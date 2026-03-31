import SwiftUI

struct SettingsGlassEffectSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Liquid Glass Effect")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                Text("Glass Variant")
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

            HStack {
                Text("Tint Color")
                    .foregroundStyle(.secondary)
                Spacer()
                ColorPicker("", selection: $settings.glassTintColor, supportsOpacity: false)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tint Opacity")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", settings.glassTintOpacity))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(value: $settings.glassTintOpacity, in: 0.0...1.0, step: 0.01)
            }

            Toggle("Interactive Shimmer", isOn: $settings.glassInteractive)
                .foregroundStyle(.secondary)
        }
    }
}
