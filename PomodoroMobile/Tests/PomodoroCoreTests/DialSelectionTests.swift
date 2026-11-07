import Foundation
import XCTest
@testable import PomodoroCore

final class DialSelectionTests: XCTestCase {
    func testExactlyThreeSupportedDesktopDials() {
        XCTAssertEqual(DialStyle.supported, [.digital, .swiss, .gemstone])
        XCTAssertEqual(DialStyle.ring.resolved, .swiss)
    }

    func testAllDialSelectionsPreserveRunningDeadlineAcrossSaveAndRelaunch() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var archive = AppArchive()
        archive.timer.start(at: date)
        let id = archive.timer.id
        for dial in DialStyle.supported {
            archive.settings.dial = dial
            let decoded = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
            XCTAssertEqual(decoded.settings.dial, dial)
            XCTAssertEqual(decoded.timer.id, id)
            XCTAssertEqual(decoded.timer.status, .running)
            XCTAssertEqual(decoded.timer.deadline, date.addingTimeInterval(1500))
        }
    }

    func testPausedStateAndBreakModeSurviveDialSwitch() throws {
        var archive = AppArchive()
        archive.timer.prepare(mode: .longBreak, settings: archive.settings)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        archive.timer.start(at: date)
        archive.timer.pause(at: date.addingTimeInterval(200))
        let timer = archive.timer
        for dial in DialStyle.supported {
            archive.settings.dial = dial
            let restored = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
            XCTAssertEqual(restored.timer, timer)
        }
    }

    func testOldAppearanceKeepsPhotoAndGetsDefaultDigitalFont() throws {
        let data = Data(#"{"photoPosition":0.8,"clockSize":280,"usesPhoto":true,"darkText":false}"#.utf8)
        let preferences = try JSONDecoder().decode(CanvasPreferences.self, from: data)
        XCTAssertEqual(preferences.photoPosition, 0.8)
        XCTAssertEqual(preferences.clockSize, 280)
        XCTAssertFalse(preferences.darkText)
        XCTAssertEqual(preferences.digitalFontName, "HelveticaNeue")
        XCTAssertEqual(preferences.digitalFontSize, 96)
    }

    func testDigitalFontSelectionRoundTripAndSizeBounds() throws {
        var preferences = CanvasPreferences()
        preferences.digitalFontName = "Courier"
        preferences.digitalFontSize = 120
        let restored = try JSONDecoder().decode(CanvasPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.digitalFontName, "Courier")
        XCTAssertEqual(restored.digitalFontSize, 120)
        let oversized = try JSONDecoder().decode(CanvasPreferences.self, from: Data(#"{"digitalFontSize":1000}"#.utf8))
        XCTAssertEqual(oversized.digitalFontSize, 160)
    }
}
