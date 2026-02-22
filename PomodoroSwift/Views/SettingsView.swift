//
//  SettingsView.swift
//  PomodoroSwift
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var selectedCampfirePreset: CampfirePreset = .cracklingCampfire
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Appearance Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                FontPickerButton(selectedFont: $settings.selectedNSFont)
                
                // App-wide Light/Dark Mode
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
            
            // Timer Settings Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Timer Settings")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Short Break Time
                HStack {
                    Text("Short Break")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.breakTime) {
                        ForEach([3, 5, 10, 15], id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                
                // Long Break Time
                HStack {
                    Text("Long Break")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.longBreakTime) {
                        ForEach([10, 15, 20, 30], id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
            
            // White Noise Section
            VStack(alignment: .leading, spacing: 12) {
                Text("White Noise")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Toggle("Enable White Noise", isOn: $settings.whiteNoiseEnabled)
                    .toggleStyle(.switch)
                    .foregroundStyle(.secondary)
                
                if settings.whiteNoiseEnabled {
                    // Noise Type Picker
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
                    
                    // Volume Slider
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
                    
                    // Campfire tuning (only when campfire is selected)
                    if settings.whiteNoiseType == "campfire" {
                        // Preset picker
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
                        
                        // Fine-tuning sliders (collapsible)
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
            
            // Liquid Glass Effect Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Liquid Glass Effect")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Glass Variant Picker
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
                
                // Color Picker
                HStack {
                    Text("Tint Color")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $settings.glassTintColor, supportsOpacity: false)
                        .labelsHidden()
                }
                
                // Tint Opacity Slider
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
                
                // Interactive Effect Toggle
                Toggle("Interactive Shimmer", isOn: $settings.glassInteractive)
                    .foregroundStyle(.secondary)
            }
            
            // Background Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Background")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                GlassButton("Select Image...", settings: settings) {
                    selectBackgroundImage()
                }
                
                if settings.backgroundImageData != nil {
                    GlassButton("Remove Background", settings: settings, isDestructive: true) {
                        settings.backgroundImageData = nil
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let imageData = try? Data(contentsOf: url) {
                    settings.backgroundImageData = imageData
                }
            }
        }
    }
    
    // Helper for campfire tuning sliders (0-1 range, shown as %)
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
    
    // Helper for frequency sliders (custom Hz range)
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

#Preview {
    NavigationStack {
        SettingsView(settings: Settings())
    }
}
