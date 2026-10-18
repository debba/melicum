import XCTest
import Combine
@testable import Melicum

@available(macOS 14.2, *)
final class ObservationTests: XCTestCase {
    func testLiveAudioDoesNotInvalidateEditableControls() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(monitoring: false,storageFolder: folder)
        let settings = model.settings
        var controlUpdates = 0, spectrumUpdates = 0
        let controls = model.objectWillChange.sink { controlUpdates += 1 }
        let spectrum = model.meters.objectWillChange.sink { spectrumUpdates += 1 }

        for level in 1...30 {
            model.meters.update(left: Float(level)/30,right: 0,spectrum: .init(repeating: Float(level)-90,count: 64))
        }

        XCTAssertEqual(controlUpdates,0)
        XCTAssertEqual(spectrumUpdates,30)
        XCTAssertEqual(model.settings,settings)
        withExtendedLifetime((controls,spectrum)) {}
    }

    func testSilenceAndRepeatedMeterSamplesDoNotTriggerRedraws() {
        let meters = AudioMeters()
        var updates = 0
        let observation = meters.objectWillChange.sink { updates += 1 }
        meters.reset()
        XCTAssertEqual(updates,0)

        let spectrum = [Float](repeating: -30,count: 64)
        meters.update(left: 0.5,right: 0.5,spectrum: spectrum)
        for _ in 0..<30 { meters.update(left: 0.5,right: 0.5,spectrum: spectrum) }
        XCTAssertEqual(updates,1)

        meters.reset()
        meters.reset()
        XCTAssertEqual(updates,2)
        XCTAssertEqual(meters.levels.left,0)
        withExtendedLifetime(observation) {}
    }
}
