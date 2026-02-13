//
//  Settings.swift
//  PomodoroSwift
//

import SwiftUI
import Combine
import AppKit

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
