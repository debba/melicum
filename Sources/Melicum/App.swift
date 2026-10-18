import SwiftUI
import AppKit
import AudioCore

@available(macOS 14.2, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

@available(macOS 14.2, *)
struct MelicumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Melicum",id: "main") { MainView().environmentObject(model).environment(\.locale,Locale(identifier: model.language)).onAppear { delegate.model = model; model.activateOnLaunch() } }
            .defaultSize(width: 900,height: 900)
            .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("Melicum",systemImage: model.settings.muted ? "speaker.slash" : "slider.horizontal.3") { MenuView().environmentObject(model).environment(\.locale,Locale(identifier: model.language)) }.menuBarExtraStyle(.window)
    }
}

@main
enum Entry {
    static func main() {
        UserDefaults.standard.set([AppLanguage.current],forKey: "AppleLanguages")
        if CommandLine.arguments.contains("--list-devices") {
            for d in Hardware.devices { print("\(d.id)\t\(d.name)\t\(d.hdmi ? "HDMI/DP" : "Audio")\t\(Int(d.rate)) Hz\t\(d.channels) channels\t\(d.uid)") }
            return
        }
        if #available(macOS 14.2, *) { MelicumApp.main() }
        else { print("Melicum requires macOS 14.2 or later.") }
    }
}
