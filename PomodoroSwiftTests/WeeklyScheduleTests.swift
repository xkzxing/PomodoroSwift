import XCTest
@testable import PomodoroSwift

@MainActor
final class WeeklyScheduleTests: XCTestCase {
    private func event(_ start: Int, _ end: Int, days: Set<ScheduleWeekday> = [.monday]) -> WeeklyScheduleEvent {
        WeeklyScheduleEvent(title: "固定安排", weekdays: days, startMinute: start, endMinute: end)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int = 2026, _ month: Int = 8, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testEmptyDayIsEntirelyFree() {
        XCTAssertEqual(WeeklyScheduleMath.freeRanges(events: [], weekday: .monday, start: 480, end: 1020),
                       [ScheduleMinuteRange(start: 480, end: 1020)])
    }

    func testOverlappingAndAdjacentEventsAreOnlyCountedOnce() {
        let events = [event(500, 600), event(540, 660), event(660, 720)]
        XCTAssertEqual(WeeklyScheduleMath.busyRanges(events: events, weekday: .monday, start: 480, end: 1020),
                       [ScheduleMinuteRange(start: 500, end: 720)])
        XCTAssertEqual(WeeklyScheduleMath.freeRanges(events: events, weekday: .monday, start: 480, end: 1020),
                       [ScheduleMinuteRange(start: 480, end: 500), ScheduleMinuteRange(start: 720, end: 1020)])
    }

    func testClipsAtDisplayBoundsAndIgnoresOtherDays() {
        let events = [event(400, 540), event(1000, 1100), event(600, 660, days: [.tuesday]), event(1200, 1300)]
        XCTAssertEqual(WeeklyScheduleMath.freeRanges(events: events, weekday: .monday, start: 480, end: 1020),
                       [ScheduleMinuteRange(start: 540, end: 1000)])
    }

    func testFullDayAndEndOfDayBoundary() {
        XCTAssertTrue(WeeklyScheduleMath.freeRanges(events: [event(0, 1440)], weekday: .monday, start: 0, end: 1440).isEmpty)
        XCTAssertEqual(WeeklyScheduleMath.timeLabel(1440), "24:00")
        XCTAssertNil(event(1425, 1440).validationMessage)
        XCTAssertNotNil(event(1430, 30).validationMessage)
    }

    func testRemainingFreeTimeExcludesPastAndOngoingBusyTime() {
        let now = date(2026, 8, 31, 10, 30) // Monday
        let events = [event(600, 660)]
        let free = WeeklyScheduleMath.remainingFreeRanges(
            events: events, date: now, start: 480, end: 1020, now: now, calendar: calendar
        )
        XCTAssertEqual(free, [ScheduleMinuteRange(start: 660, end: 1020)])
        XCTAssertTrue(WeeklyScheduleMath.remainingFreeRanges(
            events: [], date: date(2026, 8, 30), start: 480, end: 1020, now: now, calendar: calendar
        ).isEmpty)
        XCTAssertEqual(WeeklyScheduleMath.remainingFreeRanges(
            events: [], date: date(2026, 9, 1), start: 480, end: 1020, now: now, calendar: calendar
        ), [ScheduleMinuteRange(start: 480, end: 1020)])
    }

    func testBeforeAndAfterVisibleHours() {
        for hour in [6, 18] {
            let now = date(2026, 8, 31, hour)
            let free = WeeklyScheduleMath.remainingFreeRanges(
                events: [], date: now, start: 480, end: 1020, now: now, calendar: calendar
            )
            XCTAssertEqual(free.reduce(0) { $0 + $1.duration }, hour == 6 ? 540 : 0)
        }
    }

    func testRemainingWeekOnlyCountsVisibleFutureDays() {
        let now = date(2026, 9, 2, 12) // Wednesday
        let dates = WeeklyScheduleMath.weekDates(containing: now, calendar: calendar)
        let events = [event(720, 780, days: [.wednesday, .thursday, .friday])]
        let remaining = dates.prefix(5).flatMap {
            WeeklyScheduleMath.remainingFreeRanges(events: events, date: $0, start: 480, end: 1020, now: now, calendar: calendar)
        }.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(remaining, 1200) // Wed 4h + Thu/Fri 8h each.
    }

    func testMondayFirstAcrossYearBoundaryAndDST() {
        let dates = WeeklyScheduleMath.weekDates(containing: date(2027, 1, 1), calendar: calendar)
        XCTAssertEqual(dates.first, date(2026, 12, 28))
        XCTAssertEqual(dates.last, date(2027, 1, 3))
        for day in [date(2026, 3, 8), date(2026, 11, 1)] {
            let week = WeeklyScheduleMath.weekDates(containing: day, calendar: calendar)
            XCTAssertEqual(week.count, 7)
            XCTAssertEqual(week.map { ScheduleWeekday.from($0, calendar: calendar) }, ScheduleWeekday.allCases)
            XCTAssertTrue(week.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        }
    }

    func testOverlapLanesAndSeparateGroups() {
        let first = event(480, 600)
        let second = event(540, 660)
        let third = event(570, 630)
        let last = event(660, 720)
        let placements = WeeklyScheduleMath.placements(events: [last, third, second, first], weekday: .monday, start: 480, end: 1020)
        XCTAssertEqual(placements.count, 4)
        XCTAssertEqual(placements.prefix(3).map(\.columnCount), [3, 3, 3])
        XCTAssertEqual(Set(placements.prefix(3).map(\.column)), Set([0, 1, 2]))
        XCTAssertEqual(placements.last?.columnCount, 1)
        XCTAssertEqual(placements.last?.column, 0)
    }

    func testInvalidEventsAreRejected() {
        var empty = event(480, 540)
        empty.title = " \n "
        XCTAssertNotNil(empty.validationMessage)
        var noDays = event(480, 540)
        noDays.weekdays = []
        XCTAssertNotNil(noDays.validationMessage)
        XCTAssertNotNil(event(600, 600).validationMessage)
        XCTAssertNotNil(event(-1, 600).validationMessage)
    }

    func testPersistenceEditingAndDeletionOfWeeklySeries() throws {
        let suite = "WeeklyScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WeeklyScheduleStore(defaults: defaults)
        var original = event(480, 540, days: [.monday, .friday, .sunday])
        XCTAssertTrue(store.save(original))
        original.title = "  修改日程  "
        original.endMinute = 600
        XCTAssertTrue(store.save(original))
        store.preferences.includesWeekend = true
        store.preferences.startMinute = 0
        store.preferences.endMinute = 1440
        store.preferences.panelWidth = 950
        store.preferences.minimumFontSize = 9
        let reloaded = WeeklyScheduleStore(defaults: defaults)
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.events.first?.title, "修改日程")
        XCTAssertEqual(reloaded.events.first?.weekdays, [.monday, .friday, .sunday])
        XCTAssertEqual(reloaded.preferences, store.preferences)
        reloaded.delete(original)
        XCTAssertTrue(WeeklyScheduleStore(defaults: defaults).events.isEmpty)
    }

    func testHidingWeekendPreservesEventsAndPreferencesAreNormalized() throws {
        let suite = "WeeklyScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WeeklyScheduleStore(defaults: defaults)
        XCTAssertTrue(store.save(event(480, 540, days: [.sunday])))
        store.preferences.includesWeekend = false
        store.preferences.startMinute = 1440
        store.preferences.endMinute = 0
        XCTAssertEqual(store.preferences.weekdays.count, 5)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.preferences.startMinute, 1425)
        XCTAssertEqual(store.preferences.endMinute, 1440)
        XCTAssertEqual(WeeklyScheduleStore(defaults: defaults).preferences, store.preferences)
    }

    func testRemovedColorsMigrateWithoutLosingSavedSchedules() throws {
        let suite = "WeeklyScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = event(480, 540, days: [.monday, .friday])
        let encoded = try JSONEncoder().encode([original])
        for (legacy, expected) in [("teal", ScheduleColor.blue), ("pink", .red)] {
            let source = String(decoding: encoded, as: UTF8.self)
                .replacingOccurrences(of: "\"blue\"", with: "\"\(legacy)\"")
            defaults.set(Data(source.utf8), forKey: WeeklyScheduleStore.eventsKey)
            let store = WeeklyScheduleStore(defaults: defaults)
            XCTAssertNil(store.storageError)
            var expectedEvent = original
            expectedEvent.color = expected
            XCTAssertEqual(store.events, [expectedEvent])
            XCTAssertTrue(store.save(expectedEvent))
            let saved = try XCTUnwrap(defaults.data(forKey: WeeklyScheduleStore.eventsKey))
            XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains(legacy))
            XCTAssertEqual(WeeklyScheduleStore(defaults: defaults).events, [expectedEvent])
        }
    }

    func testCorruptStoredEventsAreNotOverwritten() throws {
        let suite = "WeeklyScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("invalid".utf8)
        defaults.set(corrupt, forKey: WeeklyScheduleStore.eventsKey)
        let store = WeeklyScheduleStore(defaults: defaults)
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.save(event(480, 540)))
        XCTAssertEqual(defaults.data(forKey: WeeklyScheduleStore.eventsKey), corrupt)
    }
}
