import Foundation

public enum FocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case focus, shortBreak, longBreak
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }
    public var symbol: String { self == .focus ? "leaf" : "cup.and.saucer" }
}

public enum DialStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case ring, swiss, digital, gemstone
    public static let supported: [Self] = [.digital, .swiss, .gemstone]
    public var resolved: Self { self == .ring ? .swiss : self }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ring: return "呼吸圆环"
        case .swiss: return "瑞士表盘"
        case .digital: return "数字表盘"
        case .gemstone: return "鎏金彩晶"
        }
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public enum AmbientSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, white, pink, brown, rain, campfire
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "静音"
        case .white: return "白噪音"
        case .pink: return "粉红噪音"
        case .brown: return "红噪音"
        case .rain: return "雨声"
        case .campfire: return "篝火"
        }
    }
    public var subtitle: String {
        switch self {
        case .none: return "享受此刻的安静"
        case .white: return "均匀细密，隔开纷扰"
        case .pink: return "柔和舒缓，慢慢沉静"
        case .brown: return "低沉温暖，安心投入"
        case .rain: return "舒缓雨声"
        case .campfire: return "木柴燃烧与细碎爆裂"
        }
    }
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var sessionsBeforeLongBreak = 4
    // Compatibility-only preferences from the first mobile prototype.
    public var dailyGoal = 4
    public var dial: DialStyle = .swiss
    public var appearance: AppAppearance = .system
    public var sound: AmbientSound = .none
    public var soundBeforeMute: AmbientSound = .white
    public var volume: Float = 0.3
    public var soundOnlyDuringTimer = true
    public var campfirePreset: CampfirePreset = .crackling
    public var campfire = CampfireParameters()
    public var shouldPlayAmbientIndependently: Bool { sound != .none && !soundOnlyDuringTimer }
    public func shouldPlayAmbient(timerRunning: Bool) -> Bool {
        sound != .none && (timerRunning || !soundOnlyDuringTimer)
    }
    public var notificationsEnabled = false
    public var hapticsEnabled = true
    public var keepScreenAwake = false

    public init() {}
    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, sessionsBeforeLongBreak, dailyGoal, dial, appearance, sound, soundBeforeMute, volume, notificationsEnabled, hapticsEnabled, keepScreenAwake, soundOnlyDuringTimer, campfirePreset, campfire
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? focusMinutes
        shortBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? shortBreakMinutes
        longBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? longBreakMinutes
        sessionsBeforeLongBreak = try values.decodeIfPresent(Int.self, forKey: .sessionsBeforeLongBreak) ?? sessionsBeforeLongBreak
        dailyGoal = try values.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? dailyGoal
        dial = try values.decodeIfPresent(DialStyle.self, forKey: .dial) ?? dial
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? appearance
        sound = try values.decodeIfPresent(AmbientSound.self, forKey: .sound) ?? sound
        soundBeforeMute = try values.decodeIfPresent(AmbientSound.self, forKey: .soundBeforeMute) ?? (sound == .none ? .white : sound)
        volume = try values.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? notificationsEnabled
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? hapticsEnabled
        keepScreenAwake = try values.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? keepScreenAwake
        soundOnlyDuringTimer = try values.decodeIfPresent(Bool.self, forKey: .soundOnlyDuringTimer) ?? soundOnlyDuringTimer
        campfirePreset = try values.decodeIfPresent(CampfirePreset.self, forKey: .campfirePreset) ?? campfirePreset
        campfire = try values.decodeIfPresent(CampfireParameters.self, forKey: .campfire) ?? campfire
    }

    public func duration(for mode: FocusMode) -> Int {
        let minutes: Int
        switch mode {
        case .focus: minutes = min(120, max(1, focusMinutes))
        case .shortBreak: minutes = min(30, max(1, shortBreakMinutes))
        case .longBreak: minutes = min(60, max(1, longBreakMinutes))
        }
        return minutes * 60
    }
}

public struct TaskGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public init(id: UUID = UUID(), title: String) { self.id = id; self.title = title }
}

public struct FocusTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var groupID: UUID
    public var isPinned: Bool
    public var createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(), title: String, groupID: UUID, isPinned: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.groupID = groupID
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

public struct FocusRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var completedAt: Date
    public var durationSeconds: Int
    public var taskID: UUID?
    public var taskTitle: String?
    public init(id: UUID, completedAt: Date, durationSeconds: Int, taskID: UUID?, taskTitle: String?) {
        self.id = id
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.taskID = taskID
        self.taskTitle = taskTitle
    }
}

public enum ScheduleTint: String, CaseIterable, Codable, Identifiable, Sendable {
    case green, blue, orange, purple, rose
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .green: return "青绿"
        case .blue: return "天蓝"
        case .orange: return "暖橙"
        case .purple: return "淡紫"
        case .rose: return "玫红"
        }
    }
}

public struct WeeklyEvent: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title = ""
    /// Monday = 1, Sunday = 7, independent of the user's calendar preferences.
    public var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    public var startMinute = 9 * 60
    public var endMinute = 10 * 60
    public var tint: ScheduleTint = .green
    public init() {}

    public var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入日程名称。" }
        if weekdays.isEmpty || !weekdays.isSubset(of: Set(1...7)) { return "请至少选择一个有效的星期。" }
        if startMinute < 0 || endMinute > 1440 || startMinute >= endMinute {
            return "结束时间须晚于开始时间；跨午夜请分成两条日程。"
        }
        return nil
    }

    public func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        validationMessage == nil && weekdays.contains(ScheduleMath.weekday(date, calendar: calendar))
    }
}

public enum ScheduleMath {
    public static let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
    public static func weekday(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }
    public static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: date)
        guard let monday = calendar.date(byAdding: .day, value: 1 - weekday(start, calendar: calendar), to: start) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    public static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
    /// A wall-clock time, rather than an elapsed offset from midnight on DST days.
    public static func date(on day: Date, minute: Int, calendar: Calendar = .current) -> Date {
        if minute == 1440 {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        }
        return calendar.date(bySettingHour: max(0, min(1439, minute)) / 60,
                             minute: max(0, min(1439, minute)) % 60, second: 0,
                             of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? day
    }
}

public struct AppArchive: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var settings = FocusSettings()
    public var timer = FocusTimer()
    public var groups = [TaskGroup(title: "工作"), TaskGroup(title: "学习"), TaskGroup(title: "生活")]
    public var tasks: [FocusTask] = []
    // Retain old data without exposing these removed prototype features.
    public var events: [WeeklyEvent] = []
    public var records: [FocusRecord] = []
    public var completedFocusCount = 0
    public init() {}

    /// Keep only the desktop-style cycle count; no focus-history entries are created.
    @discardableResult
    public mutating func reconcileTimer(at now: Date) -> Bool {
        guard timer.refresh(at: now) else { return false }
        if timer.mode == .focus { completedFocusCount += 1 }
        return true
    }

    public var nextMode: FocusMode {
        if timer.mode != .focus { return .focus }
        return completedFocusCount > 0 && completedFocusCount.isMultiple(of: 4)
            ? .longBreak : .shortBreak
    }
}
