import Foundation
import XCTest
@testable import PomodoroSwift

final class LakeDayScheduleTests: XCTestCase {
    func testDemoBoatMakesTwoContinuousTripsOnTheSameRoute() throws {
        let schedule = demoSchedule
        let outbound = try XCTUnwrap(schedule.outbound)
        let inbound = try XCTUnwrap(schedule.inbound)

        XCTAssertEqual(outbound.end.timeIntervalSince(outbound.start), 3 * 3600)
        XCTAssertEqual(inbound.end.timeIntervalSince(inbound.start), 3 * 3600)
        XCTAssertNil(schedule.motion(at: outbound.start.addingTimeInterval(-1)).boat)
        XCTAssertEqual(schedule.motion(at: outbound.start).boat?.position, 0)
        XCTAssertEqual(schedule.motion(at: demoTime(10, 45)).boat?.position, 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(schedule.motion(at: demoTime(11, 45)).boat).position, 0.5)
        XCTAssertNil(schedule.motion(at: outbound.end).boat)
        XCTAssertEqual(schedule.motion(at: inbound.start).boat?.position, 1)
        XCTAssertEqual(schedule.motion(at: demoTime(18, 45)).boat?.position, 0.5)
        XCTAssertTrue(try XCTUnwrap(schedule.motion(at: demoTime(18, 45)).boat).returning)
        XCTAssertLessThan(try XCTUnwrap(schedule.motion(at: demoTime(19, 45)).boat).position, 0.5)
        XCTAssertNil(schedule.motion(at: inbound.end).boat)
    }

    func testRealDaysAreStableAcrossRelaunchesButVaryByDate() {
        let calendar = BackgroundTimePreview.demoCalendar
        let firstDay = BackgroundTimePreview.demoDay
        var startMinutes = Set<Int>()
        var quietDays = 0
        for offset in 0..<60 {
            let date = firstDay.addingTimeInterval(TimeInterval(offset * 86_400))
            let schedule = LakeDaySchedule(at: date, calendar: calendar)
            let reopened = LakeDaySchedule(at: date.addingTimeInterval(17 * 3600), calendar: calendar)
            XCTAssertEqual(schedule, reopened)
            XCTAssertEqual(schedule.outbound == nil, schedule.inbound == nil)
            if let start = schedule.outbound?.start {
                startMinutes.insert(Int(start.timeIntervalSince(date) / 60))
            } else {
                quietDays += 1
            }
            XCTAssertFalse(schedule.covers(schedule.day.end, calendar: calendar))
        }
        XCTAssertGreaterThan(quietDays, 0)
        XCTAssertGreaterThan(startMinutes.count, 1)
    }

    func testRepeatedHourBelongsToOneDayAndTripsUseElapsedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let first = try utc("2026-11-01T05:30:00Z")
        let repeated = try utc("2026-11-01T06:30:00Z")
        let schedule = LakeDaySchedule(at: first, calendar: calendar, demo: true)
        XCTAssertTrue(schedule.covers(repeated, calendar: calendar))
        XCTAssertEqual(schedule, LakeDaySchedule(at: repeated, calendar: calendar, demo: true))
        XCTAssertEqual(schedule.day.duration, 25 * 3600)
        let outbound = try XCTUnwrap(schedule.outbound)
        XCTAssertEqual(outbound.start, try utc("2026-11-01T14:15:00Z"))
        XCTAssertEqual(outbound.end.timeIntervalSince(outbound.start), 3 * 3600)
        XCTAssertEqual(schedule.motion(at: outbound.start.addingTimeInterval(3600)),
                       schedule.motion(at: try utc("2026-11-01T15:15:00Z")))
        let spring = LakeDaySchedule(at: try utc("2026-03-08T06:30:00Z"), calendar: calendar, demo: true)
        XCTAssertEqual(spring.day.duration, 23 * 3600)
        XCTAssertEqual(spring.outbound?.start, try utc("2026-03-08T13:15:00Z"))
    }

    func testPorchTakesOverAtArrivalAndWindowLightsGoOut() throws {
        let schedule = demoSchedule
        let visitor = try XCTUnwrap(schedule.lanternVisitor)
        XCTAssertEqual(schedule.motion(at: visitor.start).porch, 0)
        XCTAssertNotNil(schedule.motion(at: visitor.end.addingTimeInterval(-1)).lanternVisitor)
        XCTAssertNil(schedule.motion(at: visitor.end).lanternVisitor)
        XCTAssertEqual(schedule.motion(at: visitor.end.addingTimeInterval(-30)).porch, 0.5)
        XCTAssertEqual(schedule.motion(at: visitor.end).porch, 1)
        XCTAssertEqual(schedule.motion(at: visitor.end.addingTimeInterval(1800)).porch, 0)
        XCTAssertEqual(schedule.windowLight(at: demoTime(19, 0)), 1)
        XCTAssertEqual(schedule.windowLight(at: demoTime(23, 0)), 0)
        XCTAssertEqual(LakeDaySchedule.detailVisibility(sunAltitude: 0), 1)
        XCTAssertEqual(LakeDaySchedule.detailVisibility(sunAltitude: -3), 0.5)
        XCTAssertEqual(LakeDaySchedule.detailVisibility(sunAltitude: -6), 0)
    }

    func testPreviewSkyAndActivityUseTheSameStableInstant() {
        let before = demoTime(0, 0).addingTimeInterval(-90_000)
        let after = demoTime(23, 59).addingTimeInterval(90_000)
        let preview = BackgroundTimePreview.custom
        let minute = 19 * 60 + 20
        let date = preview.date(at: before, customMinute: minute)
        let scene = preview.sky(at: before, coordinates: nil, customMinute: minute)

        XCTAssertEqual(date, demoTime(19, 20))
        XCTAssertEqual(date, preview.date(at: after, customMinute: minute))
        XCTAssertEqual(scene, preview.sky(at: after, coordinates: .init(latitude: 78, longitude: 15), customMinute: minute))
        XCTAssertEqual(scene, TodaySkyAstronomy.sky(at: date, coordinates: nil, calendar: BackgroundTimePreview.demoCalendar))
        XCTAssertEqual(LakeDaySchedule.detailVisibility(sunAltitude: scene.sunAltitude), 0)
        XCTAssertNotNil(demoSchedule.motion(at: date).boat)
        XCTAssertNotNil(demoSchedule.motion(at: date).lanternVisitor)
        XCTAssertEqual(BackgroundTimePreview.live.date(at: after, customMinute: minute), after)
        XCTAssertEqual(BackgroundTheme(storedValue: "window"), .lakeside)
        XCTAssertEqual(BackgroundTheme(storedValue: "mistLight"), .mistLight)
    }

    private var demoSchedule: LakeDaySchedule {
        LakeDaySchedule(at: BackgroundTimePreview.demoDay, calendar: BackgroundTimePreview.demoCalendar, demo: true)
    }

    private func demoTime(_ hour: Int, _ minute: Int) -> Date {
        BackgroundTimePreview.demoDay.addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    private func utc(_ timestamp: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: timestamp))
    }
}
