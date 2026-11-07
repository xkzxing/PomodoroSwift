import Foundation

public enum PanelTint: String, Codable, CaseIterable, Identifiable {
    case green, blue, yellow, neutral, pink, purple
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .yellow: return "黄色"
        case .neutral: return "原色"
        case .pink: return "粉色"
        case .purple: return "紫色"
        }
    }

}

public struct PanelLook: Codable {
    public var tint: PanelTint
    public var opacity: Double = 0.38
    public var expanded: Bool = false
    public var expandedHeight = 260.0
    public init(tint: PanelTint, opacity: Double = 0.38, expanded: Bool = false) {
        self.tint = tint; self.opacity = opacity; self.expanded = expanded
    }
    private enum CodingKeys: String, CodingKey { case tint, opacity, expanded, expandedHeight }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tint = try c.decode(PanelTint.self, forKey: .tint)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.38
        expanded = try c.decodeIfPresent(Bool.self, forKey: .expanded) ?? false
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight) ?? 260
    }
}

public struct CanvasPreferences: Codable {
    public var clearGlass = false
    public var glassOpacity = 0.15
    public var interactive = true
    public var darkText = true
    public var usesPhoto = true
    public var photoPosition = 0.66
    public var panels: [String: PanelLook] = [:]
    public var glassTintRGB: [Double] = [1, 1, 1]
    public var clockSize = 300.0
    public var sectionSpacing = 26.0
    public var digitalFontName = "HelveticaNeue"
    public var digitalFontSize = 96.0
    var backgroundTheme: BackgroundTheme = .image
    var pairedGlassTint: ScenePanelColor?
    public var todayExpanded = true
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case clearGlass, glassOpacity, interactive, darkText, usesPhoto, photoPosition, panels
        case glassTintRGB, clockSize, sectionSpacing, digitalFontName, digitalFontSize
        case backgroundTheme, pairedGlassTint, todayExpanded
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clearGlass = try c.decodeIfPresent(Bool.self, forKey: .clearGlass) ?? clearGlass
        glassOpacity = try c.decodeIfPresent(Double.self, forKey: .glassOpacity) ?? glassOpacity
        interactive = try c.decodeIfPresent(Bool.self, forKey: .interactive) ?? interactive
        darkText = try c.decodeIfPresent(Bool.self, forKey: .darkText) ?? darkText
        usesPhoto = try c.decodeIfPresent(Bool.self, forKey: .usesPhoto) ?? usesPhoto
        photoPosition = try c.decodeIfPresent(Double.self, forKey: .photoPosition) ?? photoPosition
        panels = try c.decodeIfPresent([String: PanelLook].self, forKey: .panels) ?? panels
        let rgb = try c.decodeIfPresent([Double].self, forKey: .glassTintRGB) ?? [1, 1, 1]
        glassTintRGB = rgb.count == 3 && rgb.allSatisfy({ $0.isFinite && (0...1).contains($0) }) ? rgb : [1, 1, 1]
        clockSize = try c.decodeIfPresent(Double.self, forKey: .clockSize) ?? clockSize
        sectionSpacing = try c.decodeIfPresent(Double.self, forKey: .sectionSpacing) ?? sectionSpacing
        clockSize = clockSize.isFinite ? min(520, max(160, clockSize)) : 300
        sectionSpacing = sectionSpacing.isFinite ? min(72, max(8, sectionSpacing)) : 26
        digitalFontName = try c.decodeIfPresent(String.self, forKey: .digitalFontName) ?? digitalFontName
        digitalFontSize = try c.decodeIfPresent(Double.self, forKey: .digitalFontSize) ?? digitalFontSize
        digitalFontSize = digitalFontSize.isFinite ? min(160, max(32, digitalFontSize)) : 96
        backgroundTheme = BackgroundTheme(storedValue: try c.decodeIfPresent(String.self, forKey: .backgroundTheme))
        pairedGlassTint = (try c.decodeIfPresent(String.self, forKey: .pairedGlassTint)).flatMap(ScenePanelColor.init(rawValue:))
        todayExpanded = try c.decodeIfPresent(Bool.self, forKey: .todayExpanded) ?? todayExpanded
    }
}
