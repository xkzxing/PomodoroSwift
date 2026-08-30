import Foundation

enum TimerMode {
    case work
    case shortBreak
    case longBreak

    var displayName: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

struct PomodoroSchedule {
    private(set) var workDuration: Int
    private(set) var shortBreakDuration: Int
    private(set) var longBreakDuration: Int
    let sessionsBeforeLongBreak: Int

    init(
        workMinutes: Int,
        breakMinutes: Int,
        longBreakMinutes: Int,
        sessionsBeforeLongBreak: Int = 4
    ) {
        self.workDuration = Self.seconds(fromMinutes: workMinutes)
        self.shortBreakDuration = Self.seconds(fromMinutes: breakMinutes)
        self.longBreakDuration = Self.seconds(fromMinutes: longBreakMinutes)
        self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
    }

    func duration(for mode: TimerMode) -> Int {
        switch mode {
        case .work: return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }

    func nextMode(after mode: TimerMode, completedWorkSessions: Int) -> TimerMode {
        switch mode {
        case .work:
            let hasCompletedCycle = completedWorkSessions > 0
                && completedWorkSessions.isMultiple(of: sessionsBeforeLongBreak)
            return hasCompletedCycle ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }

    mutating func update(
        workMinutes: Int,
        breakMinutes: Int? = nil,
        longBreakMinutes: Int? = nil
    ) {
        workDuration = Self.seconds(fromMinutes: workMinutes)
        if let breakMinutes {
            shortBreakDuration = Self.seconds(fromMinutes: breakMinutes)
        }
        if let longBreakMinutes {
            longBreakDuration = Self.seconds(fromMinutes: longBreakMinutes)
        }
    }

    private static func seconds(fromMinutes minutes: Int) -> Int {
        max(0, minutes) * 60
    }
}
