import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var requestingNotifications = false

    private func binding<Value>(_ keyPath: WritableKeyPath<FocusSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in
            var settings = store.settings
            settings[keyPath: keyPath] = value
            store.updateSettings(settings)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "timer").font(.title).foregroundStyle(AppPalette.ink)
                            .frame(width: 60, height: 60).background(AppPalette.soft, in: RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PomodoroSwift").font(.headline).foregroundStyle(AppPalette.ink)
                            Text("电脑版风格 · 手机布局").font(.subheadline).foregroundStyle(AppPalette.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section {
                    Stepper(value: binding(\.focusMinutes), in: 5...120, step: 5) {
                        settingValue("专注", value: "\(store.settings.focusMinutes) 分钟")
                    }
                    Stepper(value: binding(\.shortBreakMinutes), in: 1...30) {
                        settingValue("短休息", value: "\(store.settings.shortBreakMinutes) 分钟")
                    }
                    Stepper(value: binding(\.longBreakMinutes), in: 5...60, step: 5) {
                        settingValue("长休息", value: "\(store.settings.longBreakMinutes) 分钟")
                    }
                } header: { Text("专注节奏") } footer: { Text("运行中的计时不受时长修改影响；暂停时修改当前模式的时长会重新准备这一段计时。") }
                Section("电脑待办") {
                    NavigationLink("单向读取电脑结果") { MobileMirrorSettingsView() }
                }
                Section("外观") {
                    Picker("表盘", selection: Binding(get: { store.settings.dial.resolved }, set: { value in
                        var settings = store.settings
                        settings.dial = value
                        store.updateSettings(settings)
                    })) {
                        ForEach(DialStyle.supported) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("dial-style-picker")
                    if store.settings.dial.resolved == .digital {
                        NavigationLink("数字字体与字号") { DigitalFontSettingsView() }
                    }
                    NavigationLink("背景与玻璃") { CanvasAppearanceView() }
                }
                Section("环境声") {
                    NavigationLink { SoundSelectionView(embedded: true) } label: {
                        settingValue("环境声", value: store.settings.sound.title)
                    }
                }
                Section {
                    Toggle("到时提醒", isOn: Binding(get: { store.settings.notificationsEnabled }, set: { enabled in
                        if enabled {
                            requestingNotifications = true
                            Task { await store.enableNotifications(); requestingNotifications = false }
                        } else {
                            var settings = store.settings
                            settings.notificationsEnabled = false
                            store.updateSettings(settings)
                        }
                    })).disabled(requestingNotifications)
                    if requestingNotifications { ProgressView("正在请求通知权限") }
                    Link("在系统设置中管理权限", destination: URL(string: UIApplication.openSettingsURLString)!)
                } header: { Text("通知") } footer: { Text("锁屏后仍按实际时间计时。允许通知后，计时结束时可收到系统提醒。") }
                Section {
                    LabeledContent("版本", value: "1.5.0")
                } header: { Text("关于") } footer: {
                    Text("待办只读显示电脑结果；计时和外观设置独立保存在本机。")
                }
            }
            .scrollContentBackground(.hidden).background(AppPalette.background)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(AppPalette.accent)
    }

    private func settingValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            Text(value).font(.caption).foregroundStyle(AppPalette.secondary)
        }.padding(.vertical, 3)
    }
}
