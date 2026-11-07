import XCTest
@testable import PomodoroSwift

@MainActor
final class ToDoPanelTests: XCTestCase {
    func testLegacyPanelDataUsesDefaultExpandedHeight() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Legacy"
        }
        """

        let panel = try JSONDecoder().decode(ToDoPanel.self, from: Data(json.utf8))

        XCTAssertEqual(panel.id, id)
        XCTAssertEqual(panel.title, "Legacy")
        XCTAssertEqual(panel.expandedHeight, 180)
    }

    func testExpandedHeightRoundTrips() throws {
        let original = ToDoPanel(title: "Work", expandedHeight: 320)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToDoPanel.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testTodayMigrationRemovesEmptyFirstPanelOnlyOnce() throws {
        let suite = "ToDoPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldToday = ToDoPanel(title: "Today")
        let work = ToDoPanel(title: "Work")
        defaults.set(try JSONEncoder().encode([oldToday, work]), forKey: "todoPanels")

        XCTAssertEqual(ToDoPanel.loadOrdinaryPanels(defaults: defaults), [work])

        defaults.set(try JSONEncoder().encode([oldToday, work]), forKey: "todoPanels")
        XCTAssertEqual(ToDoPanel.loadOrdinaryPanels(defaults: defaults), [oldToday, work])
    }

    func testTodayMigrationKeepsOriginalIDAndTasksWhenStorageIsNotEmpty() throws {
        let suite = "ToDoPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldToday = ToDoPanel(title: "Today")
        let work = ToDoPanel(title: "Work")
        let key = "toDoItems_\(oldToday.id.uuidString)"
        let data = try JSONEncoder().encode([ToDoItem(text: "Keep this task")])
        defaults.set(try JSONEncoder().encode([oldToday, work]), forKey: "todoPanels")
        defaults.set(data, forKey: key)

        let panels = ToDoPanel.loadOrdinaryPanels(defaults: defaults)
        XCTAssertEqual(panels.map(\.id), [oldToday.id, work.id])
        XCTAssertEqual(panels.first?.title, "原今日待办")
        XCTAssertEqual(defaults.data(forKey: key), data)
        XCTAssertEqual(ToDoPanel.loadOrdinaryPanels(defaults: defaults), panels)
    }

    func testStoredDoublePreservesZeroInsteadOfUsingFallback() throws {
        let suite = "ToDoPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(Settings.storedDouble("opacity", defaults: defaults, fallback: 0.15), 0.15)
        defaults.set(0.0, forKey: "opacity")
        XCTAssertEqual(Settings.storedDouble("opacity", defaults: defaults, fallback: 0.15), 0)
    }
}
