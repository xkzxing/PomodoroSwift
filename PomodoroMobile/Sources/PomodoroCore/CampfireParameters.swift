import Foundation

public enum CampfirePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case cozy, crackling, roaring, ember, woodstove
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cozy: return "温暖壁炉"
        case .crackling: return "噼啪篝火"
        case .roaring: return "旺盛营火"
        case .ember: return "余烬微光"
        case .woodstove: return "柴火炉"
        }
    }
    public var parameters: CampfireParameters {
        let values: [Double]
        switch self {
        case .cozy: values = [0.5, 0.15, 0.2, 0.35, 0.15, 0.2, 0.97, 0.9, 250, 700, 2000, 0.6, 0.08]
        case .crackling: values = [0.35, 0.2, 0.35, 0.5, 0.3, 0.4, 0.95, 0.85, 300, 900, 2500, 0.5, 0.15]
        case .roaring: values = [0.3, 0.25, 0.55, 0.6, 0.5, 0.55, 0.9, 0.75, 300, 900, 2500, 0.5, 0.25]
        case .ember: values = [0.6, 0.1, 0.1, 0.2, 0.05, 0.1, 0.98, 0.95, 200, 600, 1500, 0.7, 0.05]
        case .woodstove: values = [0.3, 0.12, 0.3, 0.55, 0.2, 0.3, 0.95, 0.88, 350, 1100, 3500, 0.7, 0.12]
        }
        return CampfireParameters(values)
    }
}

public struct CampfireParameters: Codable, Equatable, Sendable {
    public var rumble: Double = 0.4
    public var texture: Double = 0.3
    public var woodyDensity: Double = 0.3
    public var woodyLevel: Double = 0.5
    public var snapDensity: Double = 0.3
    public var snapLevel: Double = 0.35
    public var rumbleSmooth: Double = 0.95
    public var textureSmooth: Double = 0.6
    public var freqLo: Double = 300
    public var freqMid: Double = 900
    public var freqHi: Double = 2500
    public var resonance: Double = 0.5
    public var burstProb: Double = 0.12
    public init() {}
    init(_ v: [Double]) {
        rumble = v[0]; texture = v[1]; woodyDensity = v[2]; woodyLevel = v[3]
        snapDensity = v[4]; snapLevel = v[5]; rumbleSmooth = v[6]; textureSmooth = v[7]
        freqLo = v[8]; freqMid = v[9]; freqHi = v[10]; resonance = v[11]; burstProb = v[12]
    }

    public var normalized: Self {
        var result = self
        for key in [\Self.rumble, \.texture, \.woodyDensity, \.woodyLevel, \.snapDensity,
                    \.snapLevel, \.rumbleSmooth, \.textureSmooth, \.resonance, \.burstProb] {
            result[keyPath: key] = Self.clamp(result[keyPath: key], range: 0...1)
        }
        result.freqLo = Self.clamp(freqLo, range: 50...800)
        result.freqMid = Self.clamp(freqMid, range: 200...3000)
        result.freqHi = Self.clamp(freqHi, range: 500...6000)
        return result
    }
    private static func clamp(_ value: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }
}
