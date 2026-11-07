import Foundation

enum BackgroundTheme: String, Codable, CaseIterable, Identifiable {
    case image, lakeside, mistLight

    init(storedValue: String?) {
        self = storedValue == "window" ? .lakeside : Self(rawValue: storedValue ?? "") ?? .image
    }

    var id: Self { self }
    var isDynamic: Bool { self != .image }

    var title: String {
        switch self {
        case .image: "静态背景"
        case .lakeside: "湖岸昼夜"
        case .mistLight: "雾面光场"
        }
    }
}

enum BackgroundTimePreview: String, CaseIterable, Identifiable {
    case live, dawn, day, dusk, blueHour, night, moonlitNight, custom

    static let defaultCustomMinute = 18 * 60 + 35

    static let demoCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    // A fixed local-clock day for all presets and the slider.
    static let demoDay = Date(timeIntervalSince1970: 1_753_228_800)

    var id: Self { self }

    var title: String {
        switch self {
        case .live: "实时"
        case .dawn: "清晨"
        case .day: "正午"
        case .dusk: "黄昏"
        case .blueHour: "蓝调时刻"
        case .night: "深夜"
        case .moonlitNight: "月夜"
        case .custom: "自选时刻"
        }
    }

    func date(at liveDate: Date, customMinute: Int) -> Date {
        let minute: Int
        switch self {
        case .live: return liveDate
        case .dawn: minute = 6 * 60
        case .day: minute = 12 * 60
        case .dusk: minute = 18 * 60
        case .blueHour: minute = Self.defaultCustomMinute
        case .night, .moonlitNight: minute = 23 * 60
        case .custom: minute = min(max(customMinute, 0), 1439)
        }
        return Self.demoDay.addingTimeInterval(TimeInterval(minute * 60))
    }

    func sky(at date: Date, coordinates: TodaySkyAstronomy.Coordinates?,
             customMinute: Int = Self.defaultCustomMinute) -> TodaySkyAstronomy.Sky {
        switch self {
        case .live: return TodaySkyAstronomy.sky(at: date, coordinates: coordinates)
        case .night, .moonlitNight:
            let moonlit = self == .moonlitNight
            return TodaySkyAstronomy.Sky(
                sunAltitude: -18, isMorning: true,
                moon: .init(illumination: moonlit ? 1 : 0, isWaxing: true),
                sunTrack: nil, moonTrack: moonlit ? .init(progress: 0.22, height: 0.68) : nil
            )
        case .dawn, .day, .dusk, .blueHour, .custom:
            return TodaySkyAstronomy.sky(at: self.date(at: date, customMinute: customMinute),
                                         coordinates: nil, calendar: Self.demoCalendar)
        }
    }
}
