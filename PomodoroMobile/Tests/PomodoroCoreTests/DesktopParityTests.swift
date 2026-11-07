import Foundation
import XCTest
@testable import PomodoroCore

final class DesktopParityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOlderSettingsKeepExistingDataAndGetSafeAudioDefaults() throws {
        let old = Data(#"{"focusMinutes":40,"shortBreakMinutes":8,"longBreakMinutes":20,"sound":"pink","volume":0.45,"notificationsEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: old)
        XCTAssertEqual(settings.focusMinutes, 40)
        XCTAssertEqual(settings.sound, .pink)
        XCTAssertEqual(settings.soundBeforeMute, .pink)
        XCTAssertEqual(settings.volume, 0.45)
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertTrue(settings.soundOnlyDuringTimer)
        XCTAssertEqual(settings.campfire, CampfireParameters())
        XCTAssertFalse(settings.shouldPlayAmbient(timerRunning: false))
    }

    func testIndependentAudioDoesNotRequireRunningTimer() {
        var settings = FocusSettings()
        settings.sound = .rain
        XCTAssertTrue(settings.shouldPlayAmbient(timerRunning: true))
        XCTAssertFalse(settings.shouldPlayAmbient(timerRunning: false))
        settings.soundOnlyDuringTimer = false
        XCTAssertTrue(settings.shouldPlayAmbient(timerRunning: false))
        settings.sound = .none
        XCTAssertFalse(settings.shouldPlayAmbient(timerRunning: true))
    }

    func testFiveSoundTypesAndFiveCampfirePresets() {
        XCTAssertEqual(AmbientSound.allCases.filter { $0 != .none }.count, 5)
        XCTAssertEqual(CampfirePreset.allCases.count, 5)
        XCTAssertEqual(CampfirePreset.cozy.parameters.rumble, 0.5)
        XCTAssertEqual(CampfirePreset.roaring.parameters.freqMid, 900)
        XCTAssertEqual(CampfirePreset.woodstove.parameters.freqHi, 3500)
    }

    func testAllPresetSamplesAreFiniteAndDifferent() {
        var signatures = Set<Float>()
        for preset in CampfirePreset.allCases {
            let samples = NoiseGenerator.samples(sound: .campfire, count: 48_000, campfire: preset.parameters)
            XCTAssertEqual(samples.count, 48_000)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.95 })
            signatures.insert(samples[10_000])
        }
        XCTAssertEqual(signatures.count, CampfirePreset.allCases.count)
    }

    func testInvalidCampfireParametersAreClamped() {
        var p = CampfireParameters()
        p.rumble = .nan; p.woodyLevel = 100; p.freqHi = .infinity; p.freqLo = -50
        XCTAssertEqual(p.normalized.rumble, 0)
        XCTAssertEqual(p.normalized.woodyLevel, 1)
        XCTAssertEqual(p.normalized.freqHi, 500)
        XCTAssertEqual(p.normalized.freqLo, 50)
        let samples = NoiseGenerator.samples(sound: .campfire, count: 2000, campfire: p)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }

    func testNewAudioSettingsRoundTrip() throws {
        var settings = FocusSettings()
        settings.sound = .campfire
        settings.soundOnlyDuringTimer = false
        settings.campfirePreset = .ember
        settings.campfire = CampfirePreset.ember.parameters
        XCTAssertEqual(try JSONDecoder().decode(FocusSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    private func completedArchive() -> AppArchive {
        var archive = AppArchive()
        archive.timer.start(at: now)
        archive.reconcileTimer(at: now.addingTimeInterval(1500))
        return archive
    }

    func testFocusCompletionOffersEitherBreak() {
        for action in [TimerCompletionAction.shortBreak, .longBreak] {
            var archive = completedArchive()
            XCTAssertTrue(archive.handleCompletion(action, sessionID: archive.timer.id, at: now.addingTimeInterval(1600)))
            XCTAssertEqual(archive.timer.status, .running)
            XCTAssertEqual(archive.timer.mode, action == .shortBreak ? .shortBreak : .longBreak)
            XCTAssertEqual(archive.completedFocusCount, 1)
        }
    }

    func testStopAfterCompletionReturnsToReadyFocus() {
        var archive = completedArchive()
        XCTAssertTrue(archive.handleCompletion(.stop, sessionID: archive.timer.id, at: now.addingTimeInterval(1600)))
        XCTAssertEqual(archive.timer.status, .ready)
        XCTAssertEqual(archive.timer.mode, .focus)
        XCTAssertEqual(archive.completedFocusCount, 1)
    }

    func testOldNotificationCannotReplaceNewRunningSession() {
        var archive = completedArchive()
        let oldID = archive.timer.id
        archive.timer.prepare(mode: .focus, settings: archive.settings)
        archive.timer.start(at: now.addingTimeInterval(1700))
        let newID = archive.timer.id
        XCTAssertFalse(archive.handleCompletion(.longBreak, sessionID: oldID, at: now.addingTimeInterval(1800)))
        XCTAssertEqual(archive.timer.id, newID)
        XCTAssertEqual(archive.timer.mode, .focus)
    }

    func testNotificationAtDeadlineCompletesThenStartsRequestedBreakOnce() {
        var archive = AppArchive()
        archive.timer.start(at: now)
        let id = archive.timer.id
        XCTAssertTrue(archive.handleCompletion(.shortBreak, sessionID: id, at: now.addingTimeInterval(1500)))
        XCTAssertEqual(archive.completedFocusCount, 1)
        XCTAssertFalse(archive.handleCompletion(.shortBreak, sessionID: id, at: now.addingTimeInterval(1500)))
        XCTAssertEqual(archive.completedFocusCount, 1)
    }

    func testBreakNotificationStartsNextFocus() {
        var archive = AppArchive()
        archive.timer.prepare(mode: .shortBreak, settings: archive.settings)
        archive.timer.start(at: now)
        XCTAssertTrue(archive.handleCompletion(.focus, sessionID: archive.timer.id, at: now.addingTimeInterval(300)))
        XCTAssertEqual(archive.timer.mode, .focus)
        XCTAssertEqual(archive.timer.status, .running)
        XCTAssertEqual(archive.completedFocusCount, 0)
    }

    func testSmoothHandUsesDeadlineRatherThanRoundedSeconds() {
        var timer = FocusTimer()
        timer.start(at: now)
        XCTAssertEqual(timer.progress(at: now.addingTimeInterval(0.5)), 0.5 / 1500, accuracy: 0.000001)
        timer.pause(at: now.addingTimeInterval(100))
        XCTAssertEqual(timer.progress(at: now.addingTimeInterval(500)), timer.progress)
    }

    func testOldCanvasPreferencesPreserveCustomBackgroundAndPanelExpansion() throws {
        let old = Data(#"{"darkText":false,"usesPhoto":true,"photoPosition":0.2,"panels":{"abc":{"tint":"blue","expanded":true,"opacity":0.45}}}"#.utf8)
        let style = try JSONDecoder().decode(CanvasPreferences.self, from: old)
        XCTAssertFalse(style.darkText)
        XCTAssertEqual(style.photoPosition, 0.2)
        XCTAssertEqual(style.panels["abc"]?.expanded, true)
        XCTAssertEqual(style.panels["abc"]?.expandedHeight, 260)
        XCTAssertEqual(style.glassTintRGB, [1, 1, 1])
        XCTAssertEqual(style.clockSize, 300)
        XCTAssertEqual(style.backgroundTheme, .image)
        XCTAssertNil(style.pairedGlassTint)
        XCTAssertTrue(style.todayExpanded)

        var customized = style
        customized.backgroundTheme = .lakeside
        customized.pairedGlassTint = .monochrome
        customized.todayExpanded = false
        let restored = try JSONDecoder().decode(CanvasPreferences.self, from: JSONEncoder().encode(customized))
        XCTAssertEqual(restored.backgroundTheme, .lakeside)
        XCTAssertEqual(restored.pairedGlassTint, .monochrome)
        XCTAssertFalse(restored.todayExpanded)
        XCTAssertEqual(restored.photoPosition, style.photoPosition)
    }
}
