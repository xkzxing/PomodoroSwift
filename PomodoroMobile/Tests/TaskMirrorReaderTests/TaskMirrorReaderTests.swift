import Combine
import Foundation
import XCTest
import PomodoroCore
@testable import TaskMirrorReader

@MainActor
final class TaskMirrorReaderTests: XCTestCase {
    private struct Fixture {
        let source: URL
        let cache: URL
        let defaults: UserDefaults
        let publisherID = UUID()
        var file: URL { source.appendingPathComponent(TaskMirrorSnapshot.fileName) }
        func snapshot(revision: UInt64, title: String = "电脑待办", publisherID: UUID? = nil) -> TaskMirrorSnapshot {
            .init(publisherID: publisherID ?? self.publisherID, revision: revision, publishedAt: Date(),
                  panels: [.init(id: UUID(), title: title, items: [.init(id: UUID(), text: "只读事项", isPinned: true)],
                                 appearance: .init(clearGlass: true, tintRGB: [0.2, 0.4, 0.8], opacity: 0.3, darkText: true))])
        }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let suiteName = "TaskMirrorReaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suiteName) }
        return Fixture(source: source, cache: root.appendingPathComponent("private/cache.json"), defaults: defaults)
    }

    private func waitForRead(_ reader: MobileTaskMirror, action: () -> Void) async {
        let done = expectation(description: "Read finishes")
        let cancellable = reader.$isRefreshing.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
        action()
        await fulfillment(of: [done], timeout: 10)
        cancellable.cancel()
    }

    func testSelectingFolderAndRelaunchingDoNotReadUntilManualRefresh() async throws {
        let f = try fixture()
        try f.snapshot(revision: 1).encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        reader.selectDirectory(f.source)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(reader.snapshot)
        XCTAssertFalse(reader.isRefreshing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.cache.path))
        let restored = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        XCTAssertNil(restored.snapshot)
        XCTAssertFalse(restored.isRefreshing)
        await waitForRead(restored) { restored.refresh() }
        XCTAssertEqual(restored.snapshot?.revision, 1)
    }

    func testReadingNeverWritesIntoSharedDirectory() async throws {
        let f = try fixture()
        let original = try f.snapshot(revision: 1).encoded()
        try original.write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        XCTAssertEqual(reader.snapshot?.revision, 1)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(try Data(contentsOf: f.file), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.source.path), [TaskMirrorSnapshot.fileName])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.cache.path))
    }

    func testTodayUpgradeAndRemovalRefreshBothListsAndPersistOffline() async throws {
        let f = try fixture()
        let legacy = f.snapshot(revision: 1)
        try legacy.encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        XCTAssertNil(reader.snapshot?.today)

        let panel = legacy.panels[0]
        let item = panel.items[0]
        let appearance = TaskMirrorSnapshot.TodayAppearance(theme: .sky)
        let upgraded = TaskMirrorSnapshot(publisherID: legacy.publisherID, revision: 2, publishedAt: .now,
            panels: [.init(id: panel.id, title: panel.title, items: [
                .init(id: item.id, text: item.text, isPinned: item.isPinned, isInToday: true)
            ], appearance: panel.appearance)], today: appearance)
        let published = try upgraded.encoded()
        try published.write(to: f.file, options: .atomic)
        let reopened = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        XCTAssertEqual(reopened.snapshot?.revision, 1)
        await waitForRead(reopened) { reopened.refresh() }
        XCTAssertEqual(reopened.snapshot?.todayEntries.map(\.id), [item.id])
        XCTAssertEqual(reopened.snapshot?.today, appearance)
        XCTAssertEqual(try Data(contentsOf: f.file), published)
        XCTAssertEqual(MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache).snapshot, upgraded)

        let removed = TaskMirrorSnapshot(publisherID: legacy.publisherID, revision: 3, publishedAt: .now,
            panels: legacy.panels, today: appearance)
        try removed.encoded().write(to: f.file, options: .atomic)
        await waitForRead(reopened) { reopened.refresh() }
        XCTAssertEqual(reopened.snapshot?.todayEntries.count, 0)
        XCTAssertEqual(reopened.snapshot?.panels[0].items.map(\.id), [item.id])
    }

    func testMissingSourceKeepsLastGoodResult() async throws {
        let f = try fixture()
        try f.snapshot(revision: 5).encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        try FileManager.default.removeItem(at: f.file)
        await waitForRead(reader) { reader.refresh() }
        XCTAssertEqual(reader.snapshot?.revision, 5)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.file.path))
    }

    func testCorruptedSourceKeepsCacheAndSourceUntouched() async throws {
        let f = try fixture()
        try f.snapshot(revision: 7).encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        let cache = try Data(contentsOf: f.cache)
        let broken = Data("incomplete".utf8)
        try broken.write(to: f.file)
        await waitForRead(reader) { reader.refresh() }
        XCTAssertEqual(reader.snapshot?.revision, 7)
        XCTAssertEqual(try Data(contentsOf: f.cache), cache)
        XCTAssertEqual(try Data(contentsOf: f.file), broken)
    }

    func testRestartRetainsPublisherAndRejectsRollbackEvenWithoutPreferenceWrite() async throws {
        let f = try fixture()
        try f.snapshot(revision: 20).encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        // Simulate termination after cache commit but before the preference commit.
        f.defaults.removeObject(forKey: "taskMirror.acceptedPublisherID")
        try f.snapshot(revision: 19).encoded().write(to: f.file)
        let restored = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(restored) { restored.refresh() }
        XCTAssertEqual(restored.snapshot?.revision, 20)
        XCTAssertNotNil(restored.statusMessage)
    }

    func testChangedPublisherIsRejectedUntilUserSelectsFolderAgain() async throws {
        let f = try fixture()
        try f.snapshot(revision: 5).encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        let newPublisher = UUID()
        try f.snapshot(revision: 1, publisherID: newPublisher).encoded().write(to: f.file)
        await waitForRead(reader) { reader.refresh() }
        XCTAssertEqual(reader.snapshot?.publisherID, f.publisherID)
        XCTAssertNotNil(reader.errorMessage)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        XCTAssertEqual(reader.snapshot?.publisherID, newPublisher)
        XCTAssertEqual(reader.snapshot?.revision, 1)
    }

    func testValidDesktopDeletionReplacesCachedItems() async throws {
        let f = try fixture()
        try f.snapshot(revision: 1).encoded().write(to: f.file)
        let reader = MobileTaskMirror(defaults: f.defaults, cacheURL: f.cache)
        await waitForRead(reader) { reader.selectDirectory(f.source); reader.refresh() }
        let empty = TaskMirrorSnapshot(publisherID: f.publisherID, revision: 2, publishedAt: Date(), panels: [])
        try empty.encoded().write(to: f.file)
        await waitForRead(reader) { reader.refresh() }
        XCTAssertEqual(reader.snapshot?.revision, 2)
        XCTAssertEqual(reader.snapshot?.panels.count, 0)
        XCTAssertEqual(try Data(contentsOf: f.file), try empty.encoded())
    }
}
