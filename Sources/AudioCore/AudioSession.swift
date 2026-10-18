import Foundation
import CoreAudio
import AudioToolbox
import AudioDSP

/// All lifecycle and parameter operations run on the owning serial audio queue.
@available(macOS 14.2, *)
public final class AudioSession {
    private final class Stream {
        var tap: AudioObjectID = 0
        var aggregate: AudioObjectID = 0
        var proc: AudioDeviceIOProcID?
        var dsp: OpaquePointer?
        var units: [AudioUnit] = []
        var effectIDs: [String] = []
        var key = ""
        func stop() {
            if let proc { AudioDeviceStop(aggregate,proc); AudioDeviceDestroyIOProcID(aggregate,proc) }
            proc = nil
            if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
            if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
            for unit in units { AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }; units = []
            if let dsp { eq_destroy(dsp) }; dsp = nil
        }
        deinit { stop() }
    }
    private var streams: [Stream] = []
    private var outputVolume: OutputVolumeControl?
    private var previousOutput: AudioObjectID = 0
    private let heartbeatQueue = DispatchQueue(label: "local.melicum.driver-heartbeat")
    private var heartbeatTimer: DispatchSourceTimer?
    public private(set) var outputID: AudioObjectID = 0
    public private(set) var sourceID: AudioObjectID = 0
    public private(set) var usesSystemVolume = false
    public private(set) var rate: Double = 48000
    public var running: Bool { !streams.isEmpty }
    public init() {}
    public func start(device: OutputDevice, settings: AudioSettings, applications: [AudioApplication]) throws {
        stop()
        guard device.supported else { throw SettingsError.invalid("This version processes mono/stereo PCM. Set HDMI to 2 channels in Audio MIDI Setup.") }
        var validated = settings; try validated.validate()
        let virtual = Hardware.virtualDevice
        previousOutput = Hardware.defaultOutput == virtual ? device.id : Hardware.defaultOutput
        outputID = device.id; sourceID = virtual ?? device.id; usesSystemVolume = virtual != nil
        outputVolume = virtual == nil ? nil : OutputVolumeControl(device: device)
        do {
            if let virtual {
                try Hardware.check(Hardware.setVirtualDeviceName(virtual,outputName: device.name),"System volume bridge; install the latest component")
                try Hardware.check(Hardware.heartbeat(virtual,active: true),"System volume bridge; install the latest component")
                let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
                timer.schedule(deadline: .now(),repeating: 1)
                timer.setEventHandler { Hardware.heartbeat(virtual,active: true) }; heartbeatTimer = timer; timer.resume()
                try Hardware.setSampleRate(virtual,device.rate)
            }
            let own = Hardware.processID(ProcessInfo.processInfo.processIdentifier)
            guard own != 0 else { throw SettingsError.invalid("Could not exclude this app from the tap. Startup cancelled to prevent feedback.") }
            let custom = applications.filter { settings.appVolumes[$0.id] != nil && settings.appVolumes[$0.id] != 1 }
            let exclusions = [own] + custom.flatMap(\.processes)
            let sourceUID = virtual == nil ? device.uid : Hardware.virtualUID
            let main = try makeStream(device: device, sourceUID: sourceUID, processes: exclusions, exclusive: true, key: "", settings: settings)
            streams.append(main)
            for app in custom { streams.append(try makeStream(device: device, sourceUID: sourceUID, processes: app.processes, exclusive: false, key: app.id, settings: settings)) }
            try apply(settings)
            try Hardware.setDefault(sourceID)
            // macOS can restore a device's cached controls when it becomes the default.
            if let virtual { try Hardware.setSystemVolume(virtual,volume: settings.volume,muted: settings.muted) }
        } catch { stop(); throw error }
    }
    private func makeStream(device: OutputDevice, sourceUID: String, processes: [AudioObjectID], exclusive: Bool, key: String, settings: AudioSettings) throws -> Stream {
        let s = Stream(); s.key = key
        do {
            let desc = exclusive ? CATapDescription(excludingProcesses: processes, deviceUID: sourceUID, stream: 0) : CATapDescription(processes: processes, deviceUID: sourceUID, stream: 0)
            desc.name = "Melicum · \(key.isEmpty ? "System" : key)"; desc.uuid = UUID(); desc.isPrivate = true; desc.muteBehavior = .mutedWhenTapped
            try Hardware.check(AudioHardwareCreateProcessTap(desc,&s.tap),T("Create tap"))
            let format = Hardware.read(s.tap,kAudioTapPropertyFormat,initial: AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32, format.mChannelsPerFrame <= 2, format.mSampleRate >= 8000 else { throw SettingsError.invalid("Unsupported HDMI format. Select stereo PCM at 44.1 or 48 kHz in Audio MIDI Setup.") }
            rate = format.mSampleRate
            guard let dsp = eq_create(rate) else { throw SettingsError.invalid("Could not allocate the audio engine.") }; s.dsp = dsp
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Melicum", kAudioAggregateDeviceUIDKey: "local.melicum.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: device.uid, kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true, kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality]]
            ]
            try Hardware.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary,&s.aggregate),T("Create audio path"))
            var alive = false
            for _ in 0..<30 { if Hardware.read(s.aggregate,kAudioDevicePropertyDeviceIsAlive,initial: UInt32(0)) != 0 { alive = true; break }; Thread.sleep(forTimeInterval: 0.05) }
            guard alive else { throw SettingsError.invalid("The audio device is not responding.") }
            let tapBuffers = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(format.mChannelsPerFrame) : 1
            eq_set_tap_buffers(dsp,Int32(tapBuffers))
            for effect in settings.effects where effect.enabled {
                var componentDescription = AudioComponentDescription(componentType: effect.type, componentSubType: effect.subtype, componentManufacturer: effect.manufacturer, componentFlags: 0, componentFlagsMask: 0)
                guard let component = AudioComponentFindNext(nil,&componentDescription) else { throw SettingsError.invalid(F("Audio Unit unavailable: %@",effect.name)) }
                var unit: AudioUnit?
                try Hardware.check(AudioComponentInstanceNew(component,&unit),F("Load %@",effect.name))
                if let unit {
                    s.units.append(unit); s.effectIDs.append(effect.id); try Hardware.check(eq_add_effect(dsp,unit),F("Configure %@",effect.name))
                    for (key,value) in effect.parameters { if let id = UInt32(key) { AudioUnitSetParameter(unit,id,kAudioUnitScope_Global,0,value,0) } }
                }
            }
            configure(s,settings)
            try Hardware.check(AudioDeviceCreateIOProcID(s.aggregate,eq_io_proc(),UnsafeMutableRawPointer(dsp),&s.proc),T("Connect audio"))
            disableHardwareInputs(s, tapStreams: tapBuffers)
            try Hardware.check(AudioDeviceStart(s.aggregate,s.proc),T("Start audio"))
            return s
        } catch { s.stop(); throw error }
    }
    private func disableHardwareInputs(_ s: Stream, tapStreams: Int) {
        var a = Hardware.address(kAudioDevicePropertyIOProcStreamUsage,kAudioObjectPropertyScopeInput), size: UInt32 = 0
        guard let proc = s.proc, AudioObjectGetPropertyDataSize(s.aggregate,&a,0,nil,&size) == noErr, Int(size) >= MemoryLayout<AudioHardwareIOProcStreamUsage>.size else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment); defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self,repeating: 0,count: Int(size))
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(proc,to: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(s.aggregate,&a,0,nil,&size,raw) == noErr, let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) else { return }
        let count = Int(usage.pointee.mNumberStreams)
        guard count > tapStreams, offset + count * 4 <= size else { return }
        let flags = raw.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        for i in 0..<count { flags[i] = i >= count-tapStreams ? 1 : 0 }
        _ = AudioObjectSetPropertyData(s.aggregate,&a,0,nil,size,raw)
    }
    private func configure(_ s: Stream, _ settings: AudioSettings) {
        guard let d = s.dsp else { return }
        eq_set_band_count(d,Int32(settings.bands.count))
        for (i,b) in settings.bands.enumerated() { eq_set_band(d,Int32(i),Int32(b.type.rawValue),b.frequency,b.gain,b.q,settings.eqEnabled && b.enabled ? 1 : 0) }
        let appGain = s.key.isEmpty ? 1 : pow(settings.appVolumes[s.key] ?? 1,2)
        let gain = settings.linearGain(applyingVolume: outputVolume?.usesHardwareVolume != true)
        eq_set_controls(d,gain * appGain,settings.balance,0,settings.limiter ? 1 : 0,settings.spatialEnabled ? settings.wet : 0,settings.room,settings.spatialEnabled ? settings.width : 1)
    }
    public func apply(_ settings: AudioSettings) throws {
        try outputVolume?.apply(settings)
        for s in streams { configure(s,settings) }
    }
    public func stop() {
        if sourceID != 0, Hardware.defaultOutput == sourceID, previousOutput != 0, Hardware.devices.contains(where: { $0.id == previousOutput }) { try? Hardware.setDefault(previousOutput) }
        streams.forEach { $0.stop() }; streams.removeAll()
        heartbeatTimer?.cancel(); heartbeatTimer = nil
        if usesSystemVolume, sourceID != 0 { let device = sourceID; _ = heartbeatQueue.sync { Hardware.heartbeat(device,active: false) } }
        outputVolume = nil
        outputID = 0; sourceID = 0; previousOutput = 0; usesSystemVolume = false
    }
    public func meter() -> (left: Float, right: Float, spectrum: [Float], frames: UInt64, error: Int32) {
        var l: Float = 0, r: Float = 0, frames: UInt64 = 0, bins = [Float](repeating: -100,count: 64), error: Int32 = 0
        for s in streams { guard let d = s.dsp else { continue }; l += eq_peak(d,0); r += eq_peak(d,1); frames += eq_frames(d); error = error == 0 ? eq_render_error(d) : error
            for i in 0..<64 { bins[i] = max(bins[i],eq_spectrum(d,Int32(i))) }
        }
        return (l,r,bins,frames,error)
    }
    public func parameterList(effectID: String) -> [EffectParameter] {
        guard let s = streams.first, let index = s.effectIDs.firstIndex(of: effectID) else { return [] }
        let unit = s.units[index]; var size: UInt32 = 0
        guard AudioUnitGetPropertyInfo(unit,kAudioUnitProperty_ParameterList,kAudioUnitScope_Global,0,&size,nil) == noErr else { return [] }
        var ids = [AudioUnitParameterID](repeating: 0,count: Int(size)/4)
        guard !ids.isEmpty else { return [] }
        let status = ids.withUnsafeMutableBytes { AudioUnitGetProperty(unit,kAudioUnitProperty_ParameterList,kAudioUnitScope_Global,0,$0.baseAddress!,&size) }
        guard status == noErr else { return [] }
        return ids.compactMap { id in
            var info = AudioUnitParameterInfo(), bytes = UInt32(MemoryLayout<AudioUnitParameterInfo>.size)
            guard AudioUnitGetProperty(unit,kAudioUnitProperty_ParameterInfo,kAudioUnitScope_Global,id,&info,&bytes) == noErr, info.flags.contains(.flag_IsWritable), info.minValue.isFinite, info.maxValue.isFinite, info.maxValue > info.minValue else { return nil }
            let name = withUnsafeBytes(of: info.name) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
            var value: Float = info.defaultValue; AudioUnitGetParameter(unit,id,kAudioUnitScope_Global,0,&value)
            return EffectParameter(id: id, name: name.isEmpty ? F("Parameter %d",id) : name, min: info.minValue, max: info.maxValue, value: value)
        }
    }
    public func setParameter(effectID: String, id: UInt32, value: Float) {
        for s in streams { if let i = s.effectIDs.firstIndex(of: effectID) { AudioUnitSetParameter(s.units[i],id,kAudioUnitScope_Global,0,value,0) } }
    }
    deinit { stop() }
}

public struct EffectParameter: Identifiable {
    public var id: UInt32
    public var name: String
    public var min: Float
    public var max: Float
    public var value: Float
}
