import Foundation
import XCTest
@testable import PomodoroSwift

final class TodaySkyAstronomyTests: XCTestCase {
    func testMoonPhasesAndStarDensityAgainstNovember2026Ephemeris() {
        // Reference instants: https://aa.usno.navy.mil/calculated/moon/phases?year=2026
        let new = sky("2026-11-09T07:02:00Z").moon
        let firstQuarter = sky("2026-11-17T11:48:00Z").moon
        let full = sky("2026-11-24T14:53:00Z").moon
        let lastQuarter = sky("2026-11-01T20:28:00Z").moon

        XCTAssertTrue(new.isNew)
        XCTAssertEqual(new.starCount, 18)
        let newMoonNight = sky("2026-11-09T02:00:00Z")
        XCTAssertNil(newMoonNight.moonTrack)
        XCTAssertEqual(newMoonNight.starVisibility, 1)
        XCTAssertTrue(full.isFull)
        XCTAssertEqual(full.starCount, 0)
        XCTAssertEqual(firstQuarter.illumination, 0.5, accuracy: 0.04)
        XCTAssertEqual(lastQuarter.illumination, 0.5, accuracy: 0.04)
        XCTAssertTrue(firstQuarter.isWaxing)
        XCTAssertFalse(lastQuarter.isWaxing)
        XCTAssertTrue((9...11).contains(firstQuarter.starCount))
        XCTAssertTrue((9...11).contains(lastQuarter.starCount))
    }

    func testSolarAltitudeAtNewYorkAndDuringPolarDayAndNight() {
        let newYork = TodaySkyAstronomy.Coordinates(latitude: 40.7, longitude: -74)
        let morning = sky("2026-06-21T09:25:00Z", coordinates: newYork)
        let noon = sky("2026-06-21T17:00:00Z", coordinates: newYork)
        let night = sky("2026-06-21T04:00:00Z", coordinates: newYork)
        XCTAssertEqual(morning.sunAltitude, -0.8, accuracy: 0.4)
        XCTAssertTrue(morning.isMorning)
        XCTAssertEqual(noon.sunAltitude, 72.7, accuracy: 0.5)
        XCTAssertEqual(night.starVisibility, 1)

        let svalbard = TodaySkyAstronomy.Coordinates(latitude: 78.2, longitude: 15.6)
        XCTAssertGreaterThan(sky("2026-06-21T23:00:00Z", coordinates: svalbard).sunAltitude, 0)
        XCTAssertLessThan(sky("2026-12-21T11:00:00Z", coordinates: svalbard).sunAltitude, -6)
    }

    func testClockFallbackFollowsLocalTimeWithoutChangingTheMoon() {
        let instant = "2026-06-21T10:00:00Z"
        let newYork = sky(instant, zone: "America/New_York")
        let tokyo = sky(instant, zone: "Asia/Tokyo")
        XCTAssertEqual(newYork.sunAltitude, 0)
        XCTAssertEqual(newYork.sunTrack?.progress, 0)
        XCTAssertEqual(tokyo.sunAltitude, -18)
        XCTAssertNil(tokyo.sunTrack)
        XCTAssertEqual(tokyo.starVisibility, 1)
        XCTAssertEqual(newYork.moon.illumination, tokyo.moon.illumination)

        let twilight = sky("2026-06-21T09:45:00Z", zone: "America/New_York")
        XCTAssertNil(twilight.sunTrack)
        XCTAssertEqual(twilight.starVisibility, 0)
        let beforeFallback = sky("2026-11-01T05:30:00Z", zone: "America/New_York")
        let afterFallback = sky("2026-11-01T06:30:00Z", zone: "America/New_York")
        XCTAssertEqual(beforeFallback.sunAltitude, afterFallback.sunAltitude)
    }

    func testClockFallbackSolarArcStartsRightAndSetsLeft() throws {
        let rise = try XCTUnwrap(sky("2026-11-24T06:00:00Z").sunTrack)
        let transit = try XCTUnwrap(sky("2026-11-24T12:00:00Z").sunTrack)
        let set = try XCTUnwrap(sky("2026-11-24T18:00:00Z").sunTrack)
        XCTAssertEqual(rise.progress, 0, accuracy: 1e-8)
        XCTAssertEqual(rise.height, 0, accuracy: 1e-8)
        XCTAssertEqual(transit.progress, 0.5, accuracy: 1e-8)
        XCTAssertEqual(transit.height, 1, accuracy: 1e-8)
        XCTAssertEqual(set.progress, 1, accuracy: 1e-8)
        XCTAssertEqual(set.height, 0, accuracy: 1e-8)
    }

    func testLocatedMoonCrossesTheSkyIndependentlyOfTheSun() throws {
        let newYork = TodaySkyAstronomy.Coordinates(latitude: 40.7, longitude: -74)
        let rise = try XCTUnwrap(sky("2026-11-24T23:30:00Z", coordinates: newYork).moonTrack)
        let transit = try XCTUnwrap(sky("2026-11-25T05:00:00Z", coordinates: newYork).moonTrack)
        let set = try XCTUnwrap(sky("2026-11-25T10:30:00Z", coordinates: newYork).moonTrack)
        XCTAssertLessThan(rise.progress, 0.25)
        XCTAssertEqual(transit.progress, 0.5, accuracy: 0.12)
        XCTAssertGreaterThan(set.progress, 0.75)
        XCTAssertGreaterThan(transit.height, rise.height)
        XCTAssertGreaterThan(transit.height, set.height)
        XCTAssertNil(sky("2026-11-25T17:00:00Z", coordinates: newYork).moonTrack)
    }

    func testNightPreviewsGiveAStableMoonlitAndMoonlessComparison() throws {
        let newMoon = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T07:02:00Z"))
        let moonlit = BackgroundTimePreview.moonlitNight.sky(at: newMoon, coordinates: nil)
        let later = newMoon.addingTimeInterval(15 * 24 * 60 * 60)
        let polarDay = TodaySkyAstronomy.Coordinates(latitude: 78.2, longitude: 15.6)

        XCTAssertEqual(moonlit, BackgroundTimePreview.moonlitNight.sky(at: later, coordinates: polarDay))
        XCTAssertTrue(moonlit.moon.isFull)
        XCTAssertNotNil(moonlit.moonTrack)
        XCTAssertNil(moonlit.sunTrack)
        XCTAssertNil(BackgroundTimePreview.night.sky(at: later, coordinates: polarDay).moonTrack)
    }

    private func sky(_ timestamp: String, coordinates: TodaySkyAstronomy.Coordinates? = nil,
                     zone: String = "UTC") -> TodaySkyAstronomy.Sky {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return TodaySkyAstronomy.sky(at: ISO8601DateFormatter().date(from: timestamp)!,
                                    coordinates: coordinates, calendar: calendar)
    }
}
