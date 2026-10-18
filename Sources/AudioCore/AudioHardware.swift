import AppKit
import CoreAudio

public enum Hardware {
    public static let virtualUID = "HDMIAudioSystem_UID"
    public static var virtualDevice: AudioObjectID? {
        // Hidden devices are discoverable by UID even when omitted from the public device list.
        var a = address(kAudioHardwarePropertyTranslateUIDToDevice)
        let uid = virtualUID as CFString
        var reference = Unmanaged.passUnretained(uid), device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withExtendedLifetime(uid) { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,UInt32(MemoryLayout.size(ofValue: reference)),&reference,&size,&device) }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
    public static func systemVolume(_ device: AudioObjectID) -> (volume: Double, muted: Bool) {
        (Double(read(device,kAudioDevicePropertyVolumeScalar,initial: Float32(1),scope: kAudioObjectPropertyScopeOutput)), read(device,kAudioDevicePropertyMute,initial: UInt32(0),scope: kAudioObjectPropertyScopeOutput) != 0)
    }
    public static func setSystemVolume(_ device: AudioObjectID, volume: Double, muted: Bool) throws {
        var gain = Float32(min(1,max(0,volume))), mute: UInt32 = muted ? 1 : 0
        var a = address(kAudioDevicePropertyVolumeScalar,kAudioObjectPropertyScopeOutput)
        try check(AudioObjectSetPropertyData(device,&a,0,nil,4,&gain),"macOS volume")
        a = address(kAudioDevicePropertyMute,kAudioObjectPropertyScopeOutput)
        try check(AudioObjectSetPropertyData(device,&a,0,nil,4,&mute),"Mute macOS")
    }
    @discardableResult public static func heartbeat(_ device: AudioObjectID, active: Bool) -> OSStatus {
        var a = address(0x68616374), pid: Int32 = active ? ProcessInfo.processInfo.processIdentifier : 0
        let value = CFNumberCreate(kCFAllocatorDefault,.sInt32Type,&pid)!
        var reference = Unmanaged.passUnretained(value)
        return withExtendedLifetime(value) { withUnsafePointer(to: &reference) { AudioObjectSetPropertyData(device,&a,0,nil,UInt32(MemoryLayout<CFNumber>.size),$0) } }
    }
    @discardableResult public static func setVirtualDeviceName(_ device: AudioObjectID, outputName: String) -> OSStatus {
        var a = address(0x6d6e616d)
        // Older components can still route audio until the bundled driver update is installed.
        guard AudioObjectHasProperty(device,&a) else { return noErr }
        let name = "\(outputName) (Melicum)" as CFString
        var reference = Unmanaged.passUnretained(name)
        return withExtendedLifetime(name) { AudioObjectSetPropertyData(device,&a,0,nil,UInt32(MemoryLayout.size(ofValue: reference)),&reference) }
    }
    public static func setSampleRate(_ device: AudioObjectID, _ rate: Double) throws {
        var a = address(kAudioDevicePropertyNominalSampleRate), value = rate
        try check(AudioObjectSetPropertyData(device,&a,0,nil,8,&value),"Sample rate")
        for _ in 0..<40 { if abs(read(device,kAudioDevicePropertyNominalSampleRate,initial: 0.0)-rate)<1 { return }; Thread.sleep(forTimeInterval: 0.025) }
        throw SettingsError.invalid("The virtual output did not accept the selected sample rate.")
    }
    public static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    public static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T {
        var a = address(selector,scope), v = initial, size = UInt32(MemoryLayout<T>.size)
        _ = withUnsafeMutablePointer(to: &v) { AudioObjectGetPropertyData(object,&a,0,nil,&size,$0) }
        return v
    }
    public static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector), v: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &v) { AudioObjectGetPropertyData(object,&a,0,nil,&size,$0) }
        guard status == noErr else { return "" }
        return v?.takeRetainedValue() as String? ?? ""
    }
    public static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = address(selector,scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object,&a,0,nil,&size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size)/MemoryLayout<AudioObjectID>.size)
        let status = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object,&a,0,nil,&size,$0.baseAddress!) }
        return status == noErr ? values : []
    }
    public static var defaultOutput: AudioObjectID { read(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDefaultOutputDevice,initial: AudioObjectID(0)) }
    public static func setDefault(_ id: AudioObjectID) throws {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice), v = id
        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,UInt32(MemoryLayout.size(ofValue: v)),&v),T("Select audio output"))
    }
    public static func processID(_ pid: pid_t) -> AudioObjectID {
        var a = address(kAudioHardwarePropertyTranslatePIDToProcessObject), p = pid, id: AudioObjectID = 0, size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,UInt32(MemoryLayout<pid_t>.size),&p,&size,&id)
        return id
    }
    public static func check(_ s: OSStatus, _ operation: String) throws {
        guard s == noErr else { throw SettingsError.invalid(F("%@: Core Audio %d. Check System Audio Recording permission in System Settings → Privacy & Security.",operation,s)) }
    }
    public static var devices: [OutputDevice] {
        objects(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDevices).compactMap { id in
            guard !objects(id,kAudioDevicePropertyStreams,scope: kAudioObjectPropertyScopeOutput).isEmpty else { return nil }
            let uid = string(id,kAudioDevicePropertyDeviceUID), name = string(id,kAudioObjectPropertyName)
            guard !uid.isEmpty, uid != virtualUID, !uid.contains("HDMIAudioSystem"), !uid.hasPrefix("local.melicum.aggregate"), read(id,kAudioDevicePropertyDeviceIsAlive,initial: UInt32(0)) != 0 else { return nil }
            let transport = read(id,kAudioDevicePropertyTransportType,initial: UInt32(0))
            let format = read(id,kAudioDevicePropertyStreamFormat,initial: AudioStreamBasicDescription(),scope: kAudioObjectPropertyScopeOutput)
            return OutputDevice(id: id, uid: uid, name: name, rate: read(id,kAudioDevicePropertyNominalSampleRate,initial: 48000.0), hdmi: transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort, channels: Int(format.mChannelsPerFrame))
        }
    }
    public static var applications: [AudioApplication] {
        let own = ProcessInfo.processInfo.processIdentifier
        var grouped: [String: AudioApplication] = [:]
        for id in objects(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyProcessObjectList) {
            let pid = read(id,kAudioProcessPropertyPID,initial: pid_t(0))
            guard pid != own, pid > 0 else { continue }
            let bundle = string(id,kAudioProcessPropertyBundleID)
            guard !bundle.hasPrefix("local.hdmiaudio") else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let key = app?.bundleIdentifier ?? (bundle.isEmpty ? "pid.\(pid)" : bundle)
            let running = read(id,kAudioProcessPropertyIsRunningOutput,initial: UInt32(0)) != 0
            if var current = grouped[key] { current.processes.append(id); current.playing = current.playing || running; grouped[key] = current }
            else { grouped[key] = AudioApplication(id: key, name: app?.localizedName ?? bundle.components(separatedBy: ".").last ?? "Processo \(pid)", processes: [id], playing: running) }
        }
        return grouped.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

public struct OutputDevice: Identifiable, Equatable {
    public var id: AudioObjectID
    public var uid: String
    public var name: String
    public var rate: Double
    public var hdmi: Bool
    public var channels: Int
    public var supported: Bool { channels == 1 || channels == 2 }
}
public struct AudioApplication: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var processes: [AudioObjectID]
    public var playing: Bool
}
