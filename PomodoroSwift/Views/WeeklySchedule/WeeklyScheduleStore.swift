import Foundation
import Combine

struct WeeklyScheduleImportResult {
    let added: [WeeklyScheduleEvent]
    let duplicateDayCount: Int
}

enum WeeklyScheduleImportError: LocalizedError {
    case invalidBatch
    case unavailable
    var errorDescription: String? {
        switch self {
        case .invalidBatch: return "日程批次包含无效数据，本次没有添加任何日程。"
        case .unavailable: return "日程存储暂时不可用，本次没有添加日程。请先检查已有日程数据。"
        }
    }
}

struct WeeklySchedulePreferences: Codable, Equatable {
    var isVisible = true
    var includesWeekend = false
    var firstDay: ScheduleFirstDay = .monday
    var startMinute = 8 * 60
    var endMinute = 17 * 60
    var minimumFontSize: Double = 8
    var panelWidth: Double = 760
    var panelHeight: Double = 520
    var panelX: Double = 24
    var panelY: Double = 300

    init() {}

    // Existing installations have no firstDay key; preserve their layout and hours.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try values.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        includesWeekend = try values.decodeIfPresent(Bool.self, forKey: .includesWeekend) ?? false
        firstDay = try values.decodeIfPresent(ScheduleFirstDay.self, forKey: .firstDay) ?? .monday
        startMinute = try values.decodeIfPresent(Int.self, forKey: .startMinute) ?? 480
        endMinute = try values.decodeIfPresent(Int.self, forKey: .endMinute) ?? 1020
        minimumFontSize = try values.decodeIfPresent(Double.self, forKey: .minimumFontSize) ?? 8
        panelWidth = try values.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 760
        panelHeight = try values.decodeIfPresent(Double.self, forKey: .panelHeight) ?? 520
        panelX = try values.decodeIfPresent(Double.self, forKey: .panelX) ?? 24
        panelY = try values.decodeIfPresent(Double.self, forKey: .panelY) ?? 300
    }

    var weekdays: [ScheduleWeekday] {
        includesWeekend ? ScheduleWeekday.allCases : Array(ScheduleWeekday.allCases.prefix(5))
    }

    mutating func normalize() {
        startMinute = min(max(startMinute, 0), 1425)
        endMinute = min(max(endMinute, startMinute + 15), 1440)
        minimumFontSize = minimumFontSize.isFinite ? min(max(minimumFontSize, 7), 11) : 8
        panelWidth = panelWidth.isFinite ? min(max(panelWidth, 360), 1600) : 760
        panelHeight = panelHeight.isFinite ? min(max(panelHeight, 320), 1200) : 520
        if !panelX.isFinite { panelX = 24 }
        if !panelY.isFinite { panelY = 300 }
    }
}

final class WeeklyScheduleStore: ObservableObject {
    static let panelID = UUID(uuidString: "A8E08136-13BA-4D78-AE37-A603C01164C9")!
    static let eventsKey = "weeklySchedule.events.v1"
    static let preferencesKey = "weeklySchedule.preferences.v1"
    private let defaults: UserDefaults
    let calendarStore: ScheduleCalendarStore

    @Published private(set) var events: [WeeklyScheduleEvent]
    @Published var preferences: WeeklySchedulePreferences {
        didSet {
            var normalized = preferences
            normalized.normalize()
            if normalized != preferences {
                preferences = normalized
            }
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Self.preferencesKey)
            }
        }
    }
    @Published private(set) var storageError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        calendarStore = ScheduleCalendarStore(defaults: defaults)
        if let data = defaults.data(forKey: Self.eventsKey) {
            if let decoded = try? JSONDecoder().decode([WeeklyScheduleEvent].self, from: data),
               decoded.allSatisfy({ $0.validationMessage == nil }),
               Set(decoded.map(\.id)).count == decoded.count {
                events = decoded
            } else {
                events = []
                storageError = "日程数据无法读取。原始数据已保留，请先备份后再恢复；暂时无法保存修改。"
            }
        } else {
            events = []
        }
        var loadedPreferences = defaults.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(WeeklySchedulePreferences.self, from: $0) }
            ?? WeeklySchedulePreferences()
        loadedPreferences.normalize()
        preferences = loadedPreferences
    }

    @discardableResult
    func save(_ event: WeeklyScheduleEvent) -> Bool {
        guard storageError == nil, event.validationMessage == nil else { return false }
        var normalized = event
        normalized.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = events
        if let index = updated.firstIndex(where: { $0.id == normalized.id }) {
            updated[index] = normalized
        } else {
            updated.append(normalized)
        }
        return persist(updated)
    }

    func delete(_ event: WeeklyScheduleEvent) {
        guard storageError == nil else { return }
        _ = persist(events.filter { $0.id != event.id })
    }

    /// Validate first, deduplicate against the latest local data, then persist once.
    /// Imported IDs are never trusted to update or replace an existing event.
    func addBatch(_ drafts: [WeeklyScheduleEvent]) throws -> WeeklyScheduleImportResult {
        guard storageError == nil else { throw WeeklyScheduleImportError.unavailable }
        guard !drafts.isEmpty, drafts.count <= 50,
              drafts.allSatisfy({ $0.validationMessage == nil && $0.title.count <= 200 }) else {
            throw WeeklyScheduleImportError.invalidBatch
        }
        var updated = events
        var added: [WeeklyScheduleEvent] = []
        var duplicateDayCount = 0
        for draft in drafts {
            var event = draft
            event.id = UUID()
            event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let matching = updated.filter {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == event.title.lowercased()
                    && $0.startMinute == event.startMinute && $0.endMinute == event.endMinute
            }
            let existingDays = Set(matching.flatMap(\.weekdays))
            duplicateDayCount += event.weekdays.intersection(existingDays).count
            event.weekdays.subtract(existingDays)
            guard !event.weekdays.isEmpty else { continue }
            updated.append(event)
            added.append(event)
        }
        if !added.isEmpty, !persist(updated) { throw WeeklyScheduleImportError.unavailable }
        return WeeklyScheduleImportResult(added: added, duplicateDayCount: duplicateDayCount)
    }

    private func persist(_ updated: [WeeklyScheduleEvent]) -> Bool {
        guard let data = try? JSONEncoder().encode(updated) else { return false }
        defaults.set(data, forKey: Self.eventsKey)
        events = updated
        return true
    }

    func resetLayout() {
        preferences.panelWidth = 760
        preferences.panelHeight = 520
        preferences.panelX = 24
        preferences.panelY = 300
    }
}
