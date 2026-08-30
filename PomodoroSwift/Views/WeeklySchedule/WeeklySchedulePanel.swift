import SwiftUI

struct WeeklySchedulePanel: View {
    @ObservedObject var store: WeeklyScheduleStore
    @EnvironmentObject private var settings: Settings
    @StateObject private var glass = ToDoGlassSettings(panelId: WeeklyScheduleStore.panelID, migrateLegacy: false)
    let containerSize: CGSize
    let glassEffect: Glass

    @State private var weekOffset = 0
    @State private var selectedDay = ScheduleWeekday.from(Date())
    @State private var editingEvent: WeeklyScheduleEvent?
    @State private var showLibrary = false
    @State private var showDisplaySettings = false
    @State private var showGlassSettings = false
    @State private var showAI = false
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeOffset: CGSize = .zero

    private var textColor: Color {
        (glass.useCustom ? glass.fontDark : !settings.sidebarDarkMode) ? .black : .white
    }
    private var basePanelWidth: CGFloat {
        let desired = glass.panelExpanded ? store.preferences.panelWidth : 360
        return min(max(desired, 360), max(360, containerSize.width - 24))
    }
    private var basePanelHeight: CGFloat {
        glass.panelExpanded
            ? min(max(store.preferences.panelHeight, 320), max(320, containerSize.height - 48))
            : 48
    }
    private var panelWidth: CGFloat {
        min(max(basePanelWidth + resizeOffset.width, 360), max(360, containerSize.width - basePosition.x - 12))
    }
    private var panelHeight: CGFloat {
        glass.panelExpanded
            ? min(max(basePanelHeight + resizeOffset.height, 320), max(320, containerSize.height - basePosition.y - 12))
            : 48
    }
    private var basePosition: CGPoint {
        CGPoint(
            x: min(max(store.preferences.panelX, 12), max(12, containerSize.width - basePanelWidth - 12)),
            y: min(max(store.preferences.panelY, 12), max(12, containerSize.height - basePanelHeight - 12))
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            panel(now: context.date)
        }
        .frame(width: panelWidth, height: panelHeight)
        .foregroundStyle(textColor)
        .background(.clear)
        .glassEffect(glass.useCustom ? glass.buildGlass() : glassEffect, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottomTrailing) {
            if glass.panelExpanded { resizeHandle }
        }
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 7)
        .offset(x: basePosition.x + panelWidth / 2 - containerSize.width / 2 + dragOffset.width,
                y: basePosition.y + dragOffset.height)
        .sheet(item: $editingEvent) { WeeklyScheduleEditor(store: store, event: $0) }
        .sheet(isPresented: $showLibrary) { WeeklyScheduleLibrary(store: store) }
        .sheet(isPresented: $showAI) { AIWeeklyScheduleSheet(store: store, settings: settings) }
        .onChange(of: store.preferences.includesWeekend) { _, includesWeekend in
            if !includesWeekend && selectedDay.rawValue > 5 { selectedDay = .monday }
        }
        .onAppear {
            if !store.preferences.includesWeekend && selectedDay.rawValue > 5 { selectedDay = .monday }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weeklySchedulePanel")
    }

    private func dates(now: Date) -> [Date] {
        let anchor = Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: now) ?? now
        return Array(WeeklyScheduleMath.weekDates(containing: anchor).prefix(store.preferences.includesWeekend ? 7 : 5))
    }

    private func panel(now: Date) -> some View {
        let visibleDates = dates(now: now)
        return VStack(spacing: 0) {
            header
            if glass.panelExpanded {
                Divider().overlay(textColor.opacity(0.1))
                navigation(dates: visibleDates)
                summary(dates: visibleDates, now: now)
                if let error = store.storageError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
                }
                WeeklyScheduleGrid(
                    events: store.events, dates: visibleDates,
                    startMinute: store.preferences.startMinute, endMinute: store.preferences.endMinute,
                    now: now, textColor: textColor, selectedDay: $selectedDay,
                    onEdit: { editingEvent = $0 },
                    onAdd: { addEvent(day: $0, minute: $1) }
                )
                .frame(maxHeight: .infinity)
                freeTimeFooter(dates: visibleDates, now: now)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text("周日程").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        store.preferences.panelX = min(max(basePosition.x + value.translation.width, 12),
                                                       max(12, containerSize.width - panelWidth - 12))
                        store.preferences.panelY = min(max(basePosition.y + value.translation.height, 12),
                                                       max(12, containerSize.height - panelHeight - 12))
                    }
            )
            .help("拖动以移动面板")
            iconButton("添加日程", "plus") {
                addEvent(day: selectedDay, minute: store.preferences.startMinute)
            }
            .accessibilityIdentifier("addWeeklyEvent")
            iconButton("AI 添加日程", "sparkles") { showAI = true }
                .accessibilityIdentifier("weeklyAIOpen")
            iconButton("日程列表", "list.bullet") { showLibrary = true }
            iconButton("显示设置", "slider.horizontal.3") { showDisplaySettings.toggle() }
                .popover(isPresented: $showDisplaySettings) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("周日程显示设置").font(.headline)
                        WeeklyScheduleDisplayControls(store: store)
                    }
                    .padding(18).frame(width: 300)
                }
            iconButton("玻璃效果", "paintpalette") { showGlassSettings.toggle() }
                .popover(isPresented: $showGlassSettings) {
                    ToDoGlassPopover(glassSettings: glass)
                }
            iconButton(glass.panelExpanded ? "折叠周日程" : "展开周日程",
                       glass.panelExpanded ? "chevron.up" : "chevron.down") {
                let position = basePosition
                store.preferences.panelX = position.x
                store.preferences.panelY = position.y
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    glass.panelExpanded.toggle()
                }
            }
            .accessibilityIdentifier("toggleWeeklySchedule")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private func iconButton(_ title: String, _ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func navigation(dates: [Date]) -> some View {
        HStack(spacing: 8) {
            if let first = dates.first, let last = dates.last {
                Text("\(first.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))) — \(last.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))))")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            iconButton("上一周", "chevron.left") { weekOffset -= 1 }
            Button("本周") { weekOffset = 0 }.buttonStyle(.plain).font(.system(size: 12))
            iconButton("下一周", "chevron.right") { weekOffset += 1 }
        }
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private func ranges(for date: Date, now: Date, remaining: Bool) -> [ScheduleMinuteRange] {
        if remaining {
            return WeeklyScheduleMath.remainingFreeRanges(
                events: store.events, date: date, start: store.preferences.startMinute,
                end: store.preferences.endMinute, now: now
            )
        }
        return WeeklyScheduleMath.freeRanges(
            events: store.events, weekday: .from(date), start: store.preferences.startMinute, end: store.preferences.endMinute
        )
    }

    private func summary(dates: [Date], now: Date) -> some View {
        let todayVisible = store.preferences.weekdays.contains(.from(now))
        let todayFree = todayVisible ? ranges(for: now, now: now, remaining: true).reduce(0) { $0 + $1.duration } : 0
        let total = dates.flatMap { ranges(for: $0, now: now, remaining: false) }.reduce(0) { $0 + $1.duration }
        let remaining = dates.flatMap { ranges(for: $0, now: now, remaining: true) }.reduce(0) { $0 + $1.duration }
        return HStack(spacing: 8) {
            stat("今日剩余", value: todayVisible ? WeeklyScheduleMath.durationLabel(todayFree) : "未显示周末")
            stat(weekOffset == 0 ? "本周剩余" : "所选周剩余", value: WeeklyScheduleMath.durationLabel(remaining))
            stat("整周空闲", value: WeeklyScheduleMath.durationLabel(total))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(textColor.opacity(0.6))
            Text(value).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(textColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private func freeTimeFooter(dates: [Date], now: Date) -> some View {
        let date = dates.first { ScheduleWeekday.from($0) == selectedDay } ?? dates.first ?? now
        let remaining = ranges(for: date, now: now, remaining: true)
        let longest = remaining.map(\.duration).max() ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(.teal).frame(width: 5, height: 5)
                Text("\(ScheduleWeekday.from(date).title)剩余空闲")
                    .fontWeight(.medium)
                Spacer()
                if longest > 0 { Text("最长 \(WeeklyScheduleMath.durationLabel(longest))") }
            }
            .font(.system(size: 10))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if remaining.isEmpty {
                        Text(Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: now)
                             ? "该日期已结束" : "显示范围内没有剩余空闲")
                            .foregroundStyle(textColor.opacity(0.6))
                    }
                    ForEach(remaining) { range in
                        Text(range.label)
                            .monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.teal.opacity(0.12), in: Capsule())
                    }
                }
                .font(.system(size: 10))
            }
            .scrollIndicators(.hidden)
            Text(store.events.isEmpty ? "点击＋添加每周日程，或双击时间网格；青色边线表示空闲。" :
                    "青色边线表示空闲；双击空白添加，点击日程编辑。统计仅含显示范围。")
                .font(.system(size: 9)).foregroundStyle(textColor.opacity(0.5)).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
        .overlay(alignment: .top) { Divider().overlay(textColor.opacity(0.1)) }
    }

    private func addEvent(day: ScheduleWeekday, minute: Int) {
        var event = WeeklyScheduleEvent()
        event.weekdays = [day]
        event.startMinute = min(max(minute, 0), 1425)
        event.endMinute = min(event.startMinute + 60, store.preferences.endMinute)
        editingEvent = event
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor.opacity(0.5))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($resizeOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        let position = basePosition
                        let width = min(max(basePanelWidth + value.translation.width, 360),
                                        max(360, containerSize.width - position.x - 12))
                        let height = min(max(basePanelHeight + value.translation.height, 320),
                                         max(320, containerSize.height - position.y - 12))
                        var preferences = store.preferences
                        preferences.panelX = position.x
                        preferences.panelY = position.y
                        preferences.panelWidth = width
                        preferences.panelHeight = height
                        store.preferences = preferences
                    }
            )
            .help("拖动以调整面板大小")
            .accessibilityLabel("调整周日程面板大小")
    }
}
