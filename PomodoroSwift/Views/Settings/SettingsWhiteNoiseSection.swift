import SwiftUI

struct SettingsWhiteNoiseSection: View {
    @ObservedObject var settings: Settings
    @State private var selectedCampfirePreset: CampfirePreset = .cracklingCampfire

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("White Noise")
                .font(.headline)
                .foregroundStyle(.primary)

            Toggle("Enable White Noise", isOn: $settings.whiteNoiseEnabled)
                .toggleStyle(.switch)
                .foregroundStyle(.secondary)

            if settings.whiteNoiseEnabled {
                Toggle("Only During Timer", isOn: $settings.whiteNoiseOnlyWhenTimerRunning)
                    .toggleStyle(.switch)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Sound Type")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.whiteNoiseType) {
                        ForEach(NoiseType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Volume")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", settings.whiteNoiseVolume * 100))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $settings.whiteNoiseVolume, in: 0.0...1.0, step: 0.01)
                }

                if settings.whiteNoiseType == "campfire" {
                    HStack {
                        Text("Preset")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $selectedCampfirePreset) {
                            ForEach(CampfirePreset.allCases, id: \.rawValue) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: selectedCampfirePreset) { _, newPreset in
                            settings.applyCampfirePreset(newPreset)
                        }
                    }

                    DisclosureGroup("Fine Tuning") {
                        VStack(alignment: .leading, spacing: 8) {
                            campfireSlider(label: "Rumble", value: $settings.campfireRumble)
                            campfireSlider(label: "Texture", value: $settings.campfireTexture)
                            campfireSlider(label: "Pop Level", value: $settings.campfireWoodyLevel)
                            campfireSlider(label: "Snap Level", value: $settings.campfireSnapLevel)
                            campfireSlider(label: "Rumble Smooth", value: $settings.campfireRumbleSmooth)
                            campfireSlider(label: "Texture Smooth", value: $settings.campfireTextureSmooth)
                            campfireSlider(label: "Pop Density", value: $settings.campfireWoodyDensity)
                            campfireSlider(label: "Snap Density", value: $settings.campfireSnapDensity)
                            campfireSlider(label: "Resonance", value: $settings.campfireResonance)
                            campfireSlider(label: "Burst Prob", value: $settings.campfireBurstProb)
                            campfireFreqSlider(label: "Low Freq", value: $settings.campfireFreqLo, range: 50...800)
                            campfireFreqSlider(label: "Mid Freq", value: $settings.campfireFreqMid, range: 200...3000)
                            campfireFreqSlider(label: "High Freq", value: $settings.campfireFreqHi, range: 500...6000)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
        }
    }

    private func campfireSlider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Slider(value: value, in: 0.0...1.0, step: 0.01)
        }
    }

    private func campfireFreqSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: "%.0f Hz", value.wrappedValue))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Slider(value: value, in: range, step: 10)
        }
    }
}
