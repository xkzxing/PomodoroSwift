//
//  Settings.swift
//  PomodoroSwift
//

import SwiftUI
import Combine
import AppKit

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
    @Published var selectedNSFont: NSFont {
        didSet {
            // Save font descriptor data
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: selectedNSFont.fontDescriptor, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: "fontDescriptor")
            }
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
    
    @Published var glassTintColor: Color {
        didSet {
            if let components = glassTintColor.cgColor?.components, components.count >= 3 {
                UserDefaults.standard.set([components[0], components[1], components[2]], forKey: "glassTintColor")
            }
        }
    }
    
    @Published var glassTintOpacity: Double {
        didSet {
            UserDefaults.standard.set(glassTintOpacity, forKey: "glassTintOpacity")
        }
    }
    
    @Published var glassInteractive: Bool {
        didSet {
            UserDefaults.standard.set(glassInteractive, forKey: "glassInteractive")
        }
    }

    @Published var glassButtonFontDark: Bool {
        didSet {
            UserDefaults.standard.set(glassButtonFontDark, forKey: "glassButtonFontDark")
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
    @AppStorage("whiteNoiseType") var whiteNoiseTypeRaw: String = "white"
    
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
        // Load saved font or use default
        if let data = UserDefaults.standard.data(forKey: "fontDescriptor"),
           let descriptor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFontDescriptor.self, from: data),
           let font = NSFont(descriptor: descriptor, size: 0) {
            self.selectedNSFont = font
        } else {
            // Default font: Helvetica Neue Regular
            self.selectedNSFont = NSFont(name: "Helvetica Neue", size: 72) ?? NSFont.systemFont(ofSize: 72)
        }
        
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
        if let colorArray = UserDefaults.standard.array(forKey: "glassTintColor") as? [CGFloat], colorArray.count >= 3 {
            self.glassTintColor = Color(red: colorArray[0], green: colorArray[1], blue: colorArray[2])
        } else {
            self.glassTintColor = .white
        }
        self.glassTintOpacity = UserDefaults.standard.double(forKey: "glassTintOpacity") != 0 
            ? UserDefaults.standard.double(forKey: "glassTintOpacity") 
            : 0.15
        self.glassInteractive = UserDefaults.standard.bool(forKey: "glassInteractive")
        self.glassButtonFontDark = UserDefaults.standard.object(forKey: "glassButtonFontDark") != nil
            ? UserDefaults.standard.bool(forKey: "glassButtonFontDark")
            : false
        self.sidebarDarkMode = UserDefaults.standard.object(forKey: "sidebarDarkMode") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "sidebarDarkMode")
        
        // Load white noise settings
        self.whiteNoiseEnabled = UserDefaults.standard.bool(forKey: "whiteNoiseEnabled")
        self.whiteNoiseVolume = UserDefaults.standard.object(forKey: "whiteNoiseVolume") != nil
            ? UserDefaults.standard.double(forKey: "whiteNoiseVolume")
            : 0.3
        self.whiteNoiseType = UserDefaults.standard.string(forKey: "whiteNoiseType") ?? "white"
        
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
        ("Regular", "regular"),
        ("Clear (Subtle)", "clear")
    ]
    
    // File management for background image
    private static func backgroundImageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
