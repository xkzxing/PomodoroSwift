import SwiftUI

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
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isDone ? .green.opacity(0.85) : textColor.opacity(0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
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
