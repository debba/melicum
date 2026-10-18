import XCTest
import AppKit
import SwiftUI
@testable import AudioCore
@testable import Melicum

// Render the actual SwiftUI views with isolated example data. No audio session starts.
@available(macOS 14.2, *)
final class DocumentationScreenshots: XCTestCase {
    func testCaptureDocumentation() async throws {
        try await MainActor.run {
            let root = try XCTUnwrap(ProcessInfo.processInfo.environment["MELICUM_SCREENSHOT_ROOT"])
            let destination = URL(fileURLWithPath: root).appendingPathComponent("docs/images")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let previousLanguage = UserDefaults.standard.object(forKey: "interfaceLanguage")
            let previousChecks = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks")
            defer {
                UserDefaults.standard.set(previousLanguage,forKey: "interfaceLanguage")
                UserDefaults.standard.set(previousChecks,forKey: "SUEnableAutomaticChecks")
                try? FileManager.default.removeItem(at: folder)
            }
            UserDefaults.standard.set("en",forKey: "interfaceLanguage")
            UserDefaults.standard.set(true,forKey: "SUEnableAutomaticChecks")
            NSApplication.shared.applicationIconImage = NSImage(contentsOfFile: root + "/Resources/BrandMark.png")
            let model = AppModel(monitoring: false,storageFolder: folder)
            let updater = AppUpdater()
            model.devices = [OutputDevice(id: 0,uid: "documentation.display",name: "DELL U2414H",rate: 48000,hdmi: true,channels: 2)]
            model.settings.outputUID = "documentation.display"
            model.settings.volume = 0.42
            model.settings.boost = 0
            model.settings.preamp = -3
            model.settings.bands = [EQBand(type: .lowShelf,frequency: 120,gain: 3,q: 0.71),EQBand(frequency: 1000,gain: -1.5,q: 0.9),EQBand(type: .highShelf,frequency: 8000,gain: 2,q: 0.71)]
            model.running = true
            model.driverInstalled = true
            model.sampleRate = 48000
            model.message = "Audio active on DELL U2414H"
            model.applications = [AudioApplication(id: "com.apple.Music",name: "Music",processes: [],playing: true),AudioApplication(id: "com.apple.Safari",name: "Safari",processes: [],playing: false),AudioApplication(id: "com.apple.FaceTime",name: "FaceTime",processes: [],playing: false)]
            model.settings.appVolumes = ["com.apple.Music": 0.75,"com.apple.Safari": 0.5,"com.apple.FaceTime": 1]
            let spectrum = (0..<64).map { index -> Float in
                let x = Double(index)/63
                return Float(-66 + 29*exp(-pow((x-0.22)/0.22,2)) + 12*exp(-pow((x-0.64)/0.19,2)) + 3*sin(Double(index)*1.7))
            }
            model.meters.update(left: 0.32,right: 0.28,spectrum: spectrum)
            model.presets = [Preset(name: "Desk speakers",settings: model.settings,deviceUID: model.settings.outputUID),Preset(name: "Evening",settings: model.settings,applicationID: "com.apple.Music")]

            @MainActor func capture(_ name: String, height: CGFloat) throws {
                model.systemVolumeActive = true
                defer { model.systemVolumeActive = false }
                XCTAssertNil(model.error)
                let view = MainView().environmentObject(model).environmentObject(updater).environment(\.locale,Locale(identifier: "en"))
                try render(AnyView(view),size: NSSize(width: 1000,height: height),to: destination.appendingPathComponent(name))
            }
            model.tab = "Equalizer"
            try capture("main-window.png",height: 960)
            model.tab = "App mixer"
            try capture("app-mixer.png",height: 820)
            model.tab = "Spatial audio"
            model.settings.spatialEnabled = true
            try capture("spatial-audio.png",height: 820)
            model.settings.spatialEnabled = false
            model.tab = "Audio Units"
            try capture("audio-units.png",height: 820)
            model.tab = "Presets"
            try capture("presets.png",height: 1080)
            let menu = MenuView().environmentObject(model).environmentObject(updater).environment(\.locale,Locale(identifier: "en"))
            try render(AnyView(menu),size: nil,to: destination.appendingPathComponent("menu-bar.png"))
            model.shutdown()
        }
    }

    @MainActor private func render(_ view: AnyView, size: NSSize?, to destination: URL) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.setFrameSize(size ?? host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds,to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png,properties: [:]))
        try data.write(to: destination)
        XCTAssertGreaterThan(bitmap.pixelsWide,200)
        XCTAssertGreaterThan(bitmap.pixelsHigh,200)
    }
}
