import XCTest
import CoreAudio
@testable import AudioCore

final class OutputVolumeTests: XCTestCase {
    func testVirtualVolumeReachesNativeMaximumWithoutDoubleAttenuation() throws {
        var physicalVolume = 0.2, physicalMute = true
        let control = OutputVolumeControl(channels: 2,isSettable: { _, element in element == 0 },write: { selector, _, value in
            if selector == kAudioDevicePropertyVolumeScalar { physicalVolume = value }
            else { physicalMute = value != 0 }
        })
        var settings = AudioSettings()
        settings.volume = 1
        try control.apply(settings)
        XCTAssertEqual(physicalVolume,1)
        XCTAssertFalse(physicalMute)

        settings.volume = 0.5
        try control.apply(settings)
        XCTAssertEqual(physicalVolume,0.5)
        XCTAssertEqual(settings.linearGain(applyingVolume: !control.usesHardwareVolume),1)

        settings.boost = 6; settings.preamp = -3
        XCTAssertEqual(settings.linearGain(applyingVolume: !control.usesHardwareVolume),pow(10,3.0/20),accuracy: 0.000001)
        settings.muted = true
        try control.apply(settings)
        XCTAssertTrue(physicalMute)
        XCTAssertEqual(settings.linearGain(applyingVolume: !control.usesHardwareVolume),0)
    }

    func testChannelControlsWorkWithoutAMasterOrMuteControl() throws {
        var channels: [AudioObjectPropertyElement: Double] = [1: 0.2, 2: 0.3]
        let control = OutputVolumeControl(channels: 2,isSettable: { selector, element in
            selector == kAudioDevicePropertyVolumeScalar && (element == 1 || element == 2)
        },write: { selector, element, value in
            XCTAssertEqual(selector,kAudioDevicePropertyVolumeScalar)
            channels[element] = value
        })
        var settings = AudioSettings(); settings.volume = 1
        try control.apply(settings)
        XCTAssertEqual(channels,[1: 1, 2: 1])
        XCTAssertTrue(control.usesHardwareVolume)
        settings.muted = true
        XCTAssertEqual(settings.linearGain(applyingVolume: !control.usesHardwareVolume),0)
    }

    func testFixedVolumeOutputKeepsSoftwareAttenuation() throws {
        let control = OutputVolumeControl(channels: 2,isSettable: { _, _ in false },write: { _, _, _ in XCTFail("A fixed-volume output must not be written.") })
        var settings = AudioSettings(); settings.volume = 0.5
        try control.apply(settings)
        XCTAssertFalse(control.usesHardwareVolume)
        XCTAssertEqual(settings.linearGain(applyingVolume: !control.usesHardwareVolume),0.25)
    }

    func testIncompleteChannelControlsKeepSoftwareVolume() throws {
        let control = OutputVolumeControl(channels: 2,isSettable: { selector, element in
            selector == kAudioDevicePropertyVolumeScalar && element == 1
        },write: { _, _, _ in XCTFail("Partial channel controls must not disable software volume.") })
        try control.apply(AudioSettings())
        XCTAssertFalse(control.usesHardwareVolume)
    }

    func testNativeWriteFailureIsReported() {
        let control = OutputVolumeControl(channels: 1,isSettable: { _, element in element == 0 },write: { _, _, _ in
            throw SettingsError.invalid("The physical output disconnected.")
        })
        XCTAssertThrowsError(try control.apply(AudioSettings()))
    }
}
