import XCTest
@testable import PomodoroSwift

final class PomodoroScheduleTests: XCTestCase {
    func testDurationsAreConvertedToSeconds() {
        let schedule = PomodoroSchedule(
            workMinutes: 25,
            breakMinutes: 5,
            longBreakMinutes: 15
        )

        XCTAssertEqual(schedule.duration(for: .work), 1_500)
        XCTAssertEqual(schedule.duration(for: .shortBreak), 300)
        XCTAssertEqual(schedule.duration(for: .longBreak), 900)
    }

    func testWorkSessionUsesLongBreakAtCycleBoundary() {
        let schedule = PomodoroSchedule(
            workMinutes: 25,
            breakMinutes: 5,
            longBreakMinutes: 15
        )

        XCTAssertEqual(schedule.nextMode(after: .work, completedWorkSessions: 1), .shortBreak)
        XCTAssertEqual(schedule.nextMode(after: .work, completedWorkSessions: 3), .shortBreak)
        XCTAssertEqual(schedule.nextMode(after: .work, completedWorkSessions: 4), .longBreak)
        XCTAssertEqual(schedule.nextMode(after: .work, completedWorkSessions: 8), .longBreak)
    }

    func testZeroCompletedSessionsDoesNotStartWithLongBreak() {
        let schedule = PomodoroSchedule(
            workMinutes: 25,
            breakMinutes: 5,
            longBreakMinutes: 15
        )

        XCTAssertEqual(schedule.nextMode(after: .work, completedWorkSessions: 0), .shortBreak)
    }

    func testBreakAlwaysTransitionsBackToWork() {
        let schedule = PomodoroSchedule(
            workMinutes: 25,
            breakMinutes: 5,
            longBreakMinutes: 15
        )

        XCTAssertEqual(schedule.nextMode(after: .shortBreak, completedWorkSessions: 2), .work)
        XCTAssertEqual(schedule.nextMode(after: .longBreak, completedWorkSessions: 4), .work)
    }

    func testUpdatingOneDurationPreservesOtherBreakDuration() {
        var schedule = PomodoroSchedule(
            workMinutes: 25,
            breakMinutes: 5,
            longBreakMinutes: 15
        )

        schedule.update(workMinutes: 45, breakMinutes: 10)

        XCTAssertEqual(schedule.duration(for: .work), 2_700)
        XCTAssertEqual(schedule.duration(for: .shortBreak), 600)
        XCTAssertEqual(schedule.duration(for: .longBreak), 900)
    }
}
