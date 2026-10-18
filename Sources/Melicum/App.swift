import SwiftUI
import AppKit
import AudioCore

private let menuBarIcon: NSImage = {
    let image = Bundle.main.url(forResource: "MenuBarIcon",withExtension: "tiff").flatMap { NSImage(contentsOf: $0) } ?? NSImage()
    image.size = NSSize(width: 18,height: 20)
    image.isTemplate = true
    return image
}()

@available(macOS 14.2, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

@available(macOS 14.2, *)
struct MelicumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        Window("Melicum",id: "main") { MainView().environmentObject(model).environmentObject(updater).environment(\.locale,Locale(identifier: model.language)).onAppear { delegate.model = model; model.activateOnLaunch(); updater.start() } }
            .defaultSize(width: 900,height: 900)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .appInfo) { Button(T("Check for Updates…")) { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates) }
            }
        MenuBarExtra {
            MenuView().environmentObject(model).environmentObject(updater).environment(\.locale,Locale(identifier: model.language))
        } label: {
            Image(nsImage: menuBarIcon).renderingMode(.template).accessibilityLabel("Melicum")
        }.menuBarExtraStyle(.window)
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
