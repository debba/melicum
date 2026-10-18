import CoreAudio

/// Uses the physical output's master control, or all of its channel controls.
/// Keeping hardware at the requested level also makes a driver fallback safe.
struct OutputVolumeControl {
    let volumeElements: [AudioObjectPropertyElement]
    let muteElements: [AudioObjectPropertyElement]
    private let write: (AudioObjectPropertySelector, AudioObjectPropertyElement, Double) throws -> Void

    var usesHardwareVolume: Bool { !volumeElements.isEmpty }

    init(channels: Int,
         isSettable: (AudioObjectPropertySelector, AudioObjectPropertyElement) -> Bool,
         write: @escaping (AudioObjectPropertySelector, AudioObjectPropertyElement, Double) throws -> Void) {
        func elements(_ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
            if isSettable(selector,kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
            let channels = (0..<channels).map { AudioObjectPropertyElement($0+1) }
            return !channels.isEmpty && channels.allSatisfy({ isSettable(selector,$0) }) ? channels : []
        }
        volumeElements = elements(kAudioDevicePropertyVolumeScalar)
        muteElements = elements(kAudioDevicePropertyMute)
        self.write = write
    }

    init(device: OutputDevice) {
        self.init(channels: device.channels,isSettable: { selector, element in
            var address = Hardware.address(selector,kAudioObjectPropertyScopeOutput)
            address.mElement = element
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(device.id,&address)
                && AudioObjectIsPropertySettable(device.id,&address,&settable) == noErr && settable.boolValue
        },write: { selector, element, value in
            var address = Hardware.address(selector,kAudioObjectPropertyScopeOutput)
            address.mElement = element
            if selector == kAudioDevicePropertyVolumeScalar {
                var scalar = Float32(value)
                try Hardware.check(AudioObjectSetPropertyData(device.id,&address,0,nil,4,&scalar),"Physical output volume")
            } else {
                var muted: UInt32 = value != 0 ? 1 : 0
                try Hardware.check(AudioObjectSetPropertyData(device.id,&address,0,nil,4,&muted),"Physical output mute")
            }
        })
    }

    func apply(_ settings: AudioSettings) throws {
        for element in volumeElements { try write(kAudioDevicePropertyVolumeScalar,element,settings.volume) }
        for element in muteElements { try write(kAudioDevicePropertyMute,element,settings.muted ? 1 : 0) }
    }
}
