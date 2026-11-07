import XCTest
@testable import PomodoroSwift

@MainActor
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

@MainActor
final class PomodoroTimerRegressionTests: XCTestCase {
    func testZeroDurationCanOnlyCompleteOnce() {
        let timer = PomodoroTimer(workMinutes: 0)
        timer.start()
        timer.start()
        XCTAssertTrue(timer.isCompleted)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.sessionCount, 1)
    }

    func testSwitchingWhileRunningStartsFreshCountdown() {
        let timer = PomodoroTimer(workMinutes: 25)
        timer.start()
        timer.startBreak(long: false)
        timer.pause()
        XCTAssertEqual(timer.currentMode, .shortBreak)
        XCTAssertEqual(timer.timeRemaining, 300)
        timer.start()
        timer.startNextMode()
        timer.pause()
        XCTAssertEqual(timer.currentMode, .work)
        XCTAssertEqual(timer.timeRemaining, 1500)
    }

    func testChangingBreakDurationPreservesPausedWorkProgress() {
        let timer = PomodoroTimer(workMinutes: 25)
        timer.timeRemaining = 900
        timer.updateTime(workMinutes: 25, breakMinutes: 10)
        XCTAssertEqual(timer.timeRemaining, 900)
    }

    func testChangingPausedBreakDurationUpdatesCountdown() {
        let timer = PomodoroTimer(workMinutes: 25)
        timer.startBreak(long: false)
        timer.pause()
        timer.updateTime(workMinutes: 25, breakMinutes: 10)
        XCTAssertEqual(timer.timeRemaining, 600)
    }
}
