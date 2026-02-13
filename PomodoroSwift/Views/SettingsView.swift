//
//  SettingsView.swift
//  PomodoroSwift
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Appearance Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                FontPickerButton(selectedFont: $settings.selectedNSFont)
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
}

#Preview {
    NavigationStack {
        SettingsView(settings: Settings())
    }
}
