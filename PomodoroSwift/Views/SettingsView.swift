//
//  SettingsView.swift
//  PomodoroSwift
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @StateObject private var aiController = AIClassificationController()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsAppearanceSection(settings: settings)
            SettingsTimerSection(settings: settings)
            SettingsWhiteNoiseSection(settings: settings)
            SettingsToDoPanelsSection(settings: settings)
            SettingsAIClassifierSection(settings: settings, controller: aiController)
            SettingsGlassEffectSection(settings: settings)
            SettingsBackgroundSection(settings: settings)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: Settings())
    }
}
