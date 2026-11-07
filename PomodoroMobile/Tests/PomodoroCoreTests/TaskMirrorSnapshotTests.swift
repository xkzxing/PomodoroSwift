import Foundation
import CryptoKit
import XCTest
@testable import PomodoroCore

final class TaskMirrorSnapshotTests: XCTestCase {
    private let publisher = UUID()
    private let appearance = TaskMirrorSnapshot.Appearance(clearGlass: false, tintRGB: [0.4, 0.6, 0.9], opacity: 0.35, darkText: true)

    private func snapshot(revision: UInt64 = 1, panels: [TaskMirrorSnapshot.Panel]? = nil) -> TaskMirrorSnapshot {
        .init(publisherID: publisher, revision: revision, publishedAt: Date(timeIntervalSince1970: 1000),
              panels: panels ?? [.init(id: UUID(), title: "工作", items: [.init(id: UUID(), text: "待办内容", isPinned: true)], appearance: appearance)])
    }

    func testWireRoundTripPreservesOrderAndAppearance() throws {
        let items = [TaskMirrorSnapshot.Item(id: UUID(), text: "置顶", isPinned: true), .init(id: UUID(), text: "普通", isPinned: false)]
        let panels = [TaskMirrorSnapshot.Panel(id: UUID(), title: "第二面板", items: items, appearance: appearance),
                      .init(id: UUID(), title: "第一面板", items: [], appearance: appearance)]
        let original = snapshot(panels: panels)
        let decoded = try TaskMirrorSnapshot.decode(original.encoded())
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.panels.map(\.title), ["第二面板", "第一面板"])
        XCTAssertEqual(decoded.panels[0].items.map(\.text), ["置顶", "普通"])
    }

    func testLegacySnapshotWithoutNewFieldsRetainsOriginalAppearanceAndPinnedOrder() throws {
        let data = try snapshot().encoded()
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let base64 = try XCTUnwrap(envelope["payload"] as? String)
        let rawPayload = try XCTUnwrap(Data(base64Encoded: base64))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: rawPayload) as? [String: Any])
        var panels = try XCTUnwrap(payload["panels"] as? [[String: Any]])
        var items = try XCTUnwrap(panels[0]["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "isInToday")
        panels[0]["items"] = items
        payload["panels"] = panels
        let legacyPayload = try JSONSerialization.data(withJSONObject: payload)
        envelope["payload"] = legacyPayload.base64EncodedString()
        envelope["sha256"] = SHA256.hash(data: legacyPayload).map { String(format: "%02x", $0) }.joined()
        let legacy = try TaskMirrorSnapshot.decode(JSONSerialization.data(withJSONObject: envelope))
        XCTAssertNil(legacy.today)
        XCTAssertTrue(legacy.todayEntries.isEmpty)
        XCTAssertTrue(legacy.panels[0].items[0].isPinned)
        let colors = legacy.panels[0].appearance.colors(forLightScene: false)
        XCTAssertEqual(colors.tint, appearance.tintRGB)
        XCTAssertTrue(colors.darkText)
    }

    func testTodayMembershipIsIndependentOfPinningAndColorsSwitchWithoutReloading() throws {
        let today = TaskMirrorSnapshot.TodayAppearance(theme: .sky, skyConcentration: 0.8)
        let palette = TaskMirrorSnapshot.DaylightPalette(lightRGB: [1, 1, 1], darkRGB: [0, 0, 0])
        let appearance = TaskMirrorSnapshot.Appearance(clearGlass: true, tintRGB: palette.darkRGB,
            opacity: 0.35, darkText: false, daylightPalette: palette)
        let pinned = TaskMirrorSnapshot.Item(id: UUID(), text: "只置顶", isPinned: true)
        let inToday = TaskMirrorSnapshot.Item(id: UUID(), text: "只加入今日", isPinned: false, isInToday: true)
        let original = TaskMirrorSnapshot(publisherID: publisher, revision: 1, publishedAt: Date(),
            panels: [.init(id: UUID(), title: "工作", items: [pinned, inToday], appearance: appearance)], today: today)
        let decoded = try TaskMirrorSnapshot.decode(original.encoded())
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.todayEntries.map(\.item.id), [inToday.id])
        XCTAssertEqual(decoded.todayEntries.map(\.panelTitle), ["工作"])
        let saved = decoded.panels[0].appearance
        XCTAssertEqual(saved.colors(forLightScene: nil).tint, palette.darkRGB)
        XCTAssertEqual(saved.colors(forLightScene: true).tint, palette.lightRGB)
        XCTAssertTrue(saved.colors(forLightScene: true).darkText)
        XCTAssertEqual(saved.colors(forLightScene: false).tint, palette.darkRGB)
        XCTAssertFalse(saved.colors(forLightScene: false).darkText)
    }

    func testInvalidNewAppearanceFieldsDoNotProduceSnapshots() {
        let badPalette = TaskMirrorSnapshot.DaylightPalette(lightRGB: [1, 1, 1], darkRGB: [0, 0, 2])
        let invalid = TaskMirrorSnapshot.Appearance(clearGlass: false, tintRGB: [1, 1, 1], opacity: 0.5,
            darkText: true, daylightPalette: badPalette)
        XCTAssertThrowsError(try snapshot(panels: [.init(id: UUID(), title: "工作", items: [], appearance: invalid)]).encoded())
        let invalidToday = TaskMirrorSnapshot(publisherID: publisher, revision: 1, publishedAt: Date(),
            panels: [], today: .init(gradientStart: -1))
        XCTAssertThrowsError(try invalidToday.encoded())
    }

    func testTruncatedAndEmptyFilesCannotBecomeAnEmptySnapshot() throws {
        let data = try snapshot().encoded()
        XCTAssertThrowsError(try TaskMirrorSnapshot.decode(Data()))
        XCTAssertThrowsError(try TaskMirrorSnapshot.decode(Data(data.prefix(data.count / 2))))
        XCTAssertThrowsError(try TaskMirrorSnapshot.decode(Data("{}".utf8)))
    }

    func testPayloadCorruptionFailsChecksum() throws {
        let data = try snapshot().encoded()
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        envelope["payload"] = Data("{}".utf8).base64EncodedString()
        XCTAssertThrowsError(try TaskMirrorSnapshot.decode(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testUnsupportedFormatIsRejected() throws {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot().encoded()) as? [String: Any])
        envelope["version"] = 2
        XCTAssertThrowsError(try TaskMirrorSnapshot.decode(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testOlderCloudRevisionCannotRollBackCache() throws {
        let current = snapshot(revision: 20)
        let older = snapshot(revision: 19)
        XCTAssertFalse(try older.shouldReplace(current, expectedPublisherID: publisher))
        XCTAssertFalse(try current.shouldReplace(current, expectedPublisherID: publisher))
    }

    func testSameRevisionWithDifferentContentIsRejected() throws {
        XCTAssertThrowsError(try snapshot().shouldReplace(snapshot(), expectedPublisherID: publisher))
    }

    func testAnotherComputerCannotReplacePinnedPublisher() throws {
        let current = snapshot()
        let other = TaskMirrorSnapshot(publisherID: UUID(), revision: 200, publishedAt: Date(), panels: [])
        XCTAssertThrowsError(try other.shouldReplace(current, expectedPublisherID: publisher))
        XCTAssertTrue(try other.shouldReplace(nil, expectedPublisherID: nil))
    }

    func testCompleteEmptyDesktopResultCanRemoveAllVisiblePanels() throws {
        let current = snapshot()
        let empty = snapshot(revision: 2, panels: [])
        let decoded = try TaskMirrorSnapshot.decode(empty.encoded())
        XCTAssertTrue(try decoded.shouldReplace(current, expectedPublisherID: publisher))
        XCTAssertTrue(decoded.panels.isEmpty)
    }

    func testNewRevisionReflectsDesktopDeletion() throws {
        let first = snapshot()
        let oldPanel = try XCTUnwrap(first.panels.first)
        let updated = snapshot(revision: 2, panels: [.init(id: oldPanel.id, title: oldPanel.title, items: [], appearance: appearance)])
        XCTAssertTrue(try updated.shouldReplace(first, expectedPublisherID: publisher))
        XCTAssertTrue(updated.panels[0].items.isEmpty)
    }

    func testDuplicatePanelOrTaskIdentifiersAreRejected() throws {
        let panel = try XCTUnwrap(snapshot().panels.first)
        XCTAssertThrowsError(try snapshot(panels: [panel, panel]).encoded())
        let duplicate = TaskMirrorSnapshot.Panel(id: UUID(), title: "另一个", items: panel.items, appearance: appearance)
        XCTAssertThrowsError(try snapshot(panels: [panel, duplicate]).encoded())
    }

    func testInvalidColorAndZeroRevisionAreRejected() {
        XCTAssertThrowsError(try snapshot(revision: 0).encoded())
        let invalid = TaskMirrorSnapshot.Appearance(clearGlass: false, tintRGB: [1], opacity: 0.5, darkText: false)
        let panel = TaskMirrorSnapshot.Panel(id: UUID(), title: "无效", items: [], appearance: invalid)
        XCTAssertThrowsError(try snapshot(panels: [panel]).encoded())
    }

    func testRevisionWinsEvenWhenComputerClockMovesBackwards() throws {
        let current = snapshot(revision: 10)
        let newer = TaskMirrorSnapshot(publisherID: publisher, revision: 11,
            publishedAt: Date(timeIntervalSince1970: 0), panels: current.panels)
        XCTAssertTrue(try newer.shouldReplace(current, expectedPublisherID: publisher))
    }
}
