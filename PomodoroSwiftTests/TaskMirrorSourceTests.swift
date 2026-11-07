import XCTest
import AppKit
@testable import PomodoroSwift

@MainActor
final class TaskMirrorSourceTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "TaskMirrorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testExportUsesDesktopIDsOrderPinnedPartitionAndColors() throws {
        let defaults = defaults()
        let first = ToDoPanel(title: "工作")
        let second = ToDoPanel(title: "其他")
        let normal = ToDoItem(text: "普通", isInToday: true)
        let pinned = ToDoItem(text: "置顶", isPinned: true)
        let done = ToDoItem(text: "已完成", isDone: true, isInToday: true)
        defaults.set(try JSONEncoder().encode([second, first]), forKey: "todoPanels")
        defaults.set(try JSONEncoder().encode([normal, pinned, done]), forKey: "toDoItems_\(first.id.uuidString)")
        let appearance = PanelAppearanceSettings(panelId: first.id, fallback: .taskDefault(at: 1), defaults: defaults)
        appearance.colors = .init(.purple)
        defaults.set(false, forKey: "sidebarDarkMode")
        defaults.set("clear", forKey: "glassVariant")
        defaults.set(0.0, forKey: "glassTintOpacity")
        let result = try DesktopTaskMirrorSource.panels(defaults: defaults)
        XCTAssertEqual(result.map(\.id), [second.id, first.id])
        XCTAssertEqual(result[1].items.map(\.id), [pinned.id, normal.id])
        XCTAssertEqual(result[1].items.filter(\.isInToday).map(\.id), [normal.id])
        XCTAssertEqual(result[0].appearance.tintRGB, ScenePanelColor.green.rgb(for: .light))
        XCTAssertEqual(result[1].appearance.tintRGB, ScenePanelColor.purple.rgb(for: .light))
        XCTAssertTrue(result[1].appearance.darkText)
        XCTAssertEqual(result[1].appearance.daylightPalette?.darkRGB, ScenePanelColor.purple.rgb(for: .dark))
        XCTAssertTrue(result[1].appearance.clearGlass)
        XCTAssertEqual(result[1].appearance.opacity, 0.50)
        defaults.set(true, forKey: "sidebarDarkMode")
        defaults.set(0.0, forKey: "panelGlassTintOpacity")
        let dark = try DesktopTaskMirrorSource.panels(defaults: defaults)
        XCTAssertEqual(dark[1].appearance.tintRGB, ScenePanelColor.purple.rgb(for: .dark))
        XCTAssertFalse(dark[1].appearance.darkText)
        XCTAssertEqual(dark[1].appearance.opacity, 0)
        // Exporting does not normalize or otherwise modify the author's saved tasks.
        let stored = try JSONDecoder().decode([ToDoItem].self, from: defaults.data(forKey: "toDoItems_\(first.id.uuidString)")!)
        XCTAssertEqual(stored.map(\.id), [normal.id, pinned.id, done.id])
    }

    func testCorruptPanelDataStopsExportInsteadOfPublishingEmptyTasks() throws {
        let defaults = defaults()
        let panel = ToDoPanel(title: "重要")
        defaults.set(try JSONEncoder().encode([panel]), forKey: "todoPanels")
        defaults.set(Data("broken".utf8), forKey: "toDoItems_\(panel.id.uuidString)")
        XCTAssertThrowsError(try DesktopTaskMirrorSource.panels(defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: "toDoItems_\(panel.id.uuidString)"), Data("broken".utf8))
    }

    func testLakeAndRetiredWindowUseDaylightForPanelColors() throws {
        let defaults = defaults()
        let panel = ToDoPanel(title: "工作")
        defaults.set(try JSONEncoder().encode([panel]), forKey: "todoPanels")
        defaults.set("window", forKey: "backgroundTheme")
        defaults.set(true, forKey: "sidebarDarkMode")
        let colorKey = "panelColors_\(panel.id.uuidString)"
        defaults.set("red:green", forKey: colorKey)
        let colors = PanelAppearanceSettings(panelId: panel.id, fallback: .taskDefault(at: 0), defaults: defaults)
        XCTAssertEqual(colors.colors, ScenePanelColors(.green))
        XCTAssertEqual(defaults.string(forKey: colorKey), "green")

        let clock = Calendar.autoupdatingCurrent
        let day = try XCTUnwrap(clock.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        let night = try XCTUnwrap(clock.date(bySettingHour: 0, minute: 0, second: 0, of: day))
        XCTAssertEqual(BackgroundTheme(storedValue: "window"), .lakeside)
        XCTAssertEqual(try DesktopTaskMirrorSource.panels(defaults: defaults, now: day)[0].appearance.tintRGB,
                       ScenePanelColor.green.rgb(for: .light))
        XCTAssertEqual(try DesktopTaskMirrorSource.panels(defaults: defaults, now: night)[0].appearance.tintRGB,
                       ScenePanelColor.green.rgb(for: .dark))
        XCTAssertEqual(ScenePanelPhase(sky: BackgroundTimePreview.dawn.sky(at: day, coordinates: nil)), .light)
        XCTAssertEqual(ScenePanelPhase(sky: BackgroundTimePreview.dusk.sky(at: day, coordinates: nil)), .dark)
    }

    func testRestoresOldCustomHueAndKeepsDistinctDefaultsWithTheirPanels() throws {
        let defaults = defaults()
        let first = ToDoPanel(title: "一")
        let second = ToDoPanel(title: "二")
        let third = ToDoPanel(title: "三")
        defaults.set(try JSONEncoder().encode([first, second, third]), forKey: "todoPanels")
        defaults.set(true, forKey: "todoGlassUseCustom_\(first.id.uuidString)")
        defaults.set([0.65, 0.20, 0.81], forKey: "todoGlassTintColor_\(first.id.uuidString)")

        let migrated = PanelAppearanceSettings(panelId: first.id, fallback: .taskDefault(at: 0), defaults: defaults)
        XCTAssertEqual(migrated.colors, ScenePanelColors(.purple))
        let assigned = PanelAppearanceSettings(panelId: second.id, fallback: .taskDefault(at: 1), defaults: defaults)
        XCTAssertEqual(assigned.colors, ScenePanelColors(.orange))
        let mirrored = try DesktopTaskMirrorSource.panels(defaults: defaults)
        XCTAssertEqual(mirrored.map(\.appearance.tintRGB), [.purple, .orange, .red].map { (tint: ScenePanelColor) in
            tint.rgb(for: .dark)
        })

        migrated.colors = .init(.cyan)
        let reopened = PanelAppearanceSettings(panelId: first.id, fallback: .taskDefault(at: 4), defaults: defaults)
        XCTAssertEqual(reopened.colors, migrated.colors)
        let reordered = PanelAppearanceSettings(panelId: second.id, fallback: .taskDefault(at: 0), defaults: defaults)
        XCTAssertEqual(reordered.colors, ScenePanelColors(.orange))
    }

    func testLegacyTasksAreExportedOnlyIntoFirstPanel() throws {
        let defaults = defaults()
        defaults.set(try JSONEncoder().encode([ToDoPanel(title: "一"), ToDoPanel(title: "二")]), forKey: "todoPanels")
        defaults.set(try JSONEncoder().encode([ToDoItem(text: "旧待办")]), forKey: "toDoItems")
        let result = try DesktopTaskMirrorSource.panels(defaults: defaults)
        XCTAssertEqual(result[0].items.count, 1)
        XCTAssertTrue(result[1].items.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: "hasMigratedLegacyToDoStore"))
    }

    func testWriterUsesIncreasingVersionsAndPreservesForeignPublisherFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = DesktopTaskMirrorWriter()
        let publisher = UUID()
        let first = try await writer.publish(panels: [], directory: directory, publisherID: publisher, previousRevision: 0)
        let second = try await writer.publish(panels: [], directory: directory, publisherID: publisher, previousRevision: 0)
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(second.revision, 2)
        let file = directory.appendingPathComponent(TaskMirrorSnapshot.fileName)
        let original = try Data(contentsOf: file)
        do {
            _ = try await writer.publish(panels: [], directory: directory, publisherID: UUID(), previousRevision: 100)
            XCTFail("Must not overwrite another computer's snapshot")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try TaskMirrorSnapshot.decode(original).revision, 2)
    }
    func testPublisherOnlyExportsAfterSaveDelayOrManualRequest() async throws {
        let defaults = defaults()
        let panel = ToDoPanel(title: "电脑原始面板")
        defaults.set(try JSONEncoder().encode([panel]), forKey: "todoPanels")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let publisher = DesktopTaskPublisher(defaults: defaults)
        publisher.startObserving()
        publisher.selectDirectory(directory)
        let file = directory.appendingPathComponent(TaskMirrorSnapshot.fileName)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: file.path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let first = try TaskMirrorSnapshot.decode(Data(contentsOf: file))
        XCTAssertEqual(first.today, .init())
        // Reopening does not publish, even if the application becomes active.
        let restored = DesktopTaskPublisher(defaults: defaults)
        restored.startObserving()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(try TaskMirrorSnapshot.decode(Data(contentsOf: file)).revision, first.revision)
        publisher.disconnect()
        var edited = panel
        edited.title = "修改后的面板"
        defaults.set(try JSONEncoder().encode([edited]), forKey: "todoPanels")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(try TaskMirrorSnapshot.decode(Data(contentsOf: file)).revision, first.revision)
        for _ in 0..<50 {
            let current = try TaskMirrorSnapshot.decode(Data(contentsOf: file))
            if current.panels.first?.title == edited.title { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let second = try TaskMirrorSnapshot.decode(Data(contentsOf: file))
        XCTAssertEqual(second.panels.first?.title, edited.title)
        defaults.set("sky", forKey: "todayPanelTheme")
        defaults.set(0.77, forKey: "todaySkyColorConcentration")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        for _ in 0..<50 {
            if try TaskMirrorSnapshot.decode(Data(contentsOf: file)).today?.theme == .sky { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let third = try TaskMirrorSnapshot.decode(Data(contentsOf: file))
        XCTAssertGreaterThan(third.revision, second.revision)
        XCTAssertEqual(third.today, .init(theme: .sky, skyConcentration: 0.77))
        restored.publish(force: true)
        for _ in 0..<50 {
            if try TaskMirrorSnapshot.decode(Data(contentsOf: file)).revision > third.revision { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(try TaskMirrorSnapshot.decode(Data(contentsOf: file)).revision, third.revision)
        restored.disconnect()
    }

}
