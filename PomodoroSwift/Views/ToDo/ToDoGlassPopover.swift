import SwiftUI

struct ToDoGlassPopover: View {
    @ObservedObject var glassSettings: ToDoGlassSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("自定义玻璃效果", isOn: $glassSettings.useCustom)
                .font(.system(size: 13, weight: .medium))

            if glassSettings.useCustom {
                Divider()

                HStack {
                    Text("Variant")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $glassSettings.variant) {
                        ForEach(ToDoGlassSettings.variants, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                HStack {
                    Text("Tint Color")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $glassSettings.tintColor, supportsOpacity: false)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Tint Opacity")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f", glassSettings.tintOpacity))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $glassSettings.tintOpacity, in: 0.0...1.0, step: 0.01)
                }

                HStack {
                    Text("Font Color")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $glassSettings.fontDark) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

        }
        .padding(14)
        .frame(width: 220)
    }
}
