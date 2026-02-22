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

    private let key = "toDoItems"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ToDoItem].self, from: data) {
            self.items = decoded
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
    @Published var useCustom: Bool {
        didSet { UserDefaults.standard.set(useCustom, forKey: "todoGlassUseCustom") }
    }
    @Published var variant: String {
        didSet { UserDefaults.standard.set(variant, forKey: "todoGlassVariant") }
    }
    @Published var tintColor: Color {
        didSet {
            if let components = tintColor.cgColor?.components, components.count >= 3 {
                UserDefaults.standard.set([components[0], components[1], components[2]], forKey: "todoGlassTintColor")
            }
        }
    }
    @Published var tintOpacity: Double {
        didSet { UserDefaults.standard.set(tintOpacity, forKey: "todoGlassTintOpacity") }
    }
    @Published var fontDark: Bool {
        didSet { UserDefaults.standard.set(fontDark, forKey: "todoFontDark") }
    }

    // Drag position
    @Published var offsetX: Double {
        didSet { UserDefaults.standard.set(offsetX, forKey: "todoOffsetX") }
    }
    @Published var offsetY: Double {
        didSet { UserDefaults.standard.set(offsetY, forKey: "todoOffsetY") }
    }

    // Resize extra height
    @Published var extraHeight: Double {
        didSet { UserDefaults.standard.set(extraHeight, forKey: "todoExtraHeight") }
    }
    @Published var extraWidth: Double {
        didSet { UserDefaults.standard.set(extraWidth, forKey: "todoExtraWidth") }
    }

    init() {
        self.useCustom = UserDefaults.standard.bool(forKey: "todoGlassUseCustom")
        self.variant = UserDefaults.standard.string(forKey: "todoGlassVariant") ?? "regular"
        if let arr = UserDefaults.standard.array(forKey: "todoGlassTintColor") as? [CGFloat], arr.count >= 3 {
            self.tintColor = Color(red: arr[0], green: arr[1], blue: arr[2])
        } else {
            self.tintColor = .white
        }
        let savedOpacity = UserDefaults.standard.double(forKey: "todoGlassTintOpacity")
        self.tintOpacity = savedOpacity != 0 ? savedOpacity : 0.15
        // fontDark: default false (light text on glass)
        self.fontDark = UserDefaults.standard.object(forKey: "todoFontDark") != nil
            ? UserDefaults.standard.bool(forKey: "todoFontDark")
            : false
        self.offsetX = UserDefaults.standard.double(forKey: "todoOffsetX")
        self.offsetY = UserDefaults.standard.double(forKey: "todoOffsetY")
        self.extraHeight = UserDefaults.standard.double(forKey: "todoExtraHeight")
        self.extraWidth = UserDefaults.standard.double(forKey: "todoExtraWidth")
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

// MARK: - To-Do Panel View

struct ToDoView: View {
    @StateObject private var store = ToDoStore()
    @StateObject private var glassSettings = ToDoGlassSettings()
    @State private var newText: String = ""
    @State private var isExpanded: Bool = true
    @FocusState private var inputFocused: Bool

    // Glass style from parent (used when not custom)
    var glassEffect: Glass
    // List max height passed from parent
    var listMaxHeight: CGFloat = 180

    // Popover state
    @State private var showGlassPicker: Bool = false

    // Live drag/resize gestures (transient, added to persisted values)
    @State private var liveDragOffset: CGSize = .zero
    @State private var liveExtraSize: CGSize = .zero

    private var effectiveGlass: Glass {
        glassSettings.useCustom ? glassSettings.buildGlass() : glassEffect
    }

    /// Resolved text color for this panel
    private var textColor: Color { glassSettings.fontDark ? .black : .white }

    var body: some View {
        VStack(spacing: 0) {
            // ── Expanded content (above header) ─────────────────────────────
            if isExpanded {
                // ── Resize handle (top edge) ──────────────────────────────────
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(textColor.opacity(0.3))
                        .padding(.leading, 10)
                        .padding(.top, 4)
                        .frame(width: 40, height: 16)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    liveExtraSize = value.translation
                                }
                                .onEnded { value in
                                    let newExtraH = glassSettings.extraHeight - value.translation.height
                                    let newExtraW = glassSettings.extraWidth + value.translation.width
                                    glassSettings.extraHeight = max(newExtraH, -listMaxHeight + 44)
                                    glassSettings.extraWidth = max(newExtraW, -160)
                                    liveExtraSize = .zero
                                }
                        )
                        .onHover { hovering in
                            if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
                        }
                    Spacer()
                }

                // Input field
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

                Divider().background(.white.opacity(0.15))

                // Task list
                if !store.items.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.items) { item in
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
                        }
                    }
                    .frame(maxHeight: max(listMaxHeight + glassSettings.extraHeight - liveExtraSize.height, 44))
                    .environment(\.todoTextColor, textColor)
                }

                Divider().background(.white.opacity(0.15))
            }

            // ── Header / drag bar (pinned at bottom) ─────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.85))

                Text("To-Do")
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
                .popover(isPresented: $showGlassPicker, arrowEdge: .bottom) {
                    ToDoGlassPopover(glassSettings: glassSettings)
                }

                // Chevron (tap to toggle expand/collapse)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
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
                        glassSettings.offsetX += value.translation.width
                        glassSettings.offsetY += value.translation.height
                        liveDragOffset = .zero
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
        }
        .frame(width: max(360 + glassSettings.extraWidth + liveExtraSize.width, 200)) // Apply width modification here
        .contentShape(Rectangle())
        .background(.clear)
        .glassEffect(effectiveGlass, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: -4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .offset(
            x: glassSettings.offsetX + liveDragOffset.width,
            y: glassSettings.offsetY + liveDragOffset.height
        )
    }
}

// MARK: - Glass Popover (matching app settings style)

struct ToDoGlassPopover: View {
    @ObservedObject var glassSettings: ToDoGlassSettings

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
                glassSettings.offsetX = 0
                glassSettings.offsetY = 0
                glassSettings.extraHeight = 0
                glassSettings.extraWidth = 0
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
