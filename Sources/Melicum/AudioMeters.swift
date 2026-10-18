import Combine

// Meter updates belong to the spectrum view, not to the editable audio controls.
final class AudioMeters: ObservableObject {
    struct Levels: Equatable {
        var left: Float = 0
        var right: Float = 0
        var spectrum = [Float](repeating: -100, count: 64)
    }

    @Published private(set) var levels = Levels()

    func update(left: Float, right: Float, spectrum: [Float]) {
        let next = Levels(left: left, right: right, spectrum: spectrum)
        if levels != next { levels = next }
    }

    func reset() {
        if levels != Levels() { levels = Levels() }
    }
}
