import SwiftUI

extension ScheduleColor {
    var tint: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}

struct ScheduleTimePicker: View {
    let title: String
    @Binding var minute: Int
    var allowsEndOfDay = false
    var minuteStep = 15

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer(minLength: 8)
            Picker(title + "小时", selection: Binding(
                get: { minute / 60 },
                set: { minute = $0 == 24 ? 1440 : $0 * 60 + minute % 60 }
            )) {
                ForEach(0..<(allowsEndOfDay ? 25 : 24), id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 65)
            Text(":")
            Picker(title + "分钟", selection: Binding(
                get: { minute % 60 },
                set: { minute = minute / 60 * 60 + $0 }
            )) {
                ForEach(Array(stride(from: 0, to: 60, by: minuteStep)), id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 65)
            .disabled(minute == 1440)
        }
    }
}

struct WeeklyScheduleDisplayControls: View {
    @ObservedObject var store: WeeklyScheduleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("第一列", selection: $store.preferences.firstDay) {
                ForEach(ScheduleFirstDay.allCases) { day in Text(day.title).tag(day) }
            }
            .accessibilityIdentifier("weeklyFirstDay")
            Toggle("包括周末", isOn: $store.preferences.includesWeekend)
            ScheduleTimePicker(title: "开始时间", minute: Binding(
                get: { store.preferences.startMinute },
                set: {
                    var value = store.preferences
                    value.startMinute = $0
                    value.endMinute = max(value.endMinute, $0 + 15)
                    store.preferences = value
                }
            ))
            ScheduleTimePicker(title: "结束时间", minute: Binding(
                get: { store.preferences.endMinute },
                set: {
                    var value = store.preferences
                    value.endMinute = $0
                    value.startMinute = min(value.startMinute, max(0, $0 - 15))
                    store.preferences = value
                }
            ), allowsEndOfDay: true)
            Picker("日程最小字号", selection: $store.preferences.minimumFontSize) {
                ForEach(7...11, id: \.self) { size in Text("\(size) 点").tag(Double(size)) }
            }
            .accessibilityIdentifier("weeklyMinimumFontSize")
            Text("日程文字优先换行，空间不足时从 11 点逐步缩小到最小字号。仍放不下时省略尾部，可悬停查看完整内容。")
                .font(.caption).foregroundStyle(.secondary)
            Text("固定日程每周重复，不绑定日期。选择今日时显示从今天开始的七天；不显示周末时，跳过周六和周日。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsWeeklyScheduleSection: View {
    @ObservedObject var store: WeeklyScheduleStore
    @ObservedObject var settings: Settings
    @State private var showAI = false
    @State private var showCalendars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("周日程").font(.headline)
            Toggle("显示周日程面板", isOn: $store.preferences.isVisible)
            WeeklyScheduleDisplayControls(store: store)
            Button("AI 添加日程", systemImage: "sparkles") { showAI = true }
                .accessibilityIdentifier("weeklyAISettingsOpen")
            Button("日历来源", systemImage: "calendar.badge.clock") { showCalendars = true }
                .popover(isPresented: $showCalendars, arrowEdge: .top) {
                    ScheduleCalendarSettings(calendarStore: store.calendarStore)
                        .padding(18).frame(width: 350)
                }
            Button("重置面板位置与尺寸") { store.resetLayout() }
            Text("拖动面板标题移动位置，拖动右下角调整大小。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showAI) { AIWeeklyScheduleSheet(store: store, settings: settings) }
    }
}

struct WeeklyScheduleEditor: View {
    @ObservedObject var store: WeeklyScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State var event: WeeklyScheduleEvent
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private var isExisting: Bool { store.events.contains { $0.id == event.id } }
    private var overlaps: Bool {
        store.events.contains {
            $0.id != event.id && !$0.weekdays.isDisjoint(with: event.weekdays)
                && $0.startMinute < event.endMinute && $0.endMinute > event.startMinute
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isExisting ? "编辑每周日程" : "添加每周日程")
                .font(.title2.weight(.semibold))
            TextField("日程名称，例如：上课、午餐、运动", text: $event.title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .accessibilityIdentifier("weeklyEventTitle")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("每周重复").font(.headline)
                    Spacer()
                    Button("工作日") { event.weekdays = Set(ScheduleWeekday.allCases.prefix(5)) }
                    Button("每天") { event.weekdays = Set(ScheduleWeekday.allCases) }
                }
                HStack(spacing: 6) {
                    ForEach(ScheduleWeekday.allCases) { weekday in
                        Button {
                            if event.weekdays.contains(weekday) { event.weekdays.remove(weekday) }
                            else { event.weekdays.insert(weekday) }
                        } label: {
                            Text(weekday.title)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(event.weekdays.contains(weekday) ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(
                                    event.weekdays.contains(weekday) ? Color.accentColor : .clear
                                ))
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(event.weekdays.contains(weekday) ? "已选择" : "未选择")
                    }
                }
            }

            ScheduleTimePicker(title: "开始时间", minute: $event.startMinute, minuteStep: 1)
            ScheduleTimePicker(title: "结束时间", minute: $event.endMinute, allowsEndOfDay: true, minuteStep: 1)
            Picker("日程颜色", selection: $event.color) {
                ForEach(ScheduleColor.allCases) { color in
                    Label(color.title, systemImage: "circle.fill").tint(color.tint).tag(color)
                }
            }

            if let message = event.validationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if overlaps {
                Label("与已有固定日程重叠，会并排显示。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let message = store.storageError {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Text("这是每周重复的固定安排。保存或删除会应用于所有周。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                if isExisting {
                    Button("删除日程", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if store.save(event) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(event.validationMessage != nil || store.storageError != nil)
                .accessibilityIdentifier("saveWeeklyEvent")
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear { titleFocused = true }
        .confirmationDialog("删除这个每周日程？所有周的重复安排都会删除。", isPresented: $confirmDelete) {
            Button("删除每周日程", role: .destructive) {
                store.delete(event)
                dismiss()
            }
        }
    }
}

struct WeeklyScheduleLibrary: View {
    @ObservedObject var store: WeeklyScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingEvent: WeeklyScheduleEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("每周日程").font(.title2.weight(.semibold))
                Spacer()
                Button("添加日程", systemImage: "plus") { editingEvent = WeeklyScheduleEvent() }
            }
            Text("包括显示范围之外的日程。点击任意日程进行编辑。")
                .font(.caption).foregroundStyle(.secondary)
            if store.events.isEmpty {
                ContentUnavailableView("还没有固定日程", systemImage: "calendar.badge.plus",
                                       description: Text("添加一次，即可在每一周显示。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.events.sorted { $0.startMinute < $1.startMinute }) { event in
                            Button { editingEvent = event } label: {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 3).fill(event.color.tint).frame(width: 5)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(event.title).font(.headline)
                                        Text(event.weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: "、"))
                                        Text("\(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))")
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                    Spacer()
                                    Image(systemName: "pencil").foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 470, height: 440)
        .sheet(item: $editingEvent) { WeeklyScheduleEditor(store: store, event: $0) }
    }
}
