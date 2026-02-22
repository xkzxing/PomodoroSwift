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

// MARK: - To-Do Panel View

struct ToDoView: View {
    @StateObject private var store = ToDoStore()
    @State private var newText: String = ""
    @State private var isExpanded: Bool = true
    @FocusState private var inputFocused: Bool

    // Injected glass style from parent
    var glassEffect: Glass
    // Max height for the task list scroll area (computed by parent)
    var listMaxHeight: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            // Header / toggle bar
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Text("To-Do")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    // Remaining count badge
                    let remaining = store.items.filter { !$0.isDone }.count
                    if remaining > 0 {
                        Text("\(remaining)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.25))
                            )
                    }

                    Spacer()

                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .background(.white.opacity(0.15))

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
                    .frame(maxHeight: max(listMaxHeight, 44))
                }

                // Input field
                Divider()
                    .background(.white.opacity(0.15))

                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    TextField("Add a task…", text: $newText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($inputFocused)
                        .onSubmit {
                            store.add(newText)
                            newText = ""
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(.clear)
        .glassEffect(glassEffect, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: -4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isDone ? .green.opacity(0.85) : .white.opacity(0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Text or inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($editFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitEdit() }
                    .onChange(of: editFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDone ? .white.opacity(0.35) : .white.opacity(0.9))
                    .strikethrough(item.isDone, color: .white.opacity(0.35))
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
                        .foregroundStyle(.white.opacity(0.5))
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
