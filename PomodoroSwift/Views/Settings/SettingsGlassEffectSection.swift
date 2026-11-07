import SwiftUI

struct SettingsGlassEffectSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("液态玻璃")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                Text("玻璃样式")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.glassVariant) {
                    ForEach(Settings.glassVariants, id: \.1) { name, value in
                        Text(name).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("着色强度")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", settings.glassTintOpacity))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(value: $settings.glassTintOpacity, in: 0.0...1.0, step: 0.01)
            }

            Toggle("交互光效", isOn: $settings.glassInteractive)
                .foregroundStyle(.secondary)
        }
    }
}
