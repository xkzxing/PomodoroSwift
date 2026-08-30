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
                    Text("玻璃样式")
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
                    Text("着色")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $glassSettings.tintColor, supportsOpacity: false)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("着色不透明度")
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
                    Text("文字颜色")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $glassSettings.fontDark) {
                        Text("浅色").tag(false)
                        Text("深色").tag(true)
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
