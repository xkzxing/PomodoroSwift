import SwiftUI
import Combine

class ToDoStore: ObservableObject {
    @Published private(set) var items: [ToDoItem] = [] {
        didSet {
            if !isReloading { save() }
        }
    }

    // Reordering keeps an active drag alive; other mutations invalidate its geometry.
    let willChangeStructure = PassthroughSubject<Void, Never>()

    var pinnedCount: Int { items.filter(\.isPinned).count }

    private let panelId: UUID
    private let key: String
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var itemsSyncObserver: NSObjectProtocol?
    private var isReloading = false

    init(
        panelId: UUID,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.panelId = panelId
        self.key = Self.storageKey(for: panelId)
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        if let loaded = try? Self.loadItems(for: panelId, defaults: defaults) {
            self.items = loaded
        }
        setupItemsSyncObserver()
    }

    deinit {
        if let itemsSyncObserver {
            notificationCenter.removeObserver(itemsSyncObserver)
        }
    }

    private static func storageKey(for panelId: UUID) -> String {
        "toDoItems_\(panelId.uuidString)"
    }

    static func canRemoveEmptyLegacyPanel(_ panelId: UUID, defaults: UserDefaults) -> Bool {
        var keys = [storageKey(for: panelId)]
        if !defaults.bool(forKey: "hasMigratedLegacyToDoStore") {
            keys.append("toDoItems")
        }
        return keys.allSatisfy { key in
            guard let stored = defaults.object(forKey: key) else { return true }
            guard let data = stored as? Data,
                  let items = try? JSONDecoder().decode([ToDoItem].self, from: data) else { return false }
            return items.allSatisfy(\.isDone)
        }
    }

    private static func loadItems(for panelId: UUID, defaults: UserDefaults) throws -> [ToDoItem] {
        let key = storageKey(for: panelId)
        let isLegacy: Bool
        let data: Data
        if let panelData = defaults.data(forKey: key) {
            data = panelData
            isLegacy = false
        } else if !defaults.bool(forKey: "hasMigratedLegacyToDoStore"),
                  let legacyData = defaults.data(forKey: "toDoItems") {
            data = legacyData
            isLegacy = true
        } else {
            return []
        }

        // Decode the entire list before writing anything. Corrupt data must not be overwritten.
        let decoded = try JSONDecoder().decode([ToDoItem].self, from: data)
        let remaining = decoded.filter { !$0.isDone }
        let normalized = remaining.filter(\.isPinned) + remaining.filter { !$0.isPinned }
        if isLegacy || normalized != decoded {
            defaults.set(try JSONEncoder().encode(normalized), forKey: key)
        }
        if isLegacy {
            defaults.set(true, forKey: "hasMigratedLegacyToDoStore")
        }
        return normalized
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
            notificationCenter.post(name: .todoItemsDidChange, object: self, userInfo: ["panelId": panelId])
        }
    }

    private func setupItemsSyncObserver() {
        itemsSyncObserver = notificationCenter.addObserver(
            forName: .todoItemsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  (notification.object as? ToDoStore) !== self,
                  let changedPanelId = notification.userInfo?["panelId"] as? UUID,
                  changedPanelId == self.panelId else { return }
            self.reloadFromStorage()
        }
    }

    private func reloadFromStorage() {
        guard let loaded = try? Self.loadItems(for: panelId, defaults: defaults) else { return }
        willChangeStructure.send()
        isReloading = true
        items = loaded
        isReloading = false
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        willChangeStructure.send()
        items.append(ToDoItem(text: trimmed))
    }

    func delete(at offsets: IndexSet) {
        let validOffsets = IndexSet(offsets.filter { items.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }
        willChangeStructure.send()
        items.remove(atOffsets: validOffsets)
    }

    func delete(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        delete(at: IndexSet(integer: index))
    }

    func setInToday(_ isInToday: Bool, id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].isInToday != isInToday else { return }
        items[index].isInToday = isInToday
    }

    func togglePin(_ item: ToDoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        var moved = updated.remove(at: index)
        moved.isPinned.toggle()
        let boundary = updated.filter(\.isPinned).count
        // Both transitions land at the boundary: last pinned, or first ordinary.
        updated.insert(moved, at: boundary)
        willChangeStructure.send()
        items = updated
    }

    @discardableResult
    func move(from fromIndex: Int, to toIndex: Int) -> Bool {
        guard let offset = ToDoReorderEngine.rowTargetOffset(
            fromIndex: fromIndex, toIndex: toIndex, items: items
        ) else { return false }
        var reordered = items
        reordered.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: offset)
        items = reordered
        return true
    }

    func update(_ item: ToDoItem, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = items.firstIndex(where: { $0.id == item.id }),
              items[index].text != trimmed else { return }
        willChangeStructure.send()
        items[index].text = trimmed
    }

    @discardableResult
    static func appendAssignments(
        _ assignments: [UUID: [String]],
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) -> Int {
        assignments.reduce(0) { total, assignment in
            total + appendTasks(
                assignment.value, to: assignment.key,
                defaults: defaults, notificationCenter: notificationCenter
            )
        }
    }

    @discardableResult
    static func appendTasks(
        _ tasks: [String], to panelId: UUID,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) -> Int {
        let normalizedTasks = tasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedTasks.isEmpty,
              var existing = try? loadItems(for: panelId, defaults: defaults) else { return 0 }
        existing.append(contentsOf: normalizedTasks.map { ToDoItem(text: $0) })
        guard let encoded = try? JSONEncoder().encode(existing) else { return 0 }
        defaults.set(encoded, forKey: storageKey(for: panelId))
        notificationCenter.post(
            name: .todoItemsDidChange, object: nil, userInfo: ["panelId": panelId]
        )
        return normalizedTasks.count
    }
}

final class ToDoPanelStores: ObservableObject {
    @Published private(set) var stores: [UUID: ToDoStore] = [:]
    private var subscriptions: [UUID: AnyCancellable] = [:]

    init(panels: [ToDoPanel]) {
        updatePanels(panels)
    }

    func updatePanels(_ panels: [ToDoPanel]) {
        let ids = Set(panels.map(\.id))
        guard ids != Set(stores.keys) else { return }

        var updated = stores.filter { ids.contains($0.key) }
        subscriptions = subscriptions.filter { ids.contains($0.key) }
        // Open stores in panel order so the first panel can claim any old single-list data.
        for panel in panels where updated[panel.id] == nil {
            let store = ToDoStore(panelId: panel.id)
            updated[panel.id] = store
            subscriptions[panel.id] = store.$items.dropFirst().sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        stores = updated
    }
}
