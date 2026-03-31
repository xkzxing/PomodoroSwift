import SwiftUI

struct SettingsAIClassifierSection: View {
    @ObservedObject var settings: Settings
    @ObservedObject var controller: AIClassificationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Task Classifier")
                .font(.headline)
                .foregroundStyle(.primary)

            SecureField("DashScope API Key", text: $settings.aiApiKey)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Input Tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.2))

                    TextEditor(text: $controller.inputText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .padding(4)
                }
                .frame(minHeight: 90, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }

            HStack(spacing: 10) {
                Button(action: startClassification) {
                    HStack(spacing: 8) {
                        if controller.isClassifying {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(controller.isClassifying ? "Classifying..." : "Classify Into Existing Panels")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isClassifyButtonDisabled)

                if controller.isClassifying {
                    Button("Cancel", action: controller.cancelClassification)
                        .buttonStyle(.bordered)
                } else if controller.statusIsError,
                          !controller.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !panelContexts.isEmpty {
                    Button("Retry", action: retryClassification)
                        .buttonStyle(.bordered)
                }

                Text("Only writes into existing panels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(controller.statusIsError ? .red : .green)
            }
        }
    }

    private var isClassifyButtonDisabled: Bool {
        controller.isClassifying ||
        controller.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        panelContexts.isEmpty
    }

    private var panelContexts: [AIPanelContext] {
        settings.todoPanels.map {
            AIPanelContext(
                id: $0.id,
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : $0.title
            )
        }
    }

    private func startClassification() {
        controller.startClassification(
            apiKey: settings.aiApiKey,
            panels: panelContexts,
            persistAssignments: { @MainActor assignments in
                ToDoStore.appendAssignments(assignments)
            }
        )
    }

    private func retryClassification() {
        controller.retryClassification(
            apiKey: settings.aiApiKey,
            panels: panelContexts,
            persistAssignments: { @MainActor assignments in
                ToDoStore.appendAssignments(assignments)
            }
        )
    }
}
