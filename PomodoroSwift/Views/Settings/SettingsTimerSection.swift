import SwiftUI

struct SettingsTimerSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer Settings")
                .font(.headline)
                .foregroundStyle(.primary)

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
    }
}
