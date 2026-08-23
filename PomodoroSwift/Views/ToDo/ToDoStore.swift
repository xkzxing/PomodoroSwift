import SwiftUI
import Combine

class ToDoStore: ObservableObject {
    @Published var items: [ToDoItem] = [] {
        didSet { save() }
    }

    private let panelId: UUID
    private let key: String
    private var itemsSyncObserver: NSObjectProtocol?

    init(panelId: UUID) {
        self.panelId = panelId
        self.key = "toDoItems_\(panelId.uuidString)"

        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ToDoItem].self, from: data) {
            self.items = decoded
        } else if !UserDefaults.standard.bool(forKey: "hasMigratedLegacyToDoStore"),
                  let legacyData = UserDefaults.standard.data(forKey: "toDoItems"),
                  let legacyDecoded = try? JSONDecoder().decode([ToDoItem].self, from: legacyData) {
            self.items = legacyDecoded
            save()
            UserDefaults.standard.set(true, forKey: "hasMigratedLegacyToDoStore")
        }

        setupItemsSyncObserver()
    }

    deinit {
        if let itemsSyncObserver {
            NotificationCenter.default.removeObserver(itemsSyncObserver)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func setupItemsSyncObserver() {
        itemsSyncObserver = NotificationCenter.default.addObserver(
            forName: .todoItemsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let changedPanelId = notification.userInfo?["panelId"] as? UUID,
                  changedPanelId == self.panelId else { return }
            self.reloadFromStorage()
        }
    }

    private func reloadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ToDoItem].self, from: data) {
            self.items = decoded
        } else {
            self.items = []
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(ToDoItem(text: trimmed))
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func toggle(_ item: ToDoItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isDone.toggle()
        }
    }

    func update(_ item: ToDoItem, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].text = trimmed
        }
    }

    @discardableResult
    static func appendAssignments(_ assignments: [UUID: [String]]) -> Int {
        var totalInserted = 0

        for (panelId, tasks) in assignments {
            totalInserted += appendTasks(tasks, to: panelId)
        }

        return totalInserted
    }

    @discardableResult
    static func appendTasks(_ tasks: [String], to panelId: UUID) -> Int {
        let key = "toDoItems_\(panelId.uuidString)"
        let normalizedTasks = tasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedTasks.isEmpty else { return 0 }

        var existingItems: [ToDoItem] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ToDoItem].self, from: data) {
            existingItems = decoded
        }

        let newItems = normalizedTasks.map { ToDoItem(text: $0) }
        existingItems.append(contentsOf: newItems)

        guard let encoded = try? JSONEncoder().encode(existingItems) else { return 0 }
        UserDefaults.standard.set(encoded, forKey: key)

        NotificationCenter.default.post(
            name: .todoItemsDidChange,
            object: nil,
            userInfo: ["panelId": panelId]
        )

        return newItems.count
    }
}
