import XCTest
@testable import PomodoroSwift

private actor CalendarProviderStub: ScheduleCalendarProviding {
    var result: ScheduleCalendarSnapshot
    private(set) var selections: [Set<String>] = []
    init(_ result: ScheduleCalendarSnapshot) { self.result = result }
    func requestAccess() -> Bool { result.authorization == .authorized }
    func snapshot(selectedIDs: Set<String>, start: Date?, end: Date?) -> ScheduleCalendarSnapshot {
        selections.append(selectedIDs)
        return result
    }
}

private actor DelayedCalendarProvider: ScheduleCalendarProviding {
    private var pending: [Int: CheckedContinuation<ScheduleCalendarSnapshot, Never>] = [:]
    private(set) var requestCount = 0
    func requestAccess() -> Bool { true }
    func snapshot(selectedIDs: Set<String>, start: Date?, end: Date?) async -> ScheduleCalendarSnapshot {
        let index = requestCount
        requestCount += 1
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, _ snapshot: ScheduleCalendarSnapshot) {
        pending.removeValue(forKey: index)?.resume(returning: snapshot)
    }
}

@MainActor
final class ScheduleCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func date(_ year: Int = 2026, _ month: Int = 8, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func event(_ start: Date, _ end: Date, calendarID: String = "selected", allDay: Bool = false,
                       cancelled: Bool = false) -> ScheduleCalendarEvent {
        ScheduleCalendarEvent(id: UUID(), calendarID: calendarID, calendarTitle: "测试日历", title: "定时会议",
                              start: start, end: end, isAllDay: allDay, isCancelled: cancelled, color: .init())
    }
    private func withDefaults(_ run: (UserDefaults) async throws -> Void) async throws {
        let suite = "ScheduleCalendarTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await run(defaults)
    }
    private func waitForRequests(_ count: Int, from provider: DelayedCalendarProvider) async {
        for _ in 0..<300 {
            if await provider.requestCount >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Calendar request did not start")
    }

    func testRollingWeekPreservesWeekdayOrderAcrossMonthBoundary() {
        let dates = WeeklyScheduleMath.visibleDates(now: date(2026, 8, 28), firstDay: .today,
                                                    includesWeekend: true, calendar: calendar)
        XCTAssertEqual(dates.first, date(2026, 8, 28))
        XCTAssertEqual(dates.last, date(2026, 9, 3))
        XCTAssertEqual(dates.map { ScheduleWeekday.from($0, calendar: calendar) },
                       [.friday, .saturday, .sunday, .monday, .tuesday, .wednesday, .thursday])
    }
    func testRollingWeekSkipsWeekendWithoutExtendingPastSevenDays() {
        let dates = WeeklyScheduleMath.visibleDates(now: date(2026, 8, 30), firstDay: .today,
                                                    includesWeekend: false, calendar: calendar)
        XCTAssertEqual(dates.first, date(2026, 8, 31))
        XCTAssertEqual(dates.last, date(2026, 9, 4))
        XCTAssertEqual(dates.count, 5)
        let monday = WeeklyScheduleMath.visibleDates(now: date(2026, 8, 30), firstDay: .monday,
                                                     includesWeekend: false, calendar: calendar)
        XCTAssertEqual(monday.first, date(2026, 8, 24))
    }
    func testRollingWeekUsesCalendarDaysAcrossDSTAndYearBoundary() {
        for now in [date(2026, 3, 7), date(2026, 10, 31), date(2026, 12, 30)] {
            let dates = WeeklyScheduleMath.visibleDates(now: now, firstDay: .today,
                                                        includesWeekend: true, calendar: calendar)
            XCTAssertEqual(dates.count, 7)
            XCTAssertEqual(Set(dates.map { ScheduleWeekday.from($0, calendar: calendar) }).count, 7)
            XCTAssertTrue(dates.allSatisfy { calendar.component(.hour, from: $0) == 0 })
            XCTAssertEqual(dates.last, calendar.date(byAdding: .day, value: 6, to: now))
        }
    }
    func testOldPreferencesMigrateWithoutLosingHoursOrLayout() throws {
        let json = Data("""
        {"isVisible":false,"includesWeekend":true,"startMinute":420,"endMinute":1380,
         "panelWidth":990,"panelHeight":680,"panelX":88,"panelY":99}
        """.utf8)
        var value = try JSONDecoder().decode(WeeklySchedulePreferences.self, from: json)
        XCTAssertEqual(value.firstDay, .monday)
        XCTAssertEqual(value.minimumFontSize, 8)
        XCTAssertFalse(value.isVisible)
        XCTAssertTrue(value.includesWeekend)
        XCTAssertEqual(value.startMinute, 420)
        XCTAssertEqual(value.endMinute, 1380)
        XCTAssertEqual(value.panelWidth, 990)
        XCTAssertEqual(value.panelHeight, 680)
        XCTAssertEqual(value.panelX, 88)
        XCTAssertEqual(value.panelY, 99)
        value.firstDay = .today
        value.minimumFontSize = 7
        XCTAssertEqual(try JSONDecoder().decode(WeeklySchedulePreferences.self, from: JSONEncoder().encode(value)), value)
    }
    func testCalendarFilteringUsesSelectionExactDatesAndTimedEventsOnly() {
        let dates = [date(2026, 8, 31)]
        let accepted = event(date(2026, 8, 31, 10), date(2026, 8, 31, 11))
        let events = [accepted,
                      event(date(2026, 8, 31, 10), date(2026, 8, 31, 11), calendarID: "other"),
                      event(date(2026, 8, 24, 10), date(2026, 8, 24, 11)),
                      event(date(2026, 9, 7, 10), date(2026, 9, 7, 11)),
                      event(date(2026, 8, 31), date(2026, 9, 1), allDay: true),
                      event(date(2026, 8, 31, 10), date(2026, 8, 31, 11), cancelled: true)]
        XCTAssertEqual(ScheduleCalendarProjection.visibleEvents(events, selectedIDs: ["selected"], dates: dates,
                                                                calendar: calendar).map(\.id), [accepted.id])
        XCTAssertTrue(ScheduleCalendarProjection.visibleEvents(events, selectedIDs: [], dates: dates, calendar: calendar).isEmpty)
    }
    func testOvernightEventsSplitIntoLocalDaysAndKeepIdentity() throws {
        let overnight = event(date(2026, 8, 31, 23, 30), date(2026, 9, 1, 1, 15))
        let monday = try XCTUnwrap(ScheduleCalendarProjection.event(overnight, on: date(2026, 8, 31), calendar: calendar))
        let tuesday = try XCTUnwrap(ScheduleCalendarProjection.event(overnight, on: date(2026, 9, 1), calendar: calendar))
        XCTAssertEqual(monday.startMinute, 1410)
        XCTAssertEqual(monday.endMinute, 1440)
        XCTAssertEqual(tuesday.startMinute, 0)
        XCTAssertEqual(tuesday.endMinute, 75)
        XCTAssertEqual(monday.id, tuesday.id)
        XCTAssertEqual(monday.weekdays, [.monday])
        XCTAssertEqual(tuesday.weekdays, [.tuesday])
    }
    func testMidnightEndDoesNotLeakIntoFollowingDayAndInvalidEventsAreIgnored() {
        let midnight = event(date(2026, 8, 31, 23), date(2026, 9, 1))
        XCTAssertNil(ScheduleCalendarProjection.event(midnight, on: date(2026, 9, 1), calendar: calendar))
        let zero = event(date(2026, 8, 31, 10), date(2026, 8, 31, 10))
        XCTAssertNil(ScheduleCalendarProjection.event(zero, on: date(2026, 8, 31), calendar: calendar))
    }
    func testCalendarAndRecurringEventsShareOverlapLanes() throws {
        let source = event(date(2026, 8, 31, 9, 30), date(2026, 8, 31, 10, 30))
        let projected = try XCTUnwrap(ScheduleCalendarProjection.event(source, on: date(2026, 8, 31), calendar: calendar))
        let recurring = WeeklyScheduleEvent(title: "固定安排", weekdays: [.monday], startMinute: 540, endMinute: 600)
        let placements = WeeklyScheduleMath.placements(events: [recurring, projected], weekday: .monday, start: 480, end: 1020)
        XCTAssertEqual(placements.map(\.columnCount), [2, 2])
        XCTAssertEqual(Set(placements.map(\.column)), [0, 1])
    }
    func testCalendarSelectionAndEnableStatePersistWithoutSavingEvents() async throws {
        try await withDefaults { defaults in
            let source = event(date(2026, 8, 31, 10), date(2026, 8, 31, 11))
            let provider = CalendarProviderStub(.init(authorization: .authorized, events: [source]))
            let store = ScheduleCalendarStore(defaults: defaults, provider: provider)
            XCTAssertTrue(store.selectedIDs.isEmpty)
            XCTAssertFalse(store.isEnabled)
            store.select("selected", enabled: true)
            store.isEnabled = true
            await store.updateDates([date(2026, 8, 31)])
            // Allow the scheduled refresh to settle as well.
            await Task.yield()
            await store.reload()
            XCTAssertEqual(store.events.map(\.id), [source.id])
            XCTAssertNil(defaults.data(forKey: WeeklyScheduleStore.eventsKey))
            let reloaded = ScheduleCalendarStore(defaults: defaults, provider: provider)
            XCTAssertEqual(reloaded.selectedIDs, ["selected"])
            XCTAssertTrue(reloaded.isEnabled)
            store.select("selected", enabled: false)
            XCTAssertTrue(store.events.isEmpty)
        }
    }
    func testDeniedPermissionProducesNoEventsAndPreservesSelection() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: ScheduleCalendarStore.enabledKey)
            defaults.set(["selected"], forKey: ScheduleCalendarStore.selectionKey)
            let provider = CalendarProviderStub(.init(authorization: .denied))
            let store = ScheduleCalendarStore(defaults: defaults, provider: provider)
            await store.updateDates([date(2026, 8, 31)])
            XCTAssertEqual(store.authorization, .denied)
            XCTAssertTrue(store.events.isEmpty)
            XCTAssertEqual(store.selectedIDs, ["selected"])
        }
    }
    func testDisabledCalendarNeverRequestsSelectedEvents() async throws {
        try await withDefaults { defaults in
            defaults.set(["selected"], forKey: ScheduleCalendarStore.selectionKey)
            let source = event(date(2026, 8, 31, 10), date(2026, 8, 31, 11))
            let provider = CalendarProviderStub(.init(authorization: .authorized, events: [source]))
            let store = ScheduleCalendarStore(defaults: defaults, provider: provider)
            await store.updateDates([date(2026, 8, 31)])
            let selections = await provider.selections
            XCTAssertEqual(selections, [[]])
            XCTAssertTrue(store.events.isEmpty)
        }
    }
    func testMissingCalendarDoesNotFallBackToAnotherSource() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: ScheduleCalendarStore.enabledKey)
            defaults.set(["missing"], forKey: ScheduleCalendarStore.selectionKey)
            let other = ScheduleCalendarSource(id: "other", title: "同名日历", accountID: "account2",
                                                accountTitle: "另一个账户", color: .init())
            let source = event(date(2026, 8, 31, 10), date(2026, 8, 31, 11), calendarID: "other")
            let provider = CalendarProviderStub(.init(authorization: .authorized, calendars: [other], events: [source]))
            let store = ScheduleCalendarStore(defaults: defaults, provider: provider)
            await store.updateDates([date(2026, 8, 31)])
            XCTAssertTrue(store.events.isEmpty)
            XCTAssertEqual(store.missingSelectionCount, 1)
            XCTAssertEqual(store.selectedIDs, ["missing"])
        }
    }
    func testStaleFetchCannotRestoreEventsAfterDisablingCalendar() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: ScheduleCalendarStore.enabledKey)
            defaults.set(["selected"], forKey: ScheduleCalendarStore.selectionKey)
            let provider = DelayedCalendarProvider()
            let store = ScheduleCalendarStore(defaults: defaults, provider: provider)
            let task = Task { await store.updateDates([date(2026, 8, 31)]) }
            await waitForRequests(1, from: provider)
            store.isEnabled = false
            await waitForRequests(2, from: provider)
            let source = event(date(2026, 8, 31, 10), date(2026, 8, 31, 11))
            await provider.complete(0, .init(authorization: .authorized, events: [source]))
            await task.value
            XCTAssertTrue(store.events.isEmpty)
            await provider.complete(1, .init(authorization: .authorized))
        }
    }
    func testNewDateWindowWinsWhenFetchesFinishOutOfOrder() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: ScheduleCalendarStore.enabledKey)
            defaults.set(["selected"], forKey: ScheduleCalendarStore.selectionKey)
            let provider = DelayedCalendarProvider()
            let store = ScheduleCalendarStore(defaults: defaults, provider: provider)
            let old = Task { await store.updateDates([date(2026, 8, 31)]) }
            await waitForRequests(1, from: provider)
            let new = Task { await store.updateDates([date(2026, 9, 7)]) }
            await waitForRequests(2, from: provider)
            let newEvent = event(date(2026, 9, 7, 10), date(2026, 9, 7, 11))
            await provider.complete(1, .init(authorization: .authorized, events: [newEvent]))
            await new.value
            let oldEvent = event(date(2026, 8, 31, 10), date(2026, 8, 31, 11))
            await provider.complete(0, .init(authorization: .authorized, events: [oldEvent]))
            await old.value
            XCTAssertEqual(store.events.map(\.id), [newEvent.id])
        }
    }
}
