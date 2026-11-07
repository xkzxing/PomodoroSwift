import Foundation

nonisolated enum ScenePanelPhase: Equatable {
    case light, dark

    init(sky: TodaySkyAstronomy.Sky) {
        self = sky.sunAltitude < 0 || (sky.sunAltitude == 0 && !sky.isMorning) ? .dark : .light
    }
}

nonisolated enum ScenePanelColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, cyan, blue, purple, monochrome

    var id: Self { self }

    static func nearestHue(to rgb: [Double]) -> Self? {
        let channels = rgb.prefix(3)
        guard channels.count == 3, channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              let high = channels.max(), let low = channels.min(), high - low >= 0.04 else { return nil }

        let range = high - low
        let red = rgb[0], green = rgb[1], blue = rgb[2]
        let hue: Double
        if high == red {
            hue = 60 * (green - blue) / range
        } else if high == green {
            hue = 60 * (2 + (blue - red) / range)
        } else {
            hue = 60 * (4 + (red - green) / range)
        }
        let normalizedHue = hue < 0 ? hue + 360 : hue
        let anchors: [(color: Self, hue: Double)] = [
            (.red, 0), (.orange, 30), (.yellow, 58), (.green, 120), (.cyan, 177), (.blue, 229), (.purple, 286)
        ]
        func distance(to anchor: Double) -> Double {
            let difference = abs(normalizedHue - anchor)
            return min(difference, 360 - difference)
        }
        return anchors.min { distance(to: $0.hue) < distance(to: $1.hue) }?.color
    }

    func rgb(for phase: ScenePanelPhase) -> [Double] {
        let hex: Int = switch (self, phase) {
        case (.red, .light): 0xF899A4
        case (.orange, .light): 0xF8B57B
        case (.yellow, .light): 0xF6D86F
        case (.green, .light): 0x8DDB9B
        case (.cyan, .light): 0x77DAD3
        case (.blue, .light): 0x86B9F4
        case (.purple, .light): 0xC7A4EF
        case (.red, .dark): 0xA42D49
        case (.orange, .dark): 0xA65116
        case (.yellow, .dark): 0x9A8415
        case (.green, .dark): 0x24793F
        case (.cyan, .dark): 0x007B80
        case (.blue, .dark): 0x285EB2
        case (.purple, .dark): 0x783B9D
        case (.monochrome, .light): 0xFFFFFF
        case (.monochrome, .dark): 0x000000
        }
        return [16, 8, 0].map { Double((hex >> $0) & 255) / 255 }
    }
}

nonisolated struct ScenePanelColors: RawRepresentable, Equatable {
    private static let taskTints: [ScenePanelColor] = [.green, .orange, .red, .yellow, .purple, .cyan, .blue]
    static let scheduleDefault = Self(.purple)

    let tint: ScenePanelColor

    init(_ tint: ScenePanelColor) { self.tint = tint }

    init?(rawValue: String) {
        if let tint = ScenePanelColor(rawValue: rawValue) {
            self.init(tint)
            return
        }

        // Older versions stored light and dark separately. Keep the chosen dark hue.
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              ScenePanelColor(rawValue: String(parts[0])) != nil,
              let dark = ScenePanelColor(rawValue: String(parts[1])) else { return nil }
        self.init(dark)
    }

    var rawValue: String { tint.rawValue }

    static func taskDefault(at index: Int) -> Self {
        Self(taskTints[index % taskTints.count])
    }

    static func chromeDefault(defaults: UserDefaults = .standard) -> Self {
        let tint = (defaults.array(forKey: "glassTintColor") as? [Double]).flatMap(ScenePanelColor.nearestHue(to:))
        return Self(tint ?? .blue)
    }
}
