import SwiftUI

struct SettingsAppearanceSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.headline)
                .foregroundStyle(.primary)

            FontPickerButton(selectedFont: $settings.selectedNSFont)

            HStack {
                Text("Appearance")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.sidebarDarkMode) {
                    Text("Dark").tag(true)
                    Text("Light").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
    }
}
