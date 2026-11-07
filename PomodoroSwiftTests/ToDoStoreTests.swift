import XCTest
import Combine
@testable import PomodoroSwift

@MainActor
final class ToDoStoreTests: XCTestCase {
    func testLegacyItemDefaultsToUnpinnedAndPreservesText() throws {
        let id = UUID()
        let data = Data("""
        {"id":"\(id.uuidString)","text":"🚩 Tyler Paper","isDone":false}
        """.utf8)
        let item = try JSONDecoder().decode(ToDoItem.self, from: data)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.text, "🚩 Tyler Paper")
        XCTAssertFalse(item.isPinned)
        XCTAssertFalse(item.isDone)
        XCTAssertFalse(item.isInToday)
    }

    func testTodaySelectionPersistsAndKeepsBothViewsInSync() throws {
        try withStorage { defaults, center, panelId, key in
            let item = ToDoItem(text: "First", isPinned: true)
            let second = ToDoItem(text: "Second")
            try seed([item, second], defaults, key)
            let source = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            let peer = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)

            source.setInToday(true, id: item.id)
            source.setInToday(true, id: item.id)
            XCTAssertEqual(source.items.map(\.id), [item.id, second.id])
            XCTAssertEqual(peer.items.filter(\.isInToday).map(\.id), [item.id])
            XCTAssertEqual(source.pinnedCount, 1)

            let reopened = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertEqual(reopened.items, source.items)
            peer.setInToday(false, id: item.id)
            XCTAssertTrue(source.items.filter(\.isInToday).isEmpty)
            XCTAssertEqual(source.items.map(\.id), [item.id, second.id])

            source.setInToday(true, id: item.id)
            peer.delete(id: item.id)
            XCTAssertEqual(source.items, [second])
            XCTAssertEqual(try storedItems(defaults, key), [second])
        }
    }

    func testPinnedItemRoundTripsWithLegacyCompletionField() throws {
        let item = ToDoItem(text: "Pinned", isPinned: true)
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ToDoItem.self, from: data), item)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(fields["isDone"] as? Bool, false)
        XCTAssertEqual(fields["isPinned"] as? Bool, true)
    }

    func testMigrationDeletesCompletedItemsAndIsIdempotent() throws {
        try withStorage { defaults, center, panelId, key in
            let first = ToDoItem(text: "First")
            let completed = ToDoItem(text: "Done", isDone: true)
            let last = ToDoItem(text: "🚩 Last")
            let legacy = [first, completed, last].map {
                ["id": $0.id.uuidString, "text": $0.text, "isDone": $0.isDone] as [String: Any]
            }
            defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertEqual(store.items, [first, last])
            XCTAssertEqual(store.pinnedCount, 0)
            XCTAssertEqual(try storedItems(defaults, key), [first, last])
            let reloaded = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertEqual(reloaded.items, [first, last])
        }
    }

    func testGlobalLegacyMigrationRunsOnlyForFirstPanel() throws {
        try withStorage { defaults, center, panelId, key in
            let kept = ToDoItem(text: "Kept")
            try seed([ToDoItem(text: "Done", isDone: true), kept], defaults, "toDoItems")
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertEqual(store.items, [kept])
            XCTAssertEqual(try storedItems(defaults, key), [kept])
            XCTAssertTrue(defaults.bool(forKey: "hasMigratedLegacyToDoStore"))
            let other = ToDoStore(panelId: UUID(), defaults: defaults, notificationCenter: center)
            XCTAssertTrue(other.items.isEmpty)
        }
    }

    func testLoadingNormalizesGroupsWithoutChangingTheirInternalOrder() throws {
        try withStorage { defaults, center, panelId, key in
            let a = ToDoItem(text: "A")
            let b = ToDoItem(text: "B", isPinned: true)
            let c = ToDoItem(text: "C")
            let d = ToDoItem(text: "D", isPinned: true)
            try seed([a, b, c, d], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertEqual(store.items, [b, d, a, c])
            XCTAssertEqual(store.pinnedCount, 2)
        }
    }

    func testPinAppendsToPinnedGroupAndUnpinGoesToOrdinaryTop() throws {
        try withStorage { defaults, center, panelId, key in
            let a = ToDoItem(text: "A", isPinned: true)
            let b = ToDoItem(text: "B", isPinned: true)
            let c = ToDoItem(text: "C")
            let d = ToDoItem(text: "D")
            try seed([a, b, c, d], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            store.togglePin(d)
            XCTAssertEqual(store.items.map(\.id), [a.id, b.id, d.id, c.id])
            XCTAssertEqual(store.pinnedCount, 3)
            store.togglePin(b)
            XCTAssertEqual(store.items.map(\.id), [a.id, d.id, b.id, c.id])
            XCTAssertEqual(store.items.map(\.isPinned), [true, true, false, false])
            XCTAssertEqual(store.pinnedCount, 2)
            let reopened = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertEqual(reopened.items, store.items)
        }
    }

    func testToggleUsesCurrentStateEvenWithStaleRowSnapshot() throws {
        try withStorage { defaults, center, panelId, _ in
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            store.add("A")
            store.add("B")
            let original = store.items[1]
            store.togglePin(original)
            store.togglePin(original)
            XCTAssertEqual(store.items.map(\.text), ["B", "A"])
            XCTAssertEqual(store.pinnedCount, 0)
            store.togglePin(ToDoItem(text: "Unknown"))
            XCTAssertEqual(store.items.map(\.text), ["B", "A"])
        }
    }

    func testMovesStayWithinGroupsAndPersist() throws {
        try withStorage { defaults, center, panelId, key in
            try seed([
                ToDoItem(text: "A", isPinned: true), ToDoItem(text: "B", isPinned: true),
                ToDoItem(text: "C"), ToDoItem(text: "D")
            ], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertTrue(store.move(from: 0, to: 1))
            XCTAssertTrue(store.move(from: 3, to: 2))
            XCTAssertEqual(store.items.map(\.text), ["B", "A", "D", "C"])
            XCTAssertFalse(store.move(from: 1, to: 2))
            XCTAssertFalse(store.move(from: 2, to: 0))
            XCTAssertFalse(store.move(from: -1, to: 0))
            XCTAssertFalse(store.move(from: 0, to: 9))
            XCTAssertFalse(store.move(from: 0, to: 0))
            XCTAssertEqual(store.items.map(\.text), ["B", "A", "D", "C"])
            XCTAssertEqual(try storedItems(defaults, key), store.items)
        }
    }

    func testDeletingLastPinUpdatesCountAndPreservesOrdinaryOrder() throws {
        try withStorage { defaults, center, panelId, key in
            try seed([ToDoItem(text: "A", isPinned: true), ToDoItem(text: "B"), ToDoItem(text: "C")], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            store.delete(at: IndexSet(integer: 0))
            XCTAssertEqual(store.pinnedCount, 0)
            XCTAssertEqual(store.items.map(\.text), ["B", "C"])
            store.delete(at: IndexSet(integer: 99))
            XCTAssertEqual(store.items.count, 2)
        }
    }

    func testNewAndEditedTasksPreservePinStateAndOrdinaryAppendPosition() throws {
        try withStorage { defaults, center, panelId, key in
            try seed([ToDoItem(text: "Pinned", isPinned: true), ToDoItem(text: "Old")], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            store.add("  New \n")
            store.add(" \n ")
            let pinned = store.items[0]
            store.update(pinned, newText: " Updated ")
            store.update(pinned, newText: " ")
            XCTAssertEqual(store.items.map(\.text), ["Updated", "Old", "New"])
            XCTAssertEqual(store.items[0].id, pinned.id)
            XCTAssertTrue(store.items[0].isPinned)
            XCTAssertFalse(store.items[2].isPinned)
            XCTAssertEqual(store.pinnedCount, 1)
        }
    }

    func testClassificationAppendMigratesAndSynchronizesWithoutLosingPins() throws {
        try withStorage { defaults, center, panelId, key in
            try seed([ToDoItem(text: "Pinned", isPinned: true), ToDoItem(text: "Old")], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            let pinnedId = store.items[0].id
            try seed(store.items + [ToDoItem(text: "Done", isDone: true)], defaults, key)
            let count = ToDoStore.appendAssignments(
                [panelId: [" New 1 ", "", " New 2 "]], defaults: defaults, notificationCenter: center
            )
            XCTAssertEqual(count, 2)
            XCTAssertEqual(store.items.map(\.text), ["Pinned", "Old", "New 1", "New 2"])
            XCTAssertEqual(store.items[0].id, pinnedId)
            XCTAssertEqual(store.pinnedCount, 1)
            XCTAssertEqual(try storedItems(defaults, key), store.items)
        }
    }

    func testExternalReloadMigratesAndOnlyAffectsMatchingPanel() throws {
        try withStorage { defaults, center, panelId, key in
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            store.add("Original")
            try seed([ToDoItem(text: "Done", isDone: true), ToDoItem(text: "Ordinary"), ToDoItem(text: "Pinned", isPinned: true)], defaults, key)
            center.post(name: .todoItemsDidChange, object: nil, userInfo: ["panelId": UUID()])
            XCTAssertEqual(store.items.map(\.text), ["Original"])
            center.post(name: .todoItemsDidChange, object: nil, userInfo: ["panelId": panelId])
            XCTAssertEqual(store.items.map(\.text), ["Pinned", "Ordinary"])
            XCTAssertEqual(store.pinnedCount, 1)
        }
    }

    func testCorruptDataIsNotOverwrittenByMigrationOrClassification() throws {
        try withStorage { defaults, center, panelId, key in
            let corrupt = Data("invalid json".utf8)
            defaults.set(corrupt, forKey: key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertTrue(store.items.isEmpty)
            XCTAssertEqual(defaults.data(forKey: key), corrupt)
            XCTAssertEqual(ToDoStore.appendTasks(["New"], to: panelId, defaults: defaults, notificationCenter: center), 0)
            XCTAssertEqual(defaults.data(forKey: key), corrupt)
        }
    }

    func testCorruptReloadPreservesCurrentItems() throws {
        try withStorage { defaults, center, panelId, key in
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            store.add("Kept")
            let corrupt = Data("invalid".utf8)
            defaults.set(corrupt, forKey: key)
            center.post(name: .todoItemsDidChange, object: nil, userInfo: ["panelId": panelId])
            XCTAssertEqual(store.items.map(\.text), ["Kept"])
            XCTAssertEqual(defaults.data(forKey: key), corrupt)
        }
    }

    func testStructureInvalidationPrecedesMutationButNotDragMoves() throws {
        try withStorage { defaults, center, panelId, key in
            try seed([ToDoItem(text: "A"), ToDoItem(text: "B")], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            var snapshots: [[String]] = []
            let subscription = store.willChangeStructure.sink {
                snapshots.append(store.items.map(\.text))
            }
            XCTAssertTrue(store.move(from: 0, to: 1))
            XCTAssertTrue(snapshots.isEmpty)
            store.togglePin(store.items[1])
            XCTAssertEqual(snapshots, [["B", "A"]])
            store.delete(at: IndexSet(integer: 0))
            XCTAssertEqual(snapshots, [["B", "A"], ["A", "B"]])
            center.post(name: .todoItemsDidChange, object: nil, userInfo: ["panelId": panelId])
            XCTAssertEqual(snapshots.count, 3)
            withExtendedLifetime(subscription) {}
        }
    }

    func testSingleTaskCanPinUnpinAndReturnToEmptyList() throws {
        try withStorage { defaults, center, panelId, key in
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertTrue(store.items.isEmpty)
            XCTAssertEqual(store.pinnedCount, 0)
            store.add("Only")
            let item = store.items[0]
            store.togglePin(item)
            XCTAssertEqual(store.items.map(\.id), [item.id])
            XCTAssertEqual(store.pinnedCount, 1)
            XCTAssertFalse(store.move(from: 0, to: 0))
            store.togglePin(item)
            XCTAssertEqual(store.pinnedCount, 0)
            store.delete(at: IndexSet(integer: 0))
            XCTAssertTrue(try storedItems(defaults, key).isEmpty)
        }
    }

    func testAllPinnedTasksCanMoveAndNewTaskStartsOrdinaryGroup() throws {
        try withStorage { defaults, center, panelId, key in
            try seed([ToDoItem(text: "A", isPinned: true), ToDoItem(text: "B", isPinned: true)], defaults, key)
            let store = ToDoStore(panelId: panelId, defaults: defaults, notificationCenter: center)
            XCTAssertTrue(store.move(from: 0, to: 1))
            store.add("C")
            XCTAssertEqual(store.items.map(\.text), ["B", "A", "C"])
            XCTAssertEqual(store.items.map(\.isPinned), [true, true, false])
            store.togglePin(store.items[0])
            XCTAssertEqual(store.items.map(\.text), ["A", "B", "C"])
            XCTAssertEqual(store.pinnedCount, 1)
        }
    }

    private func withStorage(
        _ body: (UserDefaults, NotificationCenter, UUID, String) throws -> Void
    ) throws {
        let suite = "ToDoStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panelId = UUID()
        try body(defaults, NotificationCenter(), panelId, "toDoItems_\(panelId.uuidString)")
    }

    private func seed(_ items: [ToDoItem], _ defaults: UserDefaults, _ key: String) throws {
        defaults.set(try JSONEncoder().encode(items), forKey: key)
    }

    private func storedItems(_ defaults: UserDefaults, _ key: String) throws -> [ToDoItem] {
        try JSONDecoder().decode([ToDoItem].self, from: XCTUnwrap(defaults.data(forKey: key)))
    }
}
