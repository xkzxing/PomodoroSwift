import XCTest
@testable import PomodoroSwift

@MainActor
final class SwissClockProgressTests: XCTestCase {
    func testRedHandRepresentsSessionProgress() {
        let progress = SwissClockProgress(totalDuration: 25 * 60, elapsedTime: 10 * 60)

        XCTAssertEqual(progress.redHandDegrees, 144, accuracy: 0.0001)
    }

    func testCompletionIsOneRedRevolutionForAnySessionLength() {
        for minutes in [3, 5, 15, 25, 45, 90] {
            let progress = SwissClockProgress(
                totalDuration: Double(minutes * 60),
                elapsedTime: Double(minutes * 60 + 100)
            )
            XCTAssertEqual(progress.redHandDegrees, 360, accuracy: 0.0001)
        }
    }

    func testEmptyAndNotYetStartedSessionsKeepRedHandAtTwelve() {
        for duration in [0.0, -10.0, 1500.0] {
            let progress = SwissClockProgress(totalDuration: duration, elapsedTime: -1)
            XCTAssertEqual(progress.redHandDegrees, 0)
        }
    }
}

@MainActor
final class SwissClockTimerTests: XCTestCase {
    func testPausedTimeAndResetStayInSyncWithCountdown() {
        let timer = PomodoroTimer(workMinutes: 25)
        timer.timeRemaining = 900

        XCTAssertEqual(timer.elapsedTime(at: .distantPast), 600)
        XCTAssertEqual(timer.elapsedTime(at: .distantFuture), 600)
        timer.reset()
        XCTAssertEqual(timer.elapsedTime(at: .now), 0)
    }

    func testRunningHandUsesWallClockAndClampsAtSessionEnd() {
        let timer = PomodoroTimer(workMinutes: 25)
        let beforeStart = Date()
        timer.start()
        let afterStart = Date()

        let elapsed = timer.elapsedTime(at: afterStart.addingTimeInterval(600))
        XCTAssertGreaterThanOrEqual(elapsed, 600)
        XCTAssertLessThanOrEqual(elapsed, 600 + afterStart.timeIntervalSince(beforeStart))
        XCTAssertEqual(timer.elapsedTime(at: .distantFuture), timer.totalDuration)

        timer.pause()
        let pausedElapsed = timer.elapsedTime(at: .now)
        XCTAssertEqual(timer.elapsedTime(at: .distantFuture), pausedElapsed)
    }

    func testBreakUsesItsOwnDurationAndStartsNewRevolutions() {
        let timer = PomodoroTimer(workMinutes: 25, breakMinutes: 5)
        timer.timeRemaining = 900
        timer.startBreak(long: false)
        timer.pause()

        XCTAssertEqual(timer.totalDuration, 300)
        XCTAssertEqual(timer.elapsedTime(at: .now), 0)
        timer.resetToWork()
        XCTAssertEqual(timer.totalDuration, 1500)
        XCTAssertEqual(timer.elapsedTime(at: .now), 0)
    }
}
