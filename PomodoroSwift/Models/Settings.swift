//
//  Settings.swift
//  PomodoroSwift
//

import SwiftUI
import Combine
import AppKit

enum TimerDisplayStyle: String, CaseIterable, Identifiable {
    case digital
    case swiss
    case gemstone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .digital: return "Digital"
        case .swiss: return "Swiss Clock"
        case .gemstone: return "鎏金彩晶"
        }
    }

    var isAnalog: Bool { self != .digital }
}

struct ToDoPanel: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var expandedHeight: Double

    init(id: UUID = UUID(), title: String = "To-Do", expandedHeight: Double = 180) {
        self.id = id
        self.title = title
        self.expandedHeight = expandedHeight
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case expandedHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        expandedHeight = try container.decodeIfPresent(Double.self, forKey: .expandedHeight) ?? 180
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(expandedHeight, forKey: .expandedHeight)
    }

    static func loadOrdinaryPanels(defaults: UserDefaults) -> [ToDoPanel] {
        let migrationKey = "hasMigratedTodayPanel"
        guard let data = defaults.data(forKey: "todoPanels") else {
            defaults.set(true, forKey: migrationKey)
            return [ToDoPanel()]
        }
        guard var panels = try? JSONDecoder().decode([ToDoPanel].self, from: data) else {
            return [ToDoPanel()]
        }
        guard !defaults.bool(forKey: migrationKey) else { return panels }

        let legacyMatches = panels.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Today") == .orderedSame
        }
        if let legacy = legacyMatches.first, legacyMatches.count == 1, panels.first?.id == legacy.id {
            if ToDoStore.canRemoveEmptyLegacyPanel(legacy.id, defaults: defaults) {
                panels.removeFirst()
                if panels.isEmpty { panels.append(ToDoPanel()) }
            } else {
                panels[0].title = "原今日待办"
            }
            guard let updated = try? JSONEncoder().encode(panels) else { return panels }
            defaults.set(updated, forKey: "todoPanels")
        }
        defaults.set(true, forKey: migrationKey)
        return panels
    }
}

enum CampfirePreset: String, CaseIterable {
    case cozyFireplace = "cozy"
    case cracklingCampfire = "crackling"
    case roaringBonfire = "roaring"
    case emberGlow = "ember"
    case woodStove = "woodstove"
    
    var displayName: String {
        switch self {
        case .cozyFireplace: return "🏠 Cozy Fireplace"
        case .cracklingCampfire: return "🏕️ Crackling Campfire"
        case .roaringBonfire: return "🔥 Roaring Bonfire"
        case .emberGlow: return "✨ Ember Glow"
        case .woodStove: return "🪵 Wood Stove"
        }
    }
    
    // (rumble, texture, woodyDensity, woodyLevel, snapDensity, snapLevel,
    //  rumbleSmooth, textureSmooth, freqLo, freqMid, freqHi, resonance, burstProb)
    var params: (Double, Double, Double, Double, Double, Double,
                 Double, Double, Double, Double, Double, Double, Double) {
        switch self {
        case .cozyFireplace:
            // Warn, gentle — mostly rumble with soft, sparse pops
            // Texture reduced (0.25 -> 0.15), smoother (0.7 -> 0.9)
            return (0.5, 0.15, 0.2, 0.35, 0.15, 0.2,
                    0.97, 0.9, 250.0, 700.0, 2000.0, 0.6, 0.08)
        case .cracklingCampfire:
            // Balanced — moderate crackle, distinct pops and snaps
            // Texture reduced (0.3 -> 0.2), smoother (0.55 -> 0.85)
            return (0.35, 0.2, 0.35, 0.5, 0.3, 0.4,
                    0.95, 0.85, 300.0, 900.0, 2500.0, 0.5, 0.15)
        case .roaringBonfire:
            // Aggressive — dense, loud, lots of snap and pop
            // Texture reduced (0.4 -> 0.25), smoother (0.4 -> 0.75)
            return (0.3, 0.25, 0.55, 0.6, 0.5, 0.55,
                    0.9, 0.75, 200.0, 800.0, 3000.0, 0.4, 0.25)
        case .emberGlow:
            // Very subtle — mostly warm rumble, occasional quiet pop
            // Texture reduced (0.15 -> 0.1), smoother (0.8 -> 0.95)
            return (0.6, 0.1, 0.1, 0.2, 0.05, 0.1,
                    0.98, 0.95, 200.0, 600.0, 1500.0, 0.7, 0.05)
        case .woodStove:
            // Tight, woody — prominent resonant pops, moderate density
            // Texture reduced (0.2 -> 0.12), smoother (0.6 -> 0.88)
            return (0.3, 0.12, 0.3, 0.55, 0.2, 0.3,
                    0.95, 0.88, 350.0, 1100.0, 3500.0, 0.7, 0.12)
        }
    }
}

class Settings: ObservableObject {
    @Published var timerDisplayStyle: TimerDisplayStyle {
        didSet {
            UserDefaults.standard.set(timerDisplayStyle.rawValue, forKey: "timerDisplayStyle")
        }
    }

    @Published var swissClockSize: Double {
        didSet {
            UserDefaults.standard.set(swissClockSize, forKey: "swissClockSize")
        }
    }

    @Published var selectedNSFont: NSFont {
        didSet {
            // Save font descriptor data
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: selectedNSFont.fontDescriptor, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "fontDescriptor")
            }
        }
    }
    
    @Published var backgroundTheme: BackgroundTheme {
        didSet {
            UserDefaults.standard.set(backgroundTheme.rawValue, forKey: "backgroundTheme")
        }
    }

    @Published var backgroundImageData: Data? {
        didSet {
            // Save to file system instead of UserDefaults (UserDefaults has 4MB limit)
            if let data = backgroundImageData {
                saveImageToFile(data)
            } else {
                deleteImageFile()
            }
        }
    }
    
    @Published var selectedTime: Int {
        didSet {
            UserDefaults.standard.set(selectedTime, forKey: "selectedTime")
        }
    }
    
    @Published var breakTime: Int {
        didSet {
            UserDefaults.standard.set(breakTime, forKey: "breakTime")
        }
    }
    
    @Published var longBreakTime: Int {
        didSet {
            UserDefaults.standard.set(longBreakTime, forKey: "longBreakTime")
        }
    }
    
    // Glass Effect Settings
    @Published var glassVariant: String {
        didSet {
            UserDefaults.standard.set(glassVariant, forKey: "glassVariant")
        }
    }
    
    @Published var settingsPanelColors: ScenePanelColors {
        didSet {
            UserDefaults.standard.set(settingsPanelColors.rawValue, forKey: "settingsPanelColors")
        }
    }
    
    @Published var glassTintOpacity: Double {
        didSet {
            UserDefaults.standard.set(glassTintOpacity, forKey: Self.panelGlassTintKey)
        }
    }
    
    @Published var glassInteractive: Bool {
        didSet {
            UserDefaults.standard.set(glassInteractive, forKey: "glassInteractive")
        }
    }

    var panelGlassStyle: PanelGlassStyle {
        PanelGlassStyle(variant: glassVariant, tintOpacity: glassTintOpacity, interactive: glassInteractive)
    }

    // Removed unused phantom variable glassButtonFontDark
    
    @Published var todoPanels: [ToDoPanel] {
        didSet {
            if let data = try? JSONEncoder().encode(todoPanels) {
                UserDefaults.standard.set(data, forKey: "todoPanels")
            }
        }
    }

    @Published var todoPanelGroupWidth: Double {
        didSet {
            UserDefaults.standard.set(todoPanelGroupWidth, forKey: "todoPanelGroupWidth")
        }
    }

    @Published var todoPanelGroupOffsetX: Double {
        didSet {
            UserDefaults.standard.set(todoPanelGroupOffsetX, forKey: "todoPanelGroupOffsetX")
        }
    }

    @Published var todoPanelGroupOffsetY: Double {
        didSet {
            UserDefaults.standard.set(todoPanelGroupOffsetY, forKey: "todoPanelGroupOffsetY")
        }
    }
    
    @Published var sidebarDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(sidebarDarkMode, forKey: "sidebarDarkMode")
        }
    }

    @Published var whiteNoiseEnabled: Bool {
        didSet {
            UserDefaults.standard.set(whiteNoiseEnabled, forKey: "whiteNoiseEnabled")
        }
    }

    @Published var whiteNoiseOnlyWhenTimerRunning: Bool {
        didSet {
            UserDefaults.standard.set(whiteNoiseOnlyWhenTimerRunning, forKey: "whiteNoiseOnlyWhenTimerRunning")
        }
    }
    
    @Published var whiteNoiseVolume: Double {
        didSet {
            UserDefaults.standard.set(whiteNoiseVolume, forKey: "whiteNoiseVolume")
        }
    }
    
    @Published var whiteNoiseType: String {
        didSet {
            UserDefaults.standard.set(whiteNoiseType, forKey: "whiteNoiseType")
        }
    }
    
    @Published var aiApiKey: String {
        didSet {
            UserDefaults.standard.set(aiApiKey, forKey: "aiApiKey")
        }
    }
    
    // Campfire tuning parameters (0.0 to 1.0)
    @Published var campfireRumble: Double {
        didSet { UserDefaults.standard.set(campfireRumble, forKey: "campfireRumble") }
    }
    @Published var campfireTexture: Double {
        didSet { UserDefaults.standard.set(campfireTexture, forKey: "campfireTexture") }
    }
    @Published var campfireWoodyDensity: Double {
        didSet { UserDefaults.standard.set(campfireWoodyDensity, forKey: "campfireWoodyDensity") }
    }
    @Published var campfireWoodyLevel: Double {
        didSet { UserDefaults.standard.set(campfireWoodyLevel, forKey: "campfireWoodyLevel") }
    }
    @Published var campfireSnapDensity: Double {
        didSet { UserDefaults.standard.set(campfireSnapDensity, forKey: "campfireSnapDensity") }
    }
    @Published var campfireSnapLevel: Double {
        didSet { UserDefaults.standard.set(campfireSnapLevel, forKey: "campfireSnapLevel") }
    }
    @Published var campfireRumbleSmooth: Double {
        didSet { UserDefaults.standard.set(campfireRumbleSmooth, forKey: "campfireRumbleSmooth") }
    }
    @Published var campfireTextureSmooth: Double {
        didSet { UserDefaults.standard.set(campfireTextureSmooth, forKey: "campfireTextureSmooth") }
    }
    @Published var campfireFreqLo: Double {
        didSet { UserDefaults.standard.set(campfireFreqLo, forKey: "campfireFreqLo") }
    }
    @Published var campfireFreqMid: Double {
        didSet { UserDefaults.standard.set(campfireFreqMid, forKey: "campfireFreqMid") }
    }
    @Published var campfireFreqHi: Double {
        didSet { UserDefaults.standard.set(campfireFreqHi, forKey: "campfireFreqHi") }
    }
    @Published var campfireResonance: Double {
        didSet { UserDefaults.standard.set(campfireResonance, forKey: "campfireResonance") }
    }
    @Published var campfireBurstProb: Double {
        didSet { UserDefaults.standard.set(campfireBurstProb, forKey: "campfireBurstProb") }
    }
    
    func applyCampfirePreset(_ preset: CampfirePreset) {
        let p = preset.params
        campfireRumble = p.0
        campfireTexture = p.1
        campfireWoodyDensity = p.2
        campfireWoodyLevel = p.3
        campfireSnapDensity = p.4
        campfireSnapLevel = p.5
        campfireRumbleSmooth = p.6
        campfireTextureSmooth = p.7
        campfireFreqLo = p.8
        campfireFreqMid = p.9
        campfireFreqHi = p.10
        campfireResonance = p.11
        campfireBurstProb = p.12
    }

    
    init() {
        self.timerDisplayStyle = TimerDisplayStyle(
            rawValue: UserDefaults.standard.string(forKey: "timerDisplayStyle") ?? ""
        ) ?? .digital
        let storedClockSize = Self.storedDouble("swissClockSize", defaults: .standard, fallback: 300)
        self.swissClockSize = storedClockSize.isFinite ? min(max(storedClockSize, 160), 520) : 300

        // Load saved font or use default
        if let data = UserDefaults.standard.data(forKey: "fontDescriptor"),
           let descriptor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFontDescriptor.self, from: data),
           let font = NSFont(descriptor: descriptor, size: 0) {
            self.selectedNSFont = font
        } else {
            // Default font: Helvetica Neue Regular
            self.selectedNSFont = NSFont(name: "Helvetica Neue", size: 72) ?? NSFont.systemFont(ofSize: 72)
        }
        
        self.backgroundTheme = BackgroundTheme(storedValue: UserDefaults.standard.string(forKey: "backgroundTheme"))
        self.backgroundImageData = Self.loadImageFromFile()
        self.selectedTime = UserDefaults.standard.integer(forKey: "selectedTime") != 0 
            ? UserDefaults.standard.integer(forKey: "selectedTime") 
            : 25
        
        self.breakTime = UserDefaults.standard.integer(forKey: "breakTime") != 0
            ? UserDefaults.standard.integer(forKey: "breakTime")
            : 5
        
        self.longBreakTime = UserDefaults.standard.integer(forKey: "longBreakTime") != 0
            ? UserDefaults.standard.integer(forKey: "longBreakTime")
            : 15
        
        // Load glass effect settings
        self.glassVariant = UserDefaults.standard.string(forKey: "glassVariant") ?? "regular"
        self.settingsPanelColors = UserDefaults.standard.string(forKey: "settingsPanelColors")
            .flatMap(ScenePanelColors.init(rawValue:)) ?? .chromeDefault()
        self.glassTintOpacity = Self.panelGlassTintOpacity(defaults: .standard)
        self.glassInteractive = UserDefaults.standard.bool(forKey: "glassInteractive")
        self.sidebarDarkMode = UserDefaults.standard.object(forKey: "sidebarDarkMode") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "sidebarDarkMode")

        self.todoPanelGroupWidth = UserDefaults.standard.object(forKey: "todoPanelGroupWidth") == nil
            ? 420
            : UserDefaults.standard.double(forKey: "todoPanelGroupWidth")
        self.todoPanelGroupOffsetX = UserDefaults.standard.double(forKey: "todoPanelGroupOffsetX")
        self.todoPanelGroupOffsetY = UserDefaults.standard.double(forKey: "todoPanelGroupOffsetY")
        
        self.todoPanels = ToDoPanel.loadOrdinaryPanels(defaults: .standard)
        
        // Load white noise settings
        self.whiteNoiseEnabled = UserDefaults.standard.bool(forKey: "whiteNoiseEnabled")
        self.whiteNoiseOnlyWhenTimerRunning = UserDefaults.standard.object(forKey: "whiteNoiseOnlyWhenTimerRunning") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "whiteNoiseOnlyWhenTimerRunning")
        self.whiteNoiseVolume = UserDefaults.standard.object(forKey: "whiteNoiseVolume") != nil
            ? UserDefaults.standard.double(forKey: "whiteNoiseVolume")
            : 0.3
        self.whiteNoiseType = UserDefaults.standard.string(forKey: "whiteNoiseType") ?? "white"
        self.aiApiKey = UserDefaults.standard.string(forKey: "aiApiKey") ?? ""
        
        // Load campfire tuning parameters
        self.campfireRumble = UserDefaults.standard.object(forKey: "campfireRumble") != nil
            ? UserDefaults.standard.double(forKey: "campfireRumble") : 0.4
        self.campfireTexture = UserDefaults.standard.object(forKey: "campfireTexture") != nil
            ? UserDefaults.standard.double(forKey: "campfireTexture") : 0.3
        self.campfireWoodyDensity = UserDefaults.standard.object(forKey: "campfireWoodyDensity") != nil
            ? UserDefaults.standard.double(forKey: "campfireWoodyDensity") : 0.3
        self.campfireWoodyLevel = UserDefaults.standard.object(forKey: "campfireWoodyLevel") != nil
            ? UserDefaults.standard.double(forKey: "campfireWoodyLevel") : 0.5
        self.campfireSnapDensity = UserDefaults.standard.object(forKey: "campfireSnapDensity") != nil
            ? UserDefaults.standard.double(forKey: "campfireSnapDensity") : 0.3
        self.campfireSnapLevel = UserDefaults.standard.object(forKey: "campfireSnapLevel") != nil
            ? UserDefaults.standard.double(forKey: "campfireSnapLevel") : 0.35
        self.campfireRumbleSmooth = UserDefaults.standard.object(forKey: "campfireRumbleSmooth") != nil
            ? UserDefaults.standard.double(forKey: "campfireRumbleSmooth") : 0.95
        self.campfireTextureSmooth = UserDefaults.standard.object(forKey: "campfireTextureSmooth") != nil
            ? UserDefaults.standard.double(forKey: "campfireTextureSmooth") : 0.6
        self.campfireFreqLo = UserDefaults.standard.object(forKey: "campfireFreqLo") != nil
            ? UserDefaults.standard.double(forKey: "campfireFreqLo") : 300.0
        self.campfireFreqMid = UserDefaults.standard.object(forKey: "campfireFreqMid") != nil
            ? UserDefaults.standard.double(forKey: "campfireFreqMid") : 900.0
        self.campfireFreqHi = UserDefaults.standard.object(forKey: "campfireFreqHi") != nil
            ? UserDefaults.standard.double(forKey: "campfireFreqHi") : 2500.0
        self.campfireResonance = UserDefaults.standard.object(forKey: "campfireResonance") != nil
            ? UserDefaults.standard.double(forKey: "campfireResonance") : 0.5
        self.campfireBurstProb = UserDefaults.standard.object(forKey: "campfireBurstProb") != nil
            ? UserDefaults.standard.double(forKey: "campfireBurstProb") : 0.12
    }
    
    static let systemFonts = [
        "Helvetica Neue",
        "Helvetica",
        "SF Pro Display",
        "SF Pro Text",
        "Arial",
        "Times New Roman",
        "Georgia",
        "Palatino",
        "Courier New",
        "Monaco",
        "Menlo",
        "Consolas",
        "American Typewriter",
        "Avenir",
        "Avenir Next",
        "Baskerville",
        "Didot",
        "Futura",
        "Gill Sans",
        "Hoefler Text",
        "Optima",
        "Trebuchet MS",
        "Verdana"
    ].sorted()
    
    static let fontWeights: [(String, Font.Weight, Int)] = [
        ("Thin", .thin, 100),
        ("Extra Light", .ultraLight, 200),
        ("Light", .light, 300),
        ("Regular", .regular, 400),
        ("Medium", .medium, 500),
        ("Semi Bold", .semibold, 600),
        ("Bold", .bold, 700),
        ("Extra Bold", .heavy, 800),
        ("Black", .black, 900)
    ]
    
    static let glassVariants: [(String, String)] = [
        ("常规", "regular"),
        ("清透", "clear")
    ]

    private static let panelGlassTintKey = "panelGlassTintOpacity"

    static func panelGlassTintOpacity(defaults: UserDefaults) -> Double {
        // The legacy button-only tint may increase the default, but should not mute panel colors.
        let legacy = defaults.object(forKey: "glassTintOpacity") as? Double
        let inherited = legacy.flatMap { $0.isFinite && $0 > 0 ? min($0, 1) : nil }
        let defaultOpacity = max(inherited ?? 0, PanelGlassStyle().tintOpacity)
        let saved = defaults.object(forKey: panelGlassTintKey) as? Double
        return saved.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? defaultOpacity
    }

    static func storedDouble(
        _ key: String,
        defaults: UserDefaults,
        fallback: Double
    ) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
    
    // File management for background image
    private static func backgroundImageURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let appFolder = appSupport.appendingPathComponent("PomodoroSwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("background.jpg")
    }
    
    private func saveImageToFile(_ data: Data) {
        let url = Self.backgroundImageURL()
        try? data.write(to: url)
    }
    
    private func deleteImageFile() {
        let url = Self.backgroundImageURL()
        try? FileManager.default.removeItem(at: url)
    }
    
    private static func loadImageFromFile() -> Data? {
        let url = backgroundImageURL()
        return try? Data(contentsOf: url)
    }
}
