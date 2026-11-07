import AppKit
import Combine
import EventKit
import Foundation

nonisolated enum ScheduleCalendarAuthorization: Sendable {
    case notDetermined, authorized, denied, restricted
}

nonisolated struct ScheduleCalendarColor: Sendable, Equatable {
    var red: Double = 0.2
    var green: Double = 0.5
    var blue: Double = 0.9
}

nonisolated struct ScheduleCalendarSource: Identifiable, Sendable {
    let id: String
    let title: String
    let accountID: String
    let accountTitle: String
    let color: ScheduleCalendarColor
}

nonisolated struct ScheduleCalendarEvent: Identifiable, Sendable {
    let id: UUID
    let calendarID: String
    let calendarTitle: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isCancelled: Bool
    let color: ScheduleCalendarColor
}

nonisolated struct ScheduleCalendarSnapshot: Sendable {
    let authorization: ScheduleCalendarAuthorization
    var calendars: [ScheduleCalendarSource] = []
    var events: [ScheduleCalendarEvent] = []
}

nonisolated protocol ScheduleCalendarProviding: Sendable {
    func requestAccess() async throws -> Bool
    func snapshot(selectedIDs: Set<String>, start: Date?, end: Date?) async -> ScheduleCalendarSnapshot
}

// Keep synchronous EventKit queries off the UI thread. EventKit objects never leave this actor.
actor EventKitScheduleProvider: ScheduleCalendarProviding {
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func snapshot(selectedIDs: Set<String>, start: Date?, end: Date?) -> ScheduleCalendarSnapshot {
        let authorization: ScheduleCalendarAuthorization
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: authorization = .authorized
        case .notDetermined: authorization = .notDetermined
        case .restricted: authorization = .restricted
        default: authorization = .denied
        }
        guard authorization == .authorized else { return ScheduleCalendarSnapshot(authorization: authorization) }
        let calendars = store.calendars(for: .event)
        let sources = calendars.map { calendar in
            ScheduleCalendarSource(id: calendar.calendarIdentifier, title: calendar.title,
                                   accountID: calendar.source.sourceIdentifier, accountTitle: calendar.source.title,
                                   color: color(calendar.cgColor))
        }.sorted { ($0.accountTitle, $0.title, $0.id) < ($1.accountTitle, $1.title, $1.id) }
        let selected = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        // Passing nil or an empty calendar list to EventKit can query every calendar. Never do that.
        guard !selected.isEmpty, let start, let end, start < end else {
            return ScheduleCalendarSnapshot(authorization: authorization, calendars: sources)
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        let events = store.events(matching: predicate).compactMap { event -> ScheduleCalendarEvent? in
            guard !event.isAllDay, event.status != .canceled,
                  let startDate = event.startDate, let endDate = event.endDate, startDate < endDate else { return nil }
            return ScheduleCalendarEvent(id: UUID(), calendarID: event.calendar.calendarIdentifier,
                                         calendarTitle: event.calendar.title, title: event.title ?? "未命名日程",
                                         start: startDate, end: endDate, isAllDay: false, isCancelled: false,
                                         color: color(event.calendar.cgColor))
        }
        return ScheduleCalendarSnapshot(authorization: authorization, calendars: sources, events: events)
    }

    private func color(_ value: CGColor?) -> ScheduleCalendarColor {
        guard let rgb = value?.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3 else { return ScheduleCalendarColor() }
        return ScheduleCalendarColor(red: components[0], green: components[1], blue: components[2])
    }
}

/// A temporary projection, never persisted into the recurring schedule store.
enum ScheduleCalendarProjection {
    static func event(_ event: ScheduleCalendarEvent, on date: Date, calendar: Calendar = .current) -> WeeklyScheduleEvent? {
        let day = calendar.startOfDay(for: date)
        guard !event.isAllDay, !event.isCancelled, event.start < event.end,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
              event.start < nextDay, event.end > day else { return nil }
        let start = event.start <= day ? 0 : WeeklyScheduleMath.minuteOfDay(event.start, calendar: calendar)
        let end = event.end >= nextDay ? 1440 : WeeklyScheduleMath.minuteOfDay(event.end, calendar: calendar)
        // A short event still occupies at least one visible minute.
        return WeeklyScheduleEvent(id: event.id, title: event.title.isEmpty ? "未命名日程" : event.title,
                                   weekdays: [.from(day, calendar: calendar)], startMinute: start,
                                   endMinute: min(1440, max(start + 1, end)))
    }

    static func visibleEvents(_ events: [ScheduleCalendarEvent], selectedIDs: Set<String>, dates: [Date],
                              calendar: Calendar = .current) -> [ScheduleCalendarEvent] {
        events.filter { event in
            selectedIDs.contains(event.calendarID) && dates.contains { self.event(event, on: $0, calendar: calendar) != nil }
        }
    }
}

@MainActor
final class ScheduleCalendarStore: ObservableObject {
    static let enabledKey = "weeklySchedule.calendar.enabled.v1"
    static let selectionKey = "weeklySchedule.calendar.selection.v1"
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { events = [] }
            refresh()
        }
    }
    @Published private(set) var selectedIDs: Set<String>
    @Published private(set) var calendars: [ScheduleCalendarSource] = []
    @Published private(set) var events: [ScheduleCalendarEvent] = []
    @Published private(set) var authorization: ScheduleCalendarAuthorization = .notDetermined
    @Published private(set) var isLoading = false
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let provider: any ScheduleCalendarProviding
    private var dates: [Date] = []
    private var revision = 0
    private var refreshTask: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard, provider: any ScheduleCalendarProviding = EventKitScheduleProvider()) {
        self.defaults = defaults
        self.provider = provider
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.selectedIDs = Set(defaults.stringArray(forKey: Self.selectionKey) ?? [])
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                     .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                }
                .store(in: &observers)
        }
    }

    var missingSelectionCount: Int { selectedIDs.subtracting(calendars.map(\.id)).count }

    func select(_ id: String, enabled: Bool) {
        if enabled { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        defaults.set(selectedIDs.sorted(), forKey: Self.selectionKey)
        // Remove deselected events immediately, even if an earlier fetch is still pending.
        events.removeAll { !selectedIDs.contains($0.calendarID) }
        refresh()
    }

    func requestAccess() async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        errorMessage = nil
        defer { isRequestingAccess = false }
        do {
            if try await provider.requestAccess() { isEnabled = true }
        } catch {
            errorMessage = "无法取得日历访问权限，请检查系统设置中的日历权限后重试。"
        }
        await reload()
    }

    func updateDates(_ dates: [Date]) async {
        if self.dates != dates { events = [] }
        self.dates = dates
        await reload()
    }

    func refresh() {
        // Invalidate before the new task starts, so older requests cannot publish stale events.
        revision += 1
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.reload() }
    }

    func reload() async {
        guard !Task.isCancelled else { return }
        revision += 1
        let requestRevision = revision
        let selected = isEnabled ? selectedIDs : []
        let visibleDates = dates
        let end = visibleDates.last.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
        isLoading = true
        defer { if requestRevision == revision { isLoading = false } }
        let snapshot = await provider.snapshot(selectedIDs: selected, start: visibleDates.first, end: end)
        guard requestRevision == revision, !Task.isCancelled else { return }
        authorization = snapshot.authorization
        calendars = snapshot.calendars
        events = isEnabled && authorization == .authorized
            ? ScheduleCalendarProjection.visibleEvents(snapshot.events, selectedIDs: selectedIDs, dates: visibleDates) : []
    }
}
