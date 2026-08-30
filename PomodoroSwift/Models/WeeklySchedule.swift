import Foundation

enum ScheduleWeekday: Int, CaseIterable, Codable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }
    var title: String { ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][rawValue - 1] }

    static func from(_ date: Date, calendar: Calendar = .current) -> Self {
        Self(rawValue: (calendar.component(.weekday, from: date) + 5) % 7 + 1)!
    }
}

enum ScheduleColor: String, CaseIterable, Codable, Identifiable {
    case blue, teal, purple, orange, pink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blue: return "蓝色"
        case .teal: return "青色"
        case .purple: return "紫色"
        case .orange: return "橙色"
        case .pink: return "粉色"
        }
    }
}

struct WeeklyScheduleEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var weekdays: Set<ScheduleWeekday> = [.monday]
    var startMinute = 9 * 60
    var endMinute = 10 * 60
    var color: ScheduleColor = .blue

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入日程名称。" }
        if weekdays.isEmpty { return "请至少选择一天。" }
        if startMinute < 0 || endMinute > 1440 || startMinute >= endMinute {
            return "结束时间必须晚于开始时间。跨午夜的日程请分成两条添加。"
        }
        return nil
    }
}

struct ScheduleMinuteRange: Equatable, Identifiable {
    let start: Int
    let end: Int
    var id: Int { start }
    var duration: Int { end - start }
    var label: String { "\(WeeklyScheduleMath.timeLabel(start))—\(WeeklyScheduleMath.timeLabel(end))" }
}

struct ScheduleEventPlacement: Identifiable {
    let event: WeeklyScheduleEvent
    let range: ScheduleMinuteRange
    let column: Int
    let columnCount: Int
    var id: UUID { event.id }
}

enum WeeklyScheduleMath {
    static func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分钟" }
        if minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes / 60)小时\(minutes % 60)分"
    }

    /// Uses calendar days rather than 24-hour offsets, including across daylight saving changes.
    static func weekDates(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = ScheduleWeekday.from(day, calendar: calendar).rawValue - 1
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func busyRanges(
        events: [WeeklyScheduleEvent], weekday: ScheduleWeekday, start: Int, end: Int
    ) -> [ScheduleMinuteRange] {
        guard start < end else { return [] }
        let ranges = events.filter { $0.weekdays.contains(weekday) && $0.validationMessage == nil }
            .compactMap { event -> ScheduleMinuteRange? in
                let lower = max(start, event.startMinute)
                let upper = min(end, event.endMinute)
                return lower < upper ? ScheduleMinuteRange(start: lower, end: upper) : nil
            }
            .sorted { $0.start < $1.start }
        var merged: [ScheduleMinuteRange] = []
        for range in ranges {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = ScheduleMinuteRange(start: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func freeRanges(
        events: [WeeklyScheduleEvent], weekday: ScheduleWeekday, start: Int, end: Int
    ) -> [ScheduleMinuteRange] {
        guard start < end else { return [] }
        var cursor = start
        var free: [ScheduleMinuteRange] = []
        for busy in busyRanges(events: events, weekday: weekday, start: start, end: end) {
            if cursor < busy.start { free.append(ScheduleMinuteRange(start: cursor, end: busy.start)) }
            cursor = busy.end
        }
        if cursor < end { free.append(ScheduleMinuteRange(start: cursor, end: end)) }
        return free
    }

    static func remainingFreeRanges(
        events: [WeeklyScheduleEvent], date: Date, start: Int, end: Int,
        now: Date, calendar: Calendar = .current
    ) -> [ScheduleMinuteRange] {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard day >= today else { return [] }
        let lower = day == today ? max(start, minuteOfDay(now, calendar: calendar)) : start
        return freeRanges(
            events: events, weekday: .from(date, calendar: calendar), start: lower, end: end
        )
    }

    /// Greedy interval partitioning keeps overlapping events side by side.
    static func placements(
        events: [WeeklyScheduleEvent], weekday: ScheduleWeekday, start: Int, end: Int
    ) -> [ScheduleEventPlacement] {
        let visible = events.filter {
            $0.validationMessage == nil && $0.weekdays.contains(weekday)
                && $0.startMinute < end && $0.endMinute > start
        }.sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.endMinute != $1.endMinute { return $0.endMinute > $1.endMinute }
            return $0.id.uuidString < $1.id.uuidString
        }
        var result: [ScheduleEventPlacement] = []
        var group: [(WeeklyScheduleEvent, Int)] = []
        var laneEnds: [Int] = []
        var groupEnd = start

        func flush() {
            for (event, lane) in group {
                result.append(ScheduleEventPlacement(
                    event: event,
                    range: ScheduleMinuteRange(start: max(start, event.startMinute), end: min(end, event.endMinute)),
                    column: lane, columnCount: laneEnds.count
                ))
            }
            group = []
            laneEnds = []
        }

        for event in visible {
            if event.startMinute >= groupEnd { flush() }
            let lane = laneEnds.firstIndex(where: { $0 <= event.startMinute }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(event.endMinute) }
            else { laneEnds[lane] = event.endMinute }
            group.append((event, lane))
            groupEnd = max(groupEnd, event.endMinute)
        }
        flush()
        return result
    }
}
