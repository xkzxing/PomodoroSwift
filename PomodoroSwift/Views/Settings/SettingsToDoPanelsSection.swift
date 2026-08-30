import SwiftUI

struct SettingsToDoPanelsSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To-Do Panels")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Use the arrows to set the top-to-bottom panel order.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach($settings.todoPanels) { $panel in
                    HStack {
                        TextField("Panel Title", text: $panel.title)
                            .textFieldStyle(.roundedBorder)

                        Button(action: {
                            movePanel(id: panel.id, by: -1)
                        }) {
                            Image(systemName: "chevron.up")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Move panel up")
                        .disabled(settings.todoPanels.first?.id == panel.id)

                        Button(action: {
                            movePanel(id: panel.id, by: 1)
                        }) {
                            Image(systemName: "chevron.down")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Move panel down")
                        .disabled(settings.todoPanels.last?.id == panel.id)

                        Button(action: {
                            if let index = settings.todoPanels.firstIndex(where: { $0.id == panel.id }) {
                                settings.todoPanels.remove(at: index)
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.todoPanels.count <= 1)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                Button(action: {
                    settings.todoPanels.append(ToDoPanel(title: "New To-Do"))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Panel")
                    }
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
        }
    }

    private func movePanel(id: UUID, by offset: Int) {
        guard let currentIndex = settings.todoPanels.firstIndex(where: { $0.id == id }) else {
            return
        }

        let destinationIndex = currentIndex + offset
        guard settings.todoPanels.indices.contains(destinationIndex) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            settings.todoPanels.swapAt(currentIndex, destinationIndex)
        }
    }
}
