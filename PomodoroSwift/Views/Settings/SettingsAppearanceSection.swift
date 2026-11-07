import SwiftUI

struct SettingsAppearanceSection: View {
    @ObservedObject var settings: Settings
    @AppStorage("timerPanelColors") private var timerColors = ScenePanelColors.chromeDefault()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                Text("Clock Style")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Clock Style", selection: $settings.timerDisplayStyle) {
                    ForEach(TimerDisplayStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .accessibilityIdentifier("timerDisplayStyle")
            }

            if settings.timerDisplayStyle == .digital {
                FontPickerButton(selectedFont: $settings.selectedNSFont)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Clock Size")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(settings.swissClockSize)) pt")
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.swissClockSize, in: 160...520, step: 10)
                        .accessibilityLabel("Clock Size")

                    if settings.timerDisplayStyle == .gemstone {
                        Text("单针在整段倒计时内转一圈，每个花瓣刻度代表总时长的十二分之一。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Text("应用外观")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.sidebarDarkMode) {
                    Text("暗色").tag(true)
                    Text("亮色").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            DisclosureGroup("计时面板配色") {
                ScenePanelColorControls(colors: $timerColors)
                    .padding(.top, 8)
            }
            DisclosureGroup("设置面板配色") {
                ScenePanelColorControls(colors: $settings.settingsPanelColors)
                    .padding(.top, 8)
            }
        }
    }
}
