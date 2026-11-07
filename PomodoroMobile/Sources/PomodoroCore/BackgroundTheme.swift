import Foundation

enum BackgroundTheme: String, Codable, CaseIterable, Identifiable {
    case image, lakeside

    init(storedValue: String?) {
        self = storedValue == "window" ? .lakeside : Self(rawValue: storedValue ?? "") ?? .image
    }

    var id: Self { self }
    var isDynamic: Bool { self != .image }

    var title: String {
        switch self {
        case .image: "静态背景"
        case .lakeside: "湖岸昼夜"
        }
    }
}

enum BackgroundTimePreview: String, CaseIterable, Identifiable {
    case live, dawn, day, dusk, night, moonlitNight

    var id: Self { self }

    var title: String {
        switch self {
        case .live: "实时"
        case .dawn: "清晨"
        case .day: "正午"
        case .dusk: "黄昏"
        case .night: "深夜"
        case .moonlitNight: "月夜"
        }
    }

    func sky(at date: Date, coordinates: TodaySkyAstronomy.Coordinates?) -> TodaySkyAstronomy.Sky {
        let hour: Int
        switch self {
        case .live: return TodaySkyAstronomy.sky(at: date, coordinates: coordinates)
        case .dawn: hour = 6
        case .day: hour = 12
        case .dusk: hour = 18
        case .night, .moonlitNight:
            let moonlit = self == .moonlitNight
            return TodaySkyAstronomy.Sky(
                sunAltitude: -18, isMorning: true,
                moon: .init(illumination: moonlit ? 1 : 0, isWaxing: true),
                sunTrack: nil, moonTrack: moonlit ? .init(progress: 0.22, height: 0.68) : nil
            )
        }
        let calendar = Calendar.autoupdatingCurrent
        let previewDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        return TodaySkyAstronomy.sky(at: previewDate, coordinates: nil, calendar: calendar)
    }
}
