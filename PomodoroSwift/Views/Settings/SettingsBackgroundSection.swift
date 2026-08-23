import SwiftUI
import UniformTypeIdentifiers

struct SettingsBackgroundSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background")
                .font(.headline)
                .foregroundStyle(.primary)

            GlassButton("Select Image...", settings: settings) {
                selectBackgroundImage()
            }

            if settings.backgroundImageData != nil {
                GlassButton("Remove Background", settings: settings, isDestructive: true) {
                    settings.backgroundImageData = nil
                }
            }
        }
    }

    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            if response == .OK,
               let url = panel.url,
               let imageData = try? Data(contentsOf: url) {
                settings.backgroundImageData = imageData
            }
        }
    }
}
