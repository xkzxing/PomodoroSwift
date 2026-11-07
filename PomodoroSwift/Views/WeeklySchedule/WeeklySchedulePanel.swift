import SwiftUI

struct WeeklySchedulePanel: View {
    @ObservedObject var store: WeeklyScheduleStore
    @EnvironmentObject private var settings: Settings
    @StateObject private var appearance = PanelAppearanceSettings(
        panelId: WeeklyScheduleStore.panelID, fallback: .scheduleDefault, migrateLegacy: false
    )
    @Environment(\.scenePanelPhase) private var phase
    let containerSize: CGSize

    @ObservedObject private var calendarStore: ScheduleCalendarStore
    @State private var showCalendars = false
    @State private var selectedDay = ScheduleWeekday.from(Date())
    @State private var editingEvent: WeeklyScheduleEvent?
    @State private var showLibrary = false
    @State private var showDisplaySettings = false
    @State private var showGlassSettings = false
    @State private var showAI = false
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeOffset: CGSize = .zero

    init(store: WeeklyScheduleStore, containerSize: CGSize) {
        self.store = store
        self.calendarStore = store.calendarStore
        self.containerSize = containerSize
    }

    private var palette: ScenePanelPalette { appearance.colors.palette(for: phase) }
    private var textColor: Color { palette.ink }
    private var basePanelWidth: CGFloat {
        let desired = appearance.panelExpanded ? store.preferences.panelWidth : 360
        return min(max(desired, 360), max(360, containerSize.width - 24))
    }
    private var basePanelHeight: CGFloat {
        appearance.panelExpanded
            ? min(max(store.preferences.panelHeight, 320), max(320, containerSize.height - 48))
            : 48
    }
    private var panelWidth: CGFloat {
        min(max(basePanelWidth + resizeOffset.width, 360), max(360, containerSize.width - basePosition.x - 12))
    }
    private var panelHeight: CGFloat {
        appearance.panelExpanded
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
        .scenePanelSurface(RoundedRectangle(cornerRadius: 16), palette: palette)
        .overlay(alignment: .bottomTrailing) {
            if appearance.panelExpanded { resizeHandle }
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
        WeeklyScheduleMath.visibleDates(now: now, firstDay: store.preferences.firstDay,
                                        includesWeekend: store.preferences.includesWeekend)
    }

    private func panel(now: Date) -> some View {
        let visibleDates = dates(now: now)
        return VStack(spacing: 0) {
            header
            if appearance.panelExpanded {
                Divider().overlay(textColor.opacity(0.1))
                if let error = store.storageError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
                }
                WeeklyScheduleGrid(
                    events: store.events, calendarEvents: calendarStore.events, dates: visibleDates,
                    startMinute: store.preferences.startMinute, endMinute: store.preferences.endMinute,
                    minimumFontSize: store.preferences.minimumFontSize,
                    now: now, textColor: textColor, selectedDay: $selectedDay,
                    onEdit: { editingEvent = $0 },
                    onAdd: { addEvent(day: $0, minute: $1) }
                )
                .frame(maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // 只在可见日期范围变化时刷新。按时间轴时间刷新会导致日历状态发布、
        // 界面重绘、时间再次变化，最终形成持续刷新回路。
        .task(id: visibleDates) { await calendarStore.updateDates(visibleDates) }
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
            iconButton("日历来源", "calendar.badge.clock") { showCalendars = true }
                .accessibilityIdentifier("weeklyCalendarSources")
                .popover(isPresented: $showCalendars, arrowEdge: .top) {
                    ScheduleCalendarSettings(calendarStore: calendarStore)
                        .padding(18).frame(width: 350)
                }
            iconButton("显示设置", "slider.horizontal.3") { showDisplaySettings.toggle() }
                .popover(isPresented: $showDisplaySettings, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("周日程显示设置").font(.headline)
                        WeeklyScheduleDisplayControls(store: store)
                    }
                    .padding(18).frame(width: 300)
                }
            iconButton("周日程配色", "paintpalette") { showGlassSettings.toggle() }
                .popover(isPresented: $showGlassSettings, arrowEdge: .top) {
                    ScenePanelColorControls(colors: $appearance.colors)
                        .padding(14)
                }
            iconButton(appearance.panelExpanded ? "折叠周日程" : "展开周日程",
                       appearance.panelExpanded ? "chevron.up" : "chevron.down") {
                let position = basePosition
                store.preferences.panelX = position.x
                store.preferences.panelY = position.y
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    appearance.panelExpanded.toggle()
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
