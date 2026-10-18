import Foundation

public enum FilterType: Int, Codable, CaseIterable, Identifiable {
    case peak, lowShelf, highShelf, lowPass, highPass, notch, bandPass
    public var id: Int { rawValue }
    public var title: String { T(["Bell", "Low shelf", "High shelf", "Low pass", "High pass", "Notch", "Band pass"][rawValue]) }
}

public struct EQBand: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var type: FilterType = .peak
    public var frequency: Double = 1000
    public var gain: Double = 0
    public var q: Double = 0.707
    public var enabled = true
    public init(type: FilterType = .peak, frequency: Double = 1000, gain: Double = 0, q: Double = 0.707) {
        self.type = type; self.frequency = frequency; self.gain = gain; self.q = q
    }
}

public struct EffectSpec: Codable, Identifiable, Equatable {
    public var type: UInt32
    public var subtype: UInt32
    public var manufacturer: UInt32
    public var name: String
    public var enabled = true
    public var parameters: [String: Float] = [:]
    public var id: String { "\(type)-\(subtype)-\(manufacturer)" }
    public init(type: UInt32, subtype: UInt32, manufacturer: UInt32, name: String) {
        self.type = type; self.subtype = subtype; self.manufacturer = manufacturer; self.name = name
    }
}

public struct AudioSettings: Codable, Equatable {
    public var volume: Double = 0.5
    public var muted = false
    public var boost: Double = 0
    public var preamp: Double = 0
    public var balance: Double = 0
    public var eqEnabled = true
    public var limiter = true
    public var bands: [EQBand] = Self.flatBands
    public var spatialEnabled = false
    public var room: Double = 1
    public var wet: Double = 0.15
    public var width: Double = 1
    public var appVolumes: [String: Double] = [:]
    public var effects: [EffectSpec] = []
    public var outputUID = ""
    public init() {}
    public static var flatBands: [EQBand] { [31,62,125,250,500,1000,2000,4000,8000,16000].map { EQBand(frequency: Double($0)) } }
    public var linearGain: Double { linearGain(applyingVolume: true) }
    func linearGain(applyingVolume: Bool) -> Double {
        muted ? 0 : (applyingVolume ? pow(volume,2) : 1) * pow(10,(boost + preamp) / 20)
    }
    public mutating func validate() throws {
        let scalars = [volume,boost,preamp,balance,room,wet,width] + bands.flatMap { [$0.frequency,$0.gain,$0.q] } + Array(appVolumes.values)
        guard scalars.allSatisfy(\.isFinite), (0...1).contains(volume), (0...12).contains(boost), (-24...12).contains(preamp), (-1...1).contains(balance), (0...4).contains(room), (0...1).contains(wet), (0...2).contains(width), bands.count <= 64, effects.count <= 12,
              bands.allSatisfy({ (10...22000).contains($0.frequency) && (-30...30).contains($0.gain) && (0.1...20).contains($0.q) }),
              appVolumes.values.allSatisfy({ (0...1).contains($0) }), effects.allSatisfy({ $0.parameters.values.allSatisfy(\.isFinite) }), Set(bands.map(\.id)).count == bands.count, Set(effects.map(\.id)).count == effects.count else {
            throw SettingsError.invalid("The preset contains out-of-range values or too many filters/effects.")
        }
    }
}

public struct Preset: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var settings: AudioSettings
    public var deviceUID: String?
    public var applicationID: String?
    public init(name: String, settings: AudioSettings, deviceUID: String? = nil, applicationID: String? = nil) { self.name = name; self.settings = settings; self.deviceUID = deviceUID; self.applicationID = applicationID }
}

public enum SettingsError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(s) = self { return T(s) }; return nil }
}

/// REW / Equalizer APO / AutoEQ ParametricEQ text; malformed enabled filters fail the import.
public enum AutoEQImporter {
    public static func parse(_ text: String) throws -> (bands: [EQBand], preamp: Double) {
        var bands: [EQBand] = [], preamp = 0.0
        let number = "([-+]?(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+))"
        func capture(_ pattern: String, _ line: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let r = Range(m.range(at: 1), in: line) else { return nil }
            return String(line[r])
        }
        func value(_ name: String, _ line: String) -> Double? { capture("\\b" + name + "\\s+" + number, line).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } }
        for line in text.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix("preamp:") {
                guard let s = capture("Preamp:\\s*" + number,line), let n = Double(s.replacingOccurrences(of: ",", with: ".")) else { throw SettingsError.invalid("Invalid preamp value.") }
                preamp = n
            }
            guard line.range(of: "^\\s*Filter\\s+[0-9]+:", options: [.regularExpression,.caseInsensitive]) != nil else { continue }
            if line.range(of: "\\bOFF\\b", options: [.regularExpression,.caseInsensitive]) != nil { continue }
            guard let kind = capture("Filter\\s+[0-9]+:\\s*ON\\s+([A-Z]+)",line), let hz = value("Fc",line) else { throw SettingsError.invalid(F("Unrecognized filter: %@",line)) }
            let type: FilterType
            switch kind.uppercased() { case "PK","PEQ": type = .peak; case "LS","LSC": type = .lowShelf; case "HS","HSC": type = .highShelf; case "LP","LPQ": type = .lowPass; case "HP","HPQ": type = .highPass; case "NO": type = .notch; case "BP": type = .bandPass; default: throw SettingsError.invalid(F("Unsupported filter type: %@",kind)) }
            let needsGain = [.peak,.lowShelf,.highShelf].contains(type)
            guard !needsGain || value("Gain",line) != nil, type != .peak || value("Q",line) != nil else { throw SettingsError.invalid(F("Missing gain or Q: %@",line)) }
            bands.append(EQBand(type: type, frequency: hz, gain: value("Gain",line) ?? 0, q: value("Q",line) ?? 0.707))
        }
        guard !bands.isEmpty else { throw SettingsError.invalid("No filters found. Use an AutoEQ ParametricEQ or Equalizer APO file.") }
        var settings = AudioSettings(); settings.bands = bands; settings.preamp = preamp; try settings.validate()
        return (bands, preamp)
    }
}
