import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    private let controller: SPUStandardUpdaterController
    private var started = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false,updaterDelegate: nil,userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).removeDuplicates().assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).removeDuplicates().assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard !started, Bundle.main.infoDictionary?["SUFeedURL"] != nil else { return }
        started = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
