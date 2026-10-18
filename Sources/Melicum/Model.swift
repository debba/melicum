import SwiftUI
import AppKit
import AudioToolbox
import CoreAudio
import AudioCore
import UniformTypeIdentifiers
import ServiceManagement

@available(macOS 14.2, *)
final class AppModel: ObservableObject {
    @Published var settings = AudioSettings() { didSet { changed() } }
    @Published var presets: [Preset] = []
    @Published var devices: [OutputDevice] = []
    @Published var applications: [AudioApplication] = []
    @Published var effectsAvailable: [EffectSpec] = []
    @Published var parameters: [String: [EffectParameter]] = [:]
    @Published var running = false
    @Published var busy = false
    @Published var error: String?
    @Published var message = "Choose an output and enable audio."
    @Published var left: Float = 0
    @Published var right: Float = 0
    @Published var spectrum = [Float](repeating: -100,count: 64)
    @Published var frames: UInt64 = 0
    @Published var sampleRate = 48000.0
    @Published var eqMode = "Expert"
    @Published var tab = "Equalizer"
    @Published var presetName = ""
    @Published var presetAutoApp = ""
    @Published var mediaKeysEnabled = false
    @Published var systemVolumeActive = false
    @Published var driverInstalled = Hardware.virtualDevice != nil
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var enableAudioOnLaunch = UserDefaults.standard.bool(forKey: "enableAudioOnLaunch") { didSet {
        UserDefaults.standard.set(enableAudioOnLaunch,forKey: "enableAudioOnLaunch")
    } }
    @Published var language = AppLanguage.current { didSet {
        UserDefaults.standard.set(language,forKey: "interfaceLanguage")
        UserDefaults.standard.set([language],forKey: "AppleLanguages")
        message = running && selectedDevice != nil ? F("Audio active on %@",deviceName(selectedDevice!)) : T("Audio control is off")
    } }
    private let queue = DispatchQueue(label: "local.melicum.engine",qos: .userInitiated)
    private let session = AudioSession()
    private var timer: Timer?
    private var tick = 0
    private var lastAutoApp = ""
    private var saveTask: DispatchWorkItem?
    private var initialised = false
    private var handledLaunch = false
    private var launchOutputUID = ""
    private var syncingSystemVolume = false
    private var systemDeviceID: AudioObjectID = 0
    let mediaKeys = MediaKeys()
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("Melicum",isDirectory: true)
    struct Saved: Codable { var settings: AudioSettings; var presets: [Preset] }
    var selectedDevice: OutputDevice? { devices.first { $0.uid == settings.outputUID } }
    func deviceName(_ device: OutputDevice) -> String {
        let matching = devices.filter { $0.name == device.name }.sorted { $0.uid < $1.uid }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.uid == device.uid }) else { return device.name }
        return "\(device.name) · \(index+1)"
    }
    init() {
        do {
            let legacy = folder.deletingLastPathComponent().appendingPathComponent("HDMI Audio",isDirectory: true)
            if !FileManager.default.fileExists(atPath: folder.path), FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.copyItem(at: legacy,to: folder) }
            if let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")) {
                var saved = try JSONDecoder().decode(Saved.self,from: data); try saved.settings.validate()
                for var preset in saved.presets { try preset.settings.validate() }
                settings = saved.settings; presets = saved.presets
            }
        } catch { self.error = F("Invalid saved settings: %@",error.localizedDescription) }
        message = T("Choose an output and enable audio.")
        launchOutputUID = settings.outputUID
        devices = Hardware.devices; applications = Hardware.applications
        if !devices.contains(where: { $0.uid == settings.outputUID }) { settings.outputUID = devices.first(where: \.hdmi)?.uid ?? devices.first(where: { $0.id == Hardware.defaultOutput })?.uid ?? devices.first?.uid ?? "" }
        initialised = true
        mediaKeys.onKey = { [weak self] key in
            guard let self, self.running else { return }
            if key == 7 { self.settings.muted.toggle() } else { self.settings.muted = false; self.settings.volume = min(1,max(0,self.settings.volume + (key == 0 ? 0.0625 : -0.0625))) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1,repeats: true) { [weak self] _ in self?.poll() }
        scanEffects()
    }
    func activateOnLaunch() {
        guard !handledLaunch else { return }
        handledLaunch = true
        guard enableAudioOnLaunch, !launchOutputUID.isEmpty, selectedDevice?.uid == launchOutputUID else { return }
        start()
    }
    private func changed() {
        guard initialised else { return }
        if systemVolumeActive, !syncingSystemVolume {
            do { try Hardware.setSystemVolume(systemDeviceID,volume: settings.volume,muted: settings.muted) }
            catch { self.error = error.localizedDescription }
        }
        let snapshot = settings
        queue.async { self.session.apply(snapshot) }
        saveTask?.cancel(); let task = DispatchWorkItem { [weak self] in self?.save() }; saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now()+0.35,execute: task)
    }
    func save() {
        do { try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true); let data = try JSONEncoder().encode(Saved(settings: settings,presets: presets)); try data.write(to: folder.appendingPathComponent("settings.json"),options: .atomic) }
        catch { self.error = F("Could not save settings: %@",error.localizedDescription) }
    }
    func toggle() { running ? stop() : start() }
    func start() {
        guard !busy else { return }
        guard let device = selectedDevice else { error = "Connect and select an audio output."; return }
        busy = true; message = T("Starting the audio path…")
        let snapshot = settings, apps = applications
        queue.async {
            do {
                try self.session.start(device: device,settings: snapshot,applications: apps)
                let rate = self.session.rate
                let system = self.session.usesSystemVolume, source = self.session.sourceID
                var params: [String: [EffectParameter]] = [:]
                for effect in snapshot.effects { params[effect.id] = self.session.parameterList(effectID: effect.id) }
                DispatchQueue.main.async {
                    self.busy = false; self.running = true; self.sampleRate = rate; self.parameters = params
                    self.systemVolumeActive = system; self.systemDeviceID = source
                    self.message = F("Audio active on %@",self.deviceName(device)); self.error = nil
                    self.mediaKeysEnabled = system || self.mediaKeys.start(requestPermission: false)
                }
            } catch { DispatchQueue.main.async { self.busy = false; self.running = false; self.systemVolumeActive = false; self.message = T("Audio control is off"); self.error = error.localizedDescription } }
        }
    }
    func stop() {
        guard !busy else { return }; busy = true; mediaKeys.stop(); mediaKeysEnabled = false
        systemVolumeActive = false
        queue.async { self.session.stop(); DispatchQueue.main.async { self.running = false; self.busy = false; self.left = 0; self.right = 0; self.spectrum = .init(repeating: -100,count: 64); self.message = T("Audio control is off") } }
    }
    func restart() {
        guard running, !busy else { return }
        systemVolumeActive = false
        mediaKeys.stop(); mediaKeysEnabled = false; running = false; start()
    }
    func selectOutput(_ uid: String) {
        settings.outputUID = uid
        if let preset = presets.first(where: { $0.deviceUID == uid }) { let output = uid; settings = preset.settings; settings.outputUID = output }
        restart()
    }
    private func poll() {
        tick += 1
        if systemVolumeActive, running {
            if tick % 10 == 0 { Hardware.heartbeat(systemDeviceID,active: true) }
            let current = Hardware.systemVolume(systemDeviceID)
            if abs(current.volume-settings.volume) > 0.0001 || current.muted != settings.muted {
                syncingSystemVolume = true
                settings.volume = current.volume; settings.muted = current.muted
                syncingSystemVolume = false
            }
        }
        if tick % 20 == 0 {
            driverInstalled = Hardware.virtualDevice != nil
            let fresh = Hardware.devices, apps = Hardware.applications
            let processChange = applications.map { "\($0.id):\($0.processes)" } != apps.map { "\($0.id):\($0.processes)" }
            let old = selectedDevice
            devices = fresh; applications = apps
            let sourceRateChanged = systemVolumeActive && abs(Hardware.read(systemDeviceID,kAudioDevicePropertyNominalSampleRate,initial: sampleRate)-sampleRate)>1
            if running, selectedDevice == nil || old?.rate != selectedDevice?.rate || old?.channels != selectedDevice?.channels || Hardware.defaultOutput != systemDeviceID || sourceRateChanged {
                stop(); error = "The output was disconnected or the audio configuration changed. Select an output and enable audio again."
            } else if running, processChange, settings.appVolumes.contains(where: { $0.value != 1 }) { restart() }
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let audible = apps.first(where: { $0.playing && $0.id == front }) ?? apps.first(where: \.playing)
            if let audible, audible.id != lastAutoApp {
                lastAutoApp = audible.id
                if let preset = presets.first(where: { $0.applicationID == audible.id && ($0.deviceUID == nil || $0.deviceUID == settings.outputUID) }) { applyPreset(preset) }
            } else if audible == nil { lastAutoApp = "" }
        }
        guard running else { return }
        queue.async {
            let m = self.session.meter()
            DispatchQueue.main.async {
                guard self.running else { return }
                self.left = m.left; self.right = m.right; self.spectrum = m.spectrum; self.frames = m.frames
                if m.error != 0 { self.error = F("Audio Unit render error %d; its signal was bypassed.",m.error) }
            }
        }
    }
    func enableMediaKeys() {
        guard running else { error = "Enable audio first."; return }
        if systemVolumeActive { message = T("Volume follows the macOS slider and system keys."); return }
        mediaKeysEnabled = mediaKeys.start(requestPermission: true)
        if !mediaKeysEnabled { message = T("Enable this app in Privacy & Security → Accessibility, then try Volume keys again.") }
    }
    func installSystemControl() {
        guard let url = Bundle.main.url(forResource: "MelicumSystemVolume",withExtension: "pkg") else { error = T("The system volume installer is missing. Rebuild the app with scripts/build-system-volume.sh."); return }
        NSWorkspace.shared.open(url)
    }
    func loginChanged() {
        do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { self.error = F("Launch at login: %@",error.localizedDescription); launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    func appVolume(_ id: String, _ value: Double, commit: Bool) {
        settings.appVolumes[id] = value
        if commit { restart() }
    }
    func chooseMode(_ mode: String) {
        eqMode = mode
        if mode == "Basic" { settings.bands = [EQBand(type: .lowShelf,frequency: 150),EQBand(frequency: 1000,q: 0.5),EQBand(type: .highShelf,frequency: 6000)] }
        else if mode == "Advanced" { settings.bands = AudioSettings.flatBands }
    }
    func savePreset(forDevice: Bool = false) {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presets.append(Preset(name: name,settings: settings,deviceUID: forDevice ? settings.outputUID : nil,applicationID: presetAutoApp.isEmpty ? nil : presetAutoApp)); presetName = ""; save()
    }
    func applyPreset(_ preset: Preset) { let uid = settings.outputUID; settings = preset.settings; settings.outputUID = uid; eqMode = "Expert"; restart() }
    func importPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json,.plainText]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "json" { var preset = try JSONDecoder().decode(Preset.self,from: data); try preset.settings.validate(); preset.id = UUID(); presets.append(preset); applyPreset(preset) }
            else { let imported = try AutoEQImporter.parse(String(decoding: data,as: UTF8.self)); settings.bands = imported.bands; settings.preamp = imported.preamp; eqMode = "Expert" }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func exportPreset() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Melicum-preset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(Preset(name: T("Exported preset"),settings: settings)).write(to: url,options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    private func scanEffects() {
        queue.async {
            var found: [EffectSpec] = []
            for type in [kAudioUnitType_Effect,kAudioUnitType_MusicEffect] {
                var desc = AudioComponentDescription(componentType: type,componentSubType: 0,componentManufacturer: 0,componentFlags: 0,componentFlagsMask: 0)
                var current: AudioComponent?
                while let component = AudioComponentFindNext(current,&desc) {
                    current = component; var d = AudioComponentDescription(); AudioComponentGetDescription(component,&d)
                    var name: Unmanaged<CFString>?; AudioComponentCopyName(component,&name)
                    found.append(EffectSpec(type: d.componentType,subtype: d.componentSubType,manufacturer: d.componentManufacturer,name: name?.takeRetainedValue() as String? ?? "Audio Units"))
                }
            }
            let result = found.sorted { $0.name < $1.name }; DispatchQueue.main.async { self.effectsAvailable = result }
        }
    }
    func setParameter(effectID: String, id: UInt32, value: Float) {
        if let index = settings.effects.firstIndex(where: { $0.id == effectID }) { settings.effects[index].parameters[String(id)] = value }
        queue.async { self.session.setParameter(effectID: effectID,id: id,value: value) }
    }
    func shutdown() { timer?.invalidate(); mediaKeys.stop(); saveTask?.cancel(); save(); queue.sync { session.stop() } }
}
