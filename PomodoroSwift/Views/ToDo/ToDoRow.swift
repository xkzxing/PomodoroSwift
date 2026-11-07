import SwiftUI

struct ToDoRow: View {
    let item: ToDoItem
    let onTogglePin: () -> Void
    let onToggleToday: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool
    @Environment(\.todoTextColor) private var textColor

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isPinned ? Color.blue : textColor.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "取消置顶" : "置顶")
            .accessibilityLabel(item.isPinned ? "取消置顶" : "置顶")

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: item.isPinned ? .semibold : .regular))
                    .foregroundStyle(textColor)
                    .focused($editFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitEdit() }
                    .onChange(of: editFocused) { _, focused in
                        if !focused {
                            commitEdit()
                        }
                    }
            } else {
                Text(item.text)
                    .font(.system(size: 13, weight: item.isPinned ? .semibold : .regular))
                    .foregroundStyle(textColor.opacity(0.9))
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

            ToDoTodayButton(isInToday: item.isInToday, textColor: textColor, action: onToggleToday)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity((item.isPinned ? 0.04 : 0) + (isHovered ? 0.06 : 0)))
        .contentShape(Rectangle())
        .contextMenu {
            Button(item.isPinned ? "取消置顶" : "置顶", action: onTogglePin)
            Button(item.isInToday ? "移出今日" : "固定到今日", action: onToggleToday)
            Button("删除", role: .destructive, action: onDelete)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func commitEdit() {
        isEditing = false
        editFocused = false
        onEdit(editText)
    }
}

struct ToDoTodayButton: View {
    let isInToday: Bool
    let textColor: Color
    let action: () -> Void

    private var label: String { isInToday ? "移出今日" : "固定到今日" }

    var body: some View {
        Button(action: action) {
            Image(systemName: isInToday ? "sun.max.fill" : "sun.max")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textColor.opacity(isInToday ? 1 : 0.65))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
