import SwiftUI

extension ScheduleCalendarColor {
    var tint: Color { Color(red: red, green: green, blue: blue) }
}

struct ScheduleCalendarSettings: View {
    @ObservedObject var calendarStore: ScheduleCalendarStore

    private var accounts: [(id: String, title: String, calendars: [ScheduleCalendarSource])] {
        let groups = Dictionary(grouping: calendarStore.calendars, by: \.accountID)
        return groups.map { (id: $0.key, title: $0.value.first?.accountTitle ?? "其他", calendars: $0.value) }
            .sorted { ($0.title, $0.id) < ($1.title, $1.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("日历来源").font(.headline)
                Spacer()
                if calendarStore.isLoading { ProgressView().controlSize(.small) }
                Button("刷新", systemImage: "arrow.clockwise") { calendarStore.refresh() }
                    .labelStyle(.iconOnly).help("重新读取系统日历")
            }
            Text("选择系统“日历”侧边栏中的日历，可多选。只显示当前周期内有明确起止时间的事件，不包含全天事件。")
                .font(.caption).foregroundStyle(.secondary)
            switch calendarStore.authorization {
            case .notDetermined:
                accessButton
            case .denied, .restricted:
                Text("尚未获得日历读取权限。请在系统设置 → 隐私与安全性 → 日历中允许访问，然后返回此处刷新。")
                    .font(.callout).foregroundStyle(.secondary)
                accessButton
            case .authorized:
                Toggle("显示所选日历的日程", isOn: $calendarStore.isEnabled)
                    .accessibilityIdentifier("weeklyCalendarEnabled")
                if accounts.isEmpty {
                    Text("未找到日历。请先在系统“日历”中添加账户并完成同步。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(accounts, id: \.id) { account in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(account.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ForEach(account.calendars) { calendar in
                                        Toggle(isOn: Binding(
                                            get: { calendarStore.selectedIDs.contains(calendar.id) },
                                            set: { calendarStore.select(calendar.id, enabled: $0) }
                                        )) {
                                            HStack(spacing: 7) {
                                                Circle().fill(calendar.color.tint).frame(width: 9, height: 9)
                                                Text(calendar.title).lineLimit(2)
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 270)
                    if calendarStore.selectedIDs.isEmpty {
                        Text("请勾选要显示的日历，不会默认读取全部日历。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if calendarStore.missingSelectionCount > 0 {
                        Text("有 \(calendarStore.missingSelectionCount) 个已选日历暂不可用；选择已保留，恢复同步后会继续显示。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = calendarStore.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            Text("仅在本地读取，不修改系统日历，不发送给 AI。读取事件需要系统的完整日历访问权限，但本应用不会写入日历。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task { await calendarStore.reload() }
    }

    private var accessButton: some View {
        Button(calendarStore.isRequestingAccess ? "正在请求权限…" : "允许读取系统日历") {
            Task { await calendarStore.requestAccess() }
        }
        .disabled(calendarStore.isRequestingAccess || calendarStore.authorization == .restricted)
        .accessibilityIdentifier("weeklyCalendarRequestAccess")
    }
}

struct ScheduleCalendarEventDetails: View {
    let event: ScheduleCalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(event.title, systemImage: "calendar").font(.headline)
            Text(event.calendarTitle).font(.subheadline).foregroundStyle(.secondary)
            Text(event.start.formatted(date: .abbreviated, time: .shortened))
            Text("至 \(event.end.formatted(date: .abbreviated, time: .shortened))")
            Text("来自系统日历，仅供查看。如需修改，请在“日历”中编辑。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .padding(18).frame(width: 290, alignment: .leading)
    }
}
