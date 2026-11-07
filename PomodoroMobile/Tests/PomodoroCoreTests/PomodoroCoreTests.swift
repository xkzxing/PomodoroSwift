import Foundation
import XCTest
@testable import PomodoroCore

final class PomodoroCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDefaultSessionAndProgress() {
        let timer = FocusTimer()
        XCTAssertEqual(timer.displayTime, "25:00")
        XCTAssertEqual(timer.status, .ready)
        XCTAssertEqual(timer.progress, 0)
    }

    func testDeadlineUsesWallClockAndDoesNotFinishEarly() {
        var timer = FocusTimer()
        timer.start(at: now)
        XCTAssertFalse(timer.refresh(at: now.addingTimeInterval(1499.8)))
        XCTAssertEqual(timer.remainingSeconds, 1)
        XCTAssertTrue(timer.refresh(at: now.addingTimeInterval(1500)))
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.progress, 1)
        XCTAssertFalse(timer.refresh(at: now.addingTimeInterval(2000)))
    }

    func testRepeatedStartDoesNotMoveDeadline() {
        var timer = FocusTimer()
        timer.start(at: now)
        timer.start(at: now.addingTimeInterval(100))
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(1500))
    }

    func testPausedTimeIsExcludedWhenResuming() {
        var timer = FocusTimer()
        timer.start(at: now)
        timer.pause(at: now.addingTimeInterval(100))
        XCTAssertEqual(timer.remainingSeconds, 1400)
        XCTAssertEqual(timer.status, .paused)
        XCTAssertNil(timer.deadline)
        XCTAssertFalse(timer.refresh(at: now.addingTimeInterval(2000)))
        timer.start(at: now.addingTimeInterval(2000))
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(3400))
        XCTAssertTrue(timer.refresh(at: now.addingTimeInterval(3400)))
    }

    func testRunningSessionSurvivesEncodingAndAppTermination() throws {
        var archive = AppArchive()
        archive.timer.start(at: now)
        let data = try JSONEncoder().encode(archive)
        var restored = try JSONDecoder().decode(AppArchive.self, from: data)
        XCTAssertTrue(restored.reconcileTimer(at: now.addingTimeInterval(3600)))
        XCTAssertEqual(restored.timer.completedAt, now.addingTimeInterval(1500))
        XCTAssertEqual(restored.timer.status, .completed)
        XCTAssertEqual(restored.completedFocusCount, 1)
        XCTAssertFalse(restored.reconcileTimer(at: now.addingTimeInterval(7200)))
        XCTAssertEqual(restored.completedFocusCount, 1)
        XCTAssertTrue(restored.records.isEmpty)
    }

    func testSuspendedSessionNeverCreatesPhantomCycles() {
        var archive = AppArchive()
        archive.timer.start(at: now)
        archive.reconcileTimer(at: now.addingTimeInterval(86_400 * 3))
        XCTAssertEqual(archive.completedFocusCount, 1)
        XCTAssertTrue(archive.records.isEmpty)
        XCTAssertEqual(archive.timer.status, .completed)
        XCTAssertEqual(archive.timer.mode, .focus)
    }

    func testCompletionKeepsDeadlineAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 20)))
        let nextMorning = try XCTUnwrap(calendar.date(byAdding: .hour, value: 10, to: start))
        var archive = AppArchive()
        archive.timer.start(at: start)
        archive.reconcileTimer(at: nextMorning)
        XCTAssertEqual(archive.timer.completedAt, start.addingTimeInterval(1500))
        XCTAssertEqual(archive.completedFocusCount, 1)
        XCTAssertTrue(archive.records.isEmpty)
    }

    func testFourthFocusOffersLongBreakWithoutHistory() {
        var archive = AppArchive()
        archive.settings.sessionsBeforeLongBreak = 8 // Legacy mobile option is no longer used.
        for index in 0..<4 {
            let start = now.addingTimeInterval(Double(index * 2000))
            archive.timer.prepare(mode: .focus, settings: archive.settings)
            archive.timer.start(at: start)
            archive.reconcileTimer(at: start.addingTimeInterval(1500))
            XCTAssertEqual(archive.nextMode, index == 3 ? .longBreak : .shortBreak)
        }
        archive.timer.prepare(mode: .longBreak, settings: archive.settings)
        archive.timer.start(at: now)
        archive.reconcileTimer(at: now.addingTimeInterval(900))
        XCTAssertTrue(archive.records.isEmpty)
        XCTAssertEqual(archive.completedFocusCount, 4)
        XCTAssertEqual(archive.nextMode, .focus)
    }

    func testResetDiscardsPartialSessionAndCreatesNewIdentity() {
        var archive = AppArchive()
        let oldID = archive.timer.id
        archive.timer.start(at: now)
        archive.timer.refresh(at: now.addingTimeInterval(800))
        archive.timer.prepare(mode: .focus, settings: archive.settings)
        XCTAssertNotEqual(archive.timer.id, oldID)
        XCTAssertEqual(archive.timer.remainingSeconds, 1500)
        XCTAssertEqual(archive.timer.status, .ready)
        XCTAssertTrue(archive.records.isEmpty)
    }

    func testOldHistoryIsPreservedButNoNewRecordsAreCreated() throws {
        var archive = AppArchive()
        let oldRecord = FocusRecord(id: UUID(), completedAt: now.addingTimeInterval(-2000),
                                    durationSeconds: 1500, taskID: nil, taskTitle: "旧记录")
        archive.records = [oldRecord]
        archive.timer.start(at: now)
        archive.reconcileTimer(at: now.addingTimeInterval(1500))
        XCTAssertEqual(archive.records, [oldRecord])
        XCTAssertEqual(archive.completedFocusCount, 1)
        let restored = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.records, [oldRecord])
    }

    func testDurationChangesDoNotModifyActiveSession() {
        var timer = FocusTimer()
        var settings = FocusSettings()
        timer.start(at: now)
        settings.focusMinutes = 50
        XCTAssertEqual(timer.durationSeconds, 1500)
        timer.prepare(mode: .focus, settings: settings)
        XCTAssertEqual(timer.durationSeconds, 3000)
    }

    func testInvalidDurationsAreBounded() {
        var settings = FocusSettings()
        settings.focusMinutes = -1
        settings.shortBreakMinutes = 1000
        settings.longBreakMinutes = Int.max
        XCTAssertEqual(settings.duration(for: .focus), 60)
        XCTAssertEqual(settings.duration(for: .shortBreak), 1800)
        XCTAssertEqual(settings.duration(for: .longBreak), 3600)
    }

    func testBackwardClockChangeCannotIncreaseBeyondFullDuration() {
        var timer = FocusTimer()
        timer.start(at: now)
        timer.refresh(at: now.addingTimeInterval(-3600))
        XCTAssertEqual(timer.remainingSeconds, timer.durationSeconds)
        XCTAssertEqual(timer.progress, 0)
    }

    func testFullArchiveRoundTrip() throws {
        var archive = AppArchive()
        var event = WeeklyEvent()
        event.title = "阅读"
        event.weekdays = [2, 4]
        archive.events = [event]
        archive.tasks = [FocusTask(title: " 整理书架 ", groupID: try XCTUnwrap(archive.groups.first).id)]
        archive.settings.sound = .pink
        let restored = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored, archive)
        XCTAssertEqual(restored.tasks.first?.title, "整理书架")
    }

    func testWeeklyEventValidation() {
        var event = WeeklyEvent()
        XCTAssertNotNil(event.validationMessage)
        event.title = "运动"
        XCTAssertNil(event.validationMessage)
        event.weekdays = []
        XCTAssertNotNil(event.validationMessage)
        event.weekdays = [8]
        XCTAssertNotNil(event.validationMessage)
        event.weekdays = [1]
        event.endMinute = event.startMinute
        XCTAssertNotNil(event.validationMessage)
        event.endMinute = 1441
        XCTAssertNotNil(event.validationMessage)
    }

    func testRecurringEventMatchesCalendarWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var event = WeeklyEvent()
        event.title = "周一例会"
        event.weekdays = [1]
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        XCTAssertTrue(event.occurs(on: monday, calendar: calendar))
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        XCTAssertFalse(event.occurs(on: tuesday, calendar: calendar))
    }

    func testWeekUsesCalendarDaysAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let week = ScheduleMath.week(containing: sunday, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map { ScheduleMath.weekday($0, calendar: calendar) }, Array(1...7))
        XCTAssertEqual(week.map { calendar.component(.day, from: $0) }, Array(2...8))
        XCTAssertTrue(week.allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }

    func testNoiseIsDeterministicFiniteAndBounded() {
        for sound in AmbientSound.allCases {
            let samples = NoiseGenerator.samples(sound: sound, count: 10_000)
            XCTAssertEqual(samples.count, 10_000)
            XCTAssertEqual(samples, NoiseGenerator.samples(sound: sound, count: 10_000))
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.95 })
            if sound == .none { XCTAssertTrue(samples.allSatisfy { $0 == 0 }) }
            else { XCTAssertTrue(samples.contains { abs($0) > 0.001 }) }
        }
    }

    func testScheduleTimeStaysAtNineOnDaylightSavingTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let nine = ScheduleMath.date(on: day, minute: 540, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: nine), 9)
        XCTAssertEqual(nine.timeIntervalSince(day), 8 * 3600)
    }

    func testPauseAtDeadlineCompletesCycleOnceWithoutHistory() {
        var archive = AppArchive()
        archive.timer.start(at: now)
        let deadline = now.addingTimeInterval(1500)
        archive.reconcileTimer(at: deadline)
        archive.timer.pause(at: deadline)
        XCTAssertEqual(archive.timer.status, .completed)
        XCTAssertEqual(archive.completedFocusCount, 1)
        XCTAssertTrue(archive.records.isEmpty)
        XCTAssertFalse(archive.reconcileTimer(at: deadline))
        XCTAssertEqual(archive.completedFocusCount, 1)
    }

    func testBrownNoiseHasSmootherAdjacentSamplesThanWhite() {
        func averageStep(_ samples: [Float]) -> Float {
            zip(samples.dropFirst(), samples).map { abs($0 - $1) }.reduce(0, +) / Float(samples.count - 1)
        }
        XCTAssertLessThan(averageStep(NoiseGenerator.samples(sound: .brown, count: 5000)),
                          averageStep(NoiseGenerator.samples(sound: .white, count: 5000)))
    }
}
