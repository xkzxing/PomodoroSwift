import SwiftUI

struct SettingsToDoPanelsSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To-Do Panels")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                ForEach($settings.todoPanels) { $panel in
                    HStack {
                        TextField("Panel Title", text: $panel.title)
                            .textFieldStyle(.roundedBorder)

                        Button(action: {
                            NotificationCenter.default.post(
                                name: .resetToDoPanel,
                                object: nil,
                                userInfo: ["panelId": panel.id]
                            )
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Reset position and size")

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
}
