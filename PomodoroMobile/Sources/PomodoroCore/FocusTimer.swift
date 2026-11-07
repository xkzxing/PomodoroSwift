import Foundation

public enum TimerStatus: String, Codable, Sendable { case ready, running, paused, completed }

/// The deadline is persisted. No background execution is needed to keep time.
public struct FocusTimer: Codable, Equatable, Sendable {
    public private(set) var id = UUID()
    public private(set) var mode: FocusMode = .focus
    public private(set) var status: TimerStatus = .ready
    public private(set) var durationSeconds = 25 * 60
    public private(set) var remainingSeconds = 25 * 60
    public private(set) var deadline: Date?
    public private(set) var completedAt: Date?
    // Legacy fields are retained only so updates can preserve existing archives.
    public var taskID: UUID?
    public var taskTitle: String?

    public init() {}
    public var progress: Double {
        min(1, max(0, 1 - Double(remainingSeconds) / Double(max(1, durationSeconds))))
    }
    public func progress(at date: Date) -> Double {
        guard status == .running, let deadline else { return progress }
        return min(1, max(0, 1 - deadline.timeIntervalSince(date) / Double(max(1, durationSeconds))))
    }
    public var displayTime: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    public mutating func prepare(mode: FocusMode, settings: FocusSettings) {
        self = FocusTimer()
        self.mode = mode
        durationSeconds = settings.duration(for: mode)
        remainingSeconds = durationSeconds
    }

    public mutating func start(at now: Date) {
        guard status == .ready || status == .paused, remainingSeconds > 0 else { return }
        deadline = now.addingTimeInterval(TimeInterval(remainingSeconds))
        status = .running
    }

    /// Returns true only on the transition to completed.
    @discardableResult
    public mutating func refresh(at now: Date) -> Bool {
        guard status == .running, let deadline else { return false }
        remainingSeconds = min(durationSeconds, max(0, Int(ceil(deadline.timeIntervalSince(now)))))
        guard remainingSeconds == 0 else { return false }
        completedAt = deadline
        self.deadline = nil
        status = .completed
        return true
    }

    public mutating func pause(at now: Date) {
        guard status == .running else { return }
        if refresh(at: now) { return }
        deadline = nil
        status = .paused
    }
}

public enum TimerCompletionAction: String, Sendable {
    case shortBreak = "START_BREAK"
    case longBreak = "START_LONG_BREAK"
    case focus = "START_FOCUS"
    case stop = "STOP_TIMER"
}

extension AppArchive {
    /// Ignore actions from an old notification so they cannot reset a new session.
    @discardableResult
    public mutating func handleCompletion(_ action: TimerCompletionAction, sessionID: UUID, at date: Date) -> Bool {
        reconcileTimer(at: date)
        guard timer.id == sessionID, timer.status == .completed else { return false }
        switch action {
        case .shortBreak, .longBreak:
            guard timer.mode == .focus else { return false }
            timer.prepare(mode: action == .shortBreak ? .shortBreak : .longBreak, settings: settings)
            timer.start(at: date)
        case .focus:
            guard timer.mode != .focus else { return false }
            timer.prepare(mode: .focus, settings: settings)
            timer.start(at: date)
        case .stop:
            timer.prepare(mode: .focus, settings: settings)
        }
        return true
    }
}
