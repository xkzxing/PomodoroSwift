import SwiftUI

struct SoundSelectionView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    private func binding<Value>(_ path: WritableKeyPath<FocusSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: path] }, set: {
            var settings = store.settings
            settings[keyPath: path] = $0
            store.updateSettings(settings)
        })
    }

    var body: some View {
        if embedded { content }
        else {
            NavigationStack {
                content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            }.tint(AppPalette.accent)
        }
    }

    private var content: some View {
        Form {
            Section {
                Toggle("启用环境声", isOn: Binding(get: { store.settings.sound != .none }, set: { enabled in
                    var settings = store.settings
                    if enabled { settings.sound = settings.soundBeforeMute == .none ? .white : settings.soundBeforeMute }
                    else { settings.soundBeforeMute = settings.sound; settings.sound = .none }
                    store.updateSettings(settings)
                }))
                if store.settings.sound != .none {
                    Toggle("仅在计时运行时播放", isOn: binding(\.soundOnlyDuringTimer))
                }
            } footer: {
                Text("关闭“仅在计时运行时播放”后，环境声可独立播放，暂停或结束计时不会停止声音。")
            }
            if store.settings.sound != .none {
                Section("声音类型") {
                    Picker("声音类型", selection: binding(\.sound)) {
                        ForEach(AmbientSound.allCases.filter { $0 != .none }) { sound in
                            Text(sound.title).tag(sound)
                        }
                    }.pickerStyle(.inline).labelsHidden()
                }
                Section("音量") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: binding(\.volume), in: 0...1).accessibilityLabel("环境声音量")
                        Text("\(Int(store.settings.volume * 100))%").font(.caption.monospacedDigit()).frame(width: 42)
                    }
                }
                if store.settings.sound == .campfire {
                    Section("篝火预设") {
                        Picker("预设", selection: Binding(get: { store.settings.campfirePreset }, set: { preset in
                            var settings = store.settings
                            settings.campfirePreset = preset
                            settings.campfire = preset.parameters
                            store.updateSettings(settings)
                        })) {
                            ForEach(CampfirePreset.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Section {
                        DisclosureGroup("篝火微调") {
                            parameter("低鸣", \.rumble)
                            parameter("纹理", \.texture)
                            parameter("木柴爆裂音量", \.woodyLevel)
                            parameter("清脆爆裂音量", \.snapLevel)
                            parameter("低鸣平滑度", \.rumbleSmooth)
                            parameter("纹理平滑度", \.textureSmooth)
                            parameter("木柴爆裂密度", \.woodyDensity)
                            parameter("清脆爆裂密度", \.snapDensity)
                            parameter("共振", \.resonance)
                            parameter("连续爆裂概率", \.burstProb)
                            parameter("低频", \.freqLo, range: 50...800)
                            parameter("中频", \.freqMid, range: 200...3000)
                            parameter("高频", \.freqHi, range: 500...6000)
                        }
                    } footer: { Text("沿用电脑版的五种预设和十三项参数。调节后会在后台生成声音，期间保持原声音播放。") }
                }
            }
        }
        .scrollContentBackground(.hidden).background(AppPalette.background)
        .navigationTitle("环境声").navigationBarTitleDisplayMode(.inline)
    }

    private func parameter(_ title: String, _ path: WritableKeyPath<CampfireParameters, Double>,
                           range: ClosedRange<Double> = 0...1) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                let value = store.settings.campfire[keyPath: path]
                Text(range.upperBound > 1 ? "\(Int(value)) 赫兹" : "\(Int(value * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { store.settings.campfire[keyPath: path] }, set: {
                var settings = store.settings
                settings.campfire[keyPath: path] = $0
                store.updateSettings(settings)
            }), in: range, step: range.upperBound > 1 ? 10 : 0.01).accessibilityLabel(title)
        }.padding(.vertical, 5)
    }
}
