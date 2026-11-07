import SwiftUI
import UniformTypeIdentifiers

struct SettingsBackgroundSection: View {
    @ObservedObject var settings: Settings
    @Binding var preview: BackgroundTimePreview
    @Binding var previewMinute: Double
    let hasSkyLocation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("背景")
                .font(.headline)
                .foregroundStyle(.primary)

            Picker("背景主题", selection: $settings.backgroundTheme) {
                ForEach(BackgroundTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .accessibilityIdentifier("backgroundThemePicker")

            if settings.backgroundTheme.isDynamic {
                Picker("时段预览", selection: $preview) {
                    ForEach(BackgroundTimePreview.allCases) { time in
                        Text(time.title).tag(time)
                    }
                }
                .accessibilityIdentifier("backgroundTimePicker")

                if preview == .custom {
                    BackgroundPreviewTimeSlider(minute: $previewMinute)
                }

                Text(preview == .live
                     ? (hasSkyLocation ? "场景和面板配色跟随当地日照。" : "场景和面板配色按系统时间切换。")
                     : "正在预览示范日。选择「实时」可恢复自动变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                GlassButton("选择图片…", settings: settings, action: selectBackgroundImage)

                if settings.backgroundImageData != nil {
                    GlassButton("移除图片", settings: settings, isDestructive: true) {
                        settings.backgroundImageData = nil
                    }
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

struct BackgroundPreviewTimeSlider: View {
    @Binding var minute: Double
    @State private var draftMinute: Double?
    @State private var isTracking = false

    var body: some View {
        let value = Int(draftMinute ?? minute)
        let time = String(format: "%02d:%02d", value / 60, value % 60)
        let pendingMinute = isTracking ? nil : draftMinute

        VStack(alignment: .leading, spacing: 8) {
            Slider(value: Binding(get: { draftMinute ?? minute }, set: { draftMinute = $0 }),
                   in: 0...1439, step: 1) {
                Text("预览时刻")
            } onEditingChanged: { isTracking = $0 }
            .accessibilityValue(time)
            .accessibilityIdentifier("backgroundTimeSlider")

            Text(time).monospacedDigit()
                .font(.caption)
                .accessibilityHidden(true)
        }
        .task(id: pendingMinute) {
            guard let pendingMinute else { return }
            if pendingMinute != minute {
                // Keep the window's scene unchanged during a drag and combine repeated key presses.
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard !Task.isCancelled, !isTracking, draftMinute == pendingMinute else { return }
                minute = pendingMinute
            }
            draftMinute = nil
        }
    }
}
