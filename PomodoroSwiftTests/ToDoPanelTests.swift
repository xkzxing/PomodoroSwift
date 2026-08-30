import XCTest
@testable import PomodoroSwift

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
}
