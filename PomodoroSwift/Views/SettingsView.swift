//
//  SettingsView.swift
//  PomodoroSwift
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var weeklySchedule: WeeklyScheduleStore
    @Binding var backgroundPreview: BackgroundTimePreview
    @Binding var backgroundPreviewMinute: Double
    let hasSkyLocation: Bool
    @StateObject private var aiController = AIClassificationController()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsAppearanceSection(settings: settings)
            SettingsBackgroundSection(settings: settings, preview: $backgroundPreview,
                                      previewMinute: $backgroundPreviewMinute, hasSkyLocation: hasSkyLocation)
            SettingsTimerSection(settings: settings)
            SettingsWhiteNoiseSection(settings: settings)
            SettingsToDoPanelsSection(settings: settings)
            SettingsMobileMirrorSection()
            SettingsWeeklyScheduleSection(store: weeklySchedule, settings: settings)
            SettingsAIClassifierSection(settings: settings, controller: aiController)
            SettingsGlassEffectSection(settings: settings)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: Settings(), weeklySchedule: WeeklyScheduleStore(),
                     backgroundPreview: .constant(.live),
                     backgroundPreviewMinute: .constant(Double(BackgroundTimePreview.defaultCustomMinute)),
                     hasSkyLocation: false)
    }
}
