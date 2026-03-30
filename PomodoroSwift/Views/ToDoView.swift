//
//  ToDoView.swift
//  PomodoroSwift
//

import SwiftUI
import Combine

// MARK: - Data Model

struct ToDoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var isDone: Bool

    init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

// MARK: - Persistence

class ToDoStore: ObservableObject {
    @Published var items: [ToDoItem] = [] {
        didSet { save() }
    }

    private let key: String

    init(panelId: UUID) {
        self.key = "toDoItems_\(panelId.uuidString)"
        
        // Attempt to load from new unique key
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ToDoItem].self, from: data) {
            self.items = decoded
        } 
        // Migration: If no unique key data exists, but legacy global data exists, import it once ONLY!
        else if !UserDefaults.standard.bool(forKey: "hasMigratedLegacyToDoStore"),
                let legacyData = UserDefaults.standard.data(forKey: "toDoItems"),
                let legacyDecoded = try? JSONDecoder().decode([ToDoItem].self, from: legacyData) {
            self.items = legacyDecoded
            save() // Save immediately to new key
            UserDefaults.standard.set(true, forKey: "hasMigratedLegacyToDoStore")
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
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

}

// MARK: - To-Do Glass Settings (persistent, per-panel)

class ToDoGlassSettings: ObservableObject {
    let panelId: UUID

    private func key(_ base: String) -> String {
        return "\(base)_\(panelId.uuidString)"
    }

    @Published var useCustom: Bool {
        didSet { UserDefaults.standard.set(useCustom, forKey: key("todoGlassUseCustom")) }
    }
    @Published var variant: String {
        didSet { UserDefaults.standard.set(variant, forKey: key("todoGlassVariant")) }
    }
    @Published var tintColor: Color {
        didSet {
            if let components = tintColor.cgColor?.components, components.count >= 3 {
                UserDefaults.standard.set([components[0], components[1], components[2]], forKey: key("todoGlassTintColor"))
            }
        }
    }
    @Published var tintOpacity: Double {
        didSet { UserDefaults.standard.set(tintOpacity, forKey: key("todoGlassTintOpacity")) }
    }
    @Published var fontDark: Bool {
        didSet { UserDefaults.standard.set(fontDark, forKey: key("todoFontDark")) }
    }

    // Drag position
    @Published var offsetX: Double {
        didSet { UserDefaults.standard.set(offsetX, forKey: key("todoOffsetX")) }
    }
    @Published var offsetY: Double {
        didSet { UserDefaults.standard.set(offsetY, forKey: key("todoOffsetY")) }
    }

    // Resize extra height
    @Published var extraHeight: Double {
        didSet { UserDefaults.standard.set(extraHeight, forKey: key("todoExtraHeight")) }
    }
    @Published var extraWidth: Double {
        didSet { UserDefaults.standard.set(extraWidth, forKey: key("todoExtraWidth")) }
    }

    init(panelId: UUID) {
        self.panelId = panelId
        
        func k(_ base: String) -> String { "\(base)_\(panelId.uuidString)" }

        // MIGRATION HELPER: Fallback to global legacy keys if new unique key is empty
        func migrate<T>(base: String, type: T.Type) -> T? {
            let uniqueKey = k(base)
            if UserDefaults.standard.object(forKey: uniqueKey) != nil {
                return UserDefaults.standard.object(forKey: uniqueKey) as? T
            }
            if !UserDefaults.standard.bool(forKey: "hasMigratedLegacyGlass") {
                if UserDefaults.standard.object(forKey: base) != nil {
                    let val = UserDefaults.standard.object(forKey: base) as? T
                    UserDefaults.standard.set(val, forKey: uniqueKey) // Save immediately to new key spaces
                    return val
                }
            }
            return nil
        }

        self.useCustom = migrate(base: "todoGlassUseCustom", type: Bool.self) ?? false
        self.variant = migrate(base: "todoGlassVariant", type: String.self) ?? "regular"
        if let arr = migrate(base: "todoGlassTintColor", type: [CGFloat].self), arr.count >= 3 {
            self.tintColor = Color(red: arr[0], green: arr[1], blue: arr[2])
        } else {
            self.tintColor = .white
        }
        let savedOpacity = migrate(base: "todoGlassTintOpacity", type: Double.self) ?? 0
        self.tintOpacity = savedOpacity != 0 ? savedOpacity : 0.15
        
        self.fontDark = migrate(base: "todoFontDark", type: Bool.self) ?? false
        
        // Default spawn position: slight jitter based on UUID to avoid stacking
        let jitter = Double(panelId.uuidString.first?.hexDigitValue ?? 0) * 5.0
        self.offsetX = migrate(base: "todoOffsetX", type: Double.self) ?? (60 + jitter)
        self.offsetY = migrate(base: "todoOffsetY", type: Double.self) ?? (100 + jitter)
        self.extraHeight = migrate(base: "todoExtraHeight", type: Double.self) ?? 0
        self.extraWidth = migrate(base: "todoExtraWidth", type: Double.self) ?? 0
        
        UserDefaults.standard.set(true, forKey: "hasMigratedLegacyGlass")
    }

    static let variants: [(String, String)] = [
        ("Clear", "clear"),
        ("Regular", "regular"),
    ]

    func buildGlass() -> Glass {
        let base: Glass = variant == "clear" ? .clear : .regular
        return base.tint(tintColor.opacity(tintOpacity))
    }
}

// MARK: - Environment Key for text color

private struct TodoTextColorKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

extension EnvironmentValues {
    var todoTextColor: Color {
        get { self[TodoTextColorKey.self] }
        set { self[TodoTextColorKey.self] = newValue }
    }
}

// MARK: - Preference Key for Row Frames (drag reorder)

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Drag Handle

private struct DragHandle: View {
    let textColor: Color
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(textColor.opacity(isHovered ? 0.5 : 0.2))
            .frame(width: 18, height: 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in onDragChanged(value.translation.height) }
                    .onEnded { value in onDragEnded(value.translation.height) }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - To-Do Panel View

struct ToDoView: View {
    let panel: ToDoPanel
    @StateObject private var store: ToDoStore
    @StateObject private var glassSettings: ToDoGlassSettings
    @EnvironmentObject private var settings: Settings
    @State private var newText: String = ""
    @State private var isExpanded: Bool = true
    @FocusState private var inputFocused: Bool

    // Drag-to-reorder state
    @State private var draggingItemId: UUID?
    @State private var dragYOffset: CGFloat = 0
    @State private var rowFrames: [UUID: CGRect] = [:]

    // Glass style from parent (used when not custom)
    var glassEffect: Glass
    // List max height passed from parent
    var listMaxHeight: CGFloat

    // Popover state
    @State private var showGlassPicker: Bool = false

    // Live drag/resize gestures (transient, added to persisted values)
    @State private var liveDragOffset: CGSize = .zero
    @State private var liveExtraSize: CGSize = .zero
    @State private var panelOffsetX: Double = 0
    @State private var panelOffsetY: Double = 0
    @State private var panelExtraHeight: Double = 0
    @State private var panelExtraWidth: Double = 0
    @State private var didLoadPanelLayout = false
    
    private let basePanelWidth: Double = 280
    private let minPanelWidth: Double = 200
    private let defaultExtraWidth: Double = 0
    private let defaultExtraHeight: Double = 0

    init(panel: ToDoPanel, glassEffect: Glass, listMaxHeight: CGFloat = 180) {
        self.panel = panel
        self.glassEffect = glassEffect
        self.listMaxHeight = listMaxHeight
        
        self._store = StateObject(wrappedValue: ToDoStore(panelId: panel.id))
        self._glassSettings = StateObject(wrappedValue: ToDoGlassSettings(panelId: panel.id))
    }

    private var effectiveGlass: Glass {
        glassSettings.useCustom ? glassSettings.buildGlass() : glassEffect
    }
    
    private var minExtraWidth: Double {
        minPanelWidth - basePanelWidth
    }
    
    private var minExtraHeight: Double {
        Double(-listMaxHeight + 44)
    }
    
    private func clampedExtraWidth(_ value: Double) -> Double {
        max(value, minExtraWidth)
    }
    
    private func clampedExtraHeight(_ value: Double) -> Double {
        max(value, minExtraHeight)
    }

    /// Calculates clamped delta width during drag to pin the left edge
    private var widthChangeDuringDrag: CGFloat {
        let currentDisplayWidth = max(basePanelWidth + panelExtraWidth, minPanelWidth)
        let newDisplayWidth = max(basePanelWidth + panelExtraWidth + Double(liveExtraSize.width), minPanelWidth)
        return CGFloat(newDisplayWidth - currentDisplayWidth)
    }

    /// Resolved text color: follows global setting when not using custom glass
    private var textColor: Color {
        let isDark = glassSettings.useCustom ? glassSettings.fontDark : !settings.sidebarDarkMode
        return isDark ? .black : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header / drag bar (pinned at top) ─────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.85))

                Text(panel.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.9))

                let remaining = store.items.filter { !$0.isDone }.count
                if remaining > 0 {
                    Text("\(remaining)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(textColor.opacity(0.25)))
                }

                Spacer()

                // Glass style picker button
                Button(action: { showGlassPicker.toggle() }) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(glassSettings.useCustom ? 0.85 : 0.45))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGlassPicker, arrowEdge: .top) {
                    ToDoGlassPopover(glassSettings: glassSettings, onResetLayout: resetPanelLayout)
                }

                // Chevron (tap to toggle expand/collapse)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isExpanded.toggle()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        liveDragOffset = value.translation
                    }
                    .onEnded { value in
                        panelOffsetX += Double(value.translation.width)
                        panelOffsetY += Double(value.translation.height)
                        liveDragOffset = .zero
                        persistPanelLayout()
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    resetPanelSize()
                }
            )
            .onHover { hovering in
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }

            // ── Expanded content (below header) ─────────────────────────────
            if isExpanded {
                Divider().background(.white.opacity(0.15))

                // Task list
                let computedHeight = max(listMaxHeight + CGFloat(panelExtraHeight) + liveExtraSize.height, 44)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.items) { item in
                            HStack(spacing: 0) {
                                DragHandle(textColor: textColor) { translation in
                                    if draggingItemId == nil { draggingItemId = item.id }
                                    dragYOffset = translation
                                } onDragEnded: { translation in
                                    handleDrop(for: item, translation: translation)
                                }

                                ToDoRow(item: item, onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        store.toggle(item)
                                    }
                                }, onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if let idx = store.items.firstIndex(where: { $0.id == item.id }) {
                                            store.delete(at: IndexSet(integer: idx))
                                        }
                                    }
                                }, onEdit: { newText in
                                    store.update(item, newText: newText)
                                })
                            }
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: RowFrameKey.self,
                                        value: [item.id: geo.frame(in: .named("todoReorder"))]
                                    )
                                }
                            )
                            .offset(y: draggingItemId == item.id ? dragYOffset : 0)
                            .zIndex(draggingItemId == item.id ? 1 : 0)
                            .opacity(draggingItemId == item.id ? 0.75 : 1.0)
                            .scaleEffect(draggingItemId == item.id ? 1.03 : 1.0)
                            .shadow(color: draggingItemId == item.id ? .black.opacity(0.18) : .clear, radius: 6, y: 2)
                        }
                    }
                    .coordinateSpace(name: "todoReorder")
                    .onPreferenceChange(RowFrameKey.self) { frames in
                        rowFrames = frames
                    }
                }
                .scrollDisabled(draggingItemId != nil)
                .frame(height: computedHeight)
                .environment(\.todoTextColor, textColor)

                if !store.items.isEmpty {
                    Divider().background(.white.opacity(0.15))
                }

                // Input field + Resize handle at the very bottom
                ZStack(alignment: .bottomTrailing) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.5))

                        TextField("Add a task…", text: $newText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(textColor)
                            .focused($inputFocused)
                            .onSubmit {
                                store.add(newText)
                                newText = ""
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .padding(.trailing, 20) // Leave space for resize handle
                    
                    // Resize handle (bottom right)
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(textColor.opacity(0.3))
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    liveExtraSize = value.translation
                                }
                                .onEnded { value in
                                    let newExtraHeight = clampedExtraHeight(panelExtraHeight + Double(value.translation.height))
                                    let oldDisplayExtraWidth = clampedExtraWidth(panelExtraWidth)
                                    let newDisplayExtraWidth = clampedExtraWidth(panelExtraWidth + Double(value.translation.width))
                                    let deltaWidth = newDisplayExtraWidth - oldDisplayExtraWidth
                                    
                                    panelExtraHeight = newExtraHeight
                                    panelExtraWidth = newDisplayExtraWidth
                                    // Keep left edge fixed while size changes around the horizontal center anchor.
                                    panelOffsetX += deltaWidth / 2
                                    liveExtraSize = .zero
                                    persistPanelLayout()
                                }
                        )
                        .onHover { hovering in
                            if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
                        }
                }
            }
        }
        .frame(width: CGFloat(max(basePanelWidth + panelExtraWidth + Double(liveExtraSize.width), minPanelWidth))) // Shrunk base width to 280
        .contentShape(Rectangle())
        .background(.clear)
        .glassEffect(effectiveGlass, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: -4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .offset(
            x: CGFloat(panelOffsetX) + liveDragOffset.width + widthChangeDuringDrag / 2,
            y: CGFloat(panelOffsetY) + liveDragOffset.height
        )
        .onAppear {
            loadPanelLayoutIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetToDoPanel)) { notification in
            if let targetId = notification.userInfo?["panelId"] as? UUID, targetId == panel.id {
                let jitter = Double(panel.id.uuidString.first?.hexDigitValue ?? 0) * 5.0
                withAnimation(.spring()) {
                    panelOffsetX = 60 + jitter
                    panelOffsetY = 100 + jitter
                    panelExtraWidth = defaultExtraWidth
                    panelExtraHeight = defaultExtraHeight
                    liveDragOffset = .zero
                    liveExtraSize = .zero
                }
                persistPanelLayout()
            }
        }
    }

    // MARK: - Drop handling
    
    private func loadPanelLayoutIfNeeded() {
        guard !didLoadPanelLayout else { return }
        panelOffsetX = glassSettings.offsetX
        panelOffsetY = glassSettings.offsetY
        panelExtraHeight = clampedExtraHeight(glassSettings.extraHeight)
        panelExtraWidth = clampedExtraWidth(glassSettings.extraWidth)
        didLoadPanelLayout = true
    }
    
    private func persistPanelLayout() {
        if glassSettings.offsetX != panelOffsetX {
            glassSettings.offsetX = panelOffsetX
        }
        if glassSettings.offsetY != panelOffsetY {
            glassSettings.offsetY = panelOffsetY
        }
        if glassSettings.extraHeight != panelExtraHeight {
            glassSettings.extraHeight = panelExtraHeight
        }
        if glassSettings.extraWidth != panelExtraWidth {
            glassSettings.extraWidth = panelExtraWidth
        }
    }
    
    private func resetPanelSize() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            panelExtraWidth = defaultExtraWidth
            panelExtraHeight = defaultExtraHeight
            liveExtraSize = .zero
        }
        persistPanelLayout()
    }
    
    private func resetPanelLayout() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            panelOffsetX = 0
            panelOffsetY = 0
            panelExtraWidth = defaultExtraWidth
            panelExtraHeight = defaultExtraHeight
            liveDragOffset = .zero
            liveExtraSize = .zero
        }
        persistPanelLayout()
    }

    private func handleDrop(for item: ToDoItem, translation: CGFloat) {
        guard let fromIndex = store.items.firstIndex(where: { $0.id == item.id }),
              let currentFrame = rowFrames[item.id] else {
            withAnimation(.easeInOut(duration: 0.2)) {
                draggingItemId = nil
                dragYOffset = 0
            }
            return
        }

        let dropMidY = currentFrame.midY + translation

        // Count how many rows have their center above the drop point
        var targetIndex = 0
        for storeItem in store.items {
            if let frame = rowFrames[storeItem.id], dropMidY > frame.midY {
                targetIndex += 1
            }
        }
        targetIndex = max(0, min(store.items.count, targetIndex))

        withAnimation(.easeInOut(duration: 0.25)) {
            // Only move if target differs from current position
            if fromIndex != targetIndex && fromIndex + 1 != targetIndex {
                store.items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: targetIndex)
            }
            draggingItemId = nil
            dragYOffset = 0
        }
    }
}

// MARK: - Glass Popover (matching app settings style)

struct ToDoGlassPopover: View {
    @ObservedObject var glassSettings: ToDoGlassSettings
    var onResetLayout: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toggle: Follow app or custom
            Toggle("自定义玻璃效果", isOn: $glassSettings.useCustom)
                .font(.system(size: 13, weight: .medium))

            if glassSettings.useCustom {
                Divider()

                // Glass Variant Picker
                HStack {
                    Text("Variant")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $glassSettings.variant) {
                        ForEach(ToDoGlassSettings.variants, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                // Color Picker
                HStack {
                    Text("Tint Color")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $glassSettings.tintColor, supportsOpacity: false)
                        .labelsHidden()
                }

                // Tint Opacity
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Tint Opacity")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f", glassSettings.tintOpacity))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $glassSettings.tintOpacity, in: 0.0...1.0, step: 0.01)
                }

                // Font color
                HStack {
                    Text("Font Color")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $glassSettings.fontDark) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            Divider()

            // Reset position button
            Button(action: {
                if let onResetLayout = onResetLayout {
                    onResetLayout()
                } else {
                    glassSettings.offsetX = 0
                    glassSettings.offsetY = 0
                    glassSettings.extraHeight = 0
                    glassSettings.extraWidth = 0
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                    Text("重置位置和大小")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 220)
    }
}

// MARK: - Single Row

struct ToDoRow: View {
    let item: ToDoItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool
    @Environment(\.todoTextColor) private var textColor

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isDone ? .green.opacity(0.85) : textColor.opacity(0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Text or inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .focused($editFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitEdit() }
                    .onChange(of: editFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDone ? textColor.opacity(0.35) : textColor.opacity(0.9))
                    .strikethrough(item.isDone, color: textColor.opacity(0.35))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gesture(
                        TapGesture(count: 2).onEnded {
                            editText = item.text
                            isEditing = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                editFocused = true
                            }
                        }
                    )
            }

            // Delete on hover (hidden while editing)
            if isHovered && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func commitEdit() {
        isEditing = false
        editFocused = false
        onEdit(editText)
    }
}
