//
//  PomodoroTimer.swift
//  PomodoroSwift
//

import Foundation
import UserNotifications
import Combine
import AppKit

@MainActor
class PomodoroTimer: ObservableObject {
    @Published var timeRemaining: Int
    @Published var isRunning = false
    @Published var isCompleted = false
    @Published var currentMode: TimerMode = .work
    @Published var sessionCount: Int = 0
    
    private var timer: Timer?
    private var totalTime: Int
    private var delayedRestartTimer: Timer?
    private var schedule: PomodoroSchedule
    private var restartObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    
    // Wall-clock based timing
    private var startDate: Date?
    private var timeRemainingAtStart: Int = 0
    
    static let workNotificationCategoryID = "POMODORO_WORK_COMPLETE"
    static let breakNotificationCategoryID = "POMODORO_BREAK_COMPLETE"
    static let actionStartBreak = "START_BREAK"
    static let actionStartLongBreak = "START_LONG_BREAK"
    static let actionStartFocus = "START_FOCUS"
    static let actionDismiss = "DISMISS"
    
    init(workMinutes: Int, breakMinutes: Int = 5, longBreakMinutes: Int = 15) {
        let schedule = PomodoroSchedule(
            workMinutes: workMinutes,
            breakMinutes: breakMinutes,
            longBreakMinutes: longBreakMinutes
        )
        self.schedule = schedule
        self.totalTime = schedule.workDuration
        self.timeRemaining = schedule.workDuration
        setupNotificationCategory()
        setupNotificationObserver()
        setupAppActiveObserver()
    }
    
    deinit {
        // Clean up timers
        timer?.invalidate()
        delayedRestartTimer?.invalidate()
        
        // Remove notification observers
        if let restartObserver = restartObserver {
            NotificationCenter.default.removeObserver(restartObserver)
        }
        if let appActiveObserver = appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }
    
    private func setupAppActiveObserver() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recalculateTimeRemaining() }
        }
    }
    
    /// Recalculate timeRemaining from wall clock — called when app returns to foreground
    private func recalculateTimeRemaining() {
        guard isRunning, let startDate = startDate else { return }
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let newRemaining = max(0, timeRemainingAtStart - elapsed)
        timeRemaining = newRemaining
        if newRemaining <= 0 {
            complete()
        }
    }
    
    private func setupNotificationObserver() {
        restartObserver = NotificationCenter.default.addObserver(
            forName: .restartPomodoroTimer,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if let action = notification.userInfo?["action"] as? String {
                    switch action {
                    case "shortBreak":
                        self.startBreak(long: false)
                    case "longBreak":
                        self.startBreak(long: true)
                    case "focus":
                        self.startNextMode()
                    default:
                        self.startNextMode()
                    }
                }
            }
        }
    }
    
    private func setupNotificationCategory() {
        // Work complete actions
        let startBreak = UNNotificationAction(
            identifier: Self.actionStartBreak,
            title: "Start Short Break",
            options: [.foreground]
        )
        
        let startLongBreak = UNNotificationAction(
            identifier: Self.actionStartLongBreak,
            title: "Start Long Break",
            options: [.foreground]
        )
        
        let dismiss = UNNotificationAction(
            identifier: Self.actionDismiss,
            title: "Dismiss",
            options: []
        )
        
        let startFocus = UNNotificationAction(
            identifier: Self.actionStartFocus,
            title: "Start Focus Session",
            options: [.foreground]
        )
        
        let workCategory = UNNotificationCategory(
            identifier: Self.workNotificationCategoryID,
            actions: [startBreak, startLongBreak, dismiss],
            intentIdentifiers: [],
            options: []
        )
        
        let breakCategory = UNNotificationCategory(
            identifier: Self.breakNotificationCategoryID,
            actions: [startFocus, dismiss],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([workCategory, breakCategory])
    }
    
    func start() {
        guard !isRunning else { return }
        cancelDelayedRestart()
        guard timeRemaining > 0 else {
            if !isCompleted { complete() }
            return
        }
        isRunning = true
        isCompleted = false
        
        // Record wall-clock start point
        startDate = Date()
        timeRemainingAtStart = timeRemaining
        
        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recalculateTimeRemaining() }
        }
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }
    
    func pause() {
        cancelDelayedRestart()
        // Set isRunning false FIRST to prevent re-entrant complete() if time happens to be 0
        isRunning = false
        // Snapshot the current remaining time before clearing startDate
        if let startDate = startDate {
            let elapsed = Int(Date().timeIntervalSince(startDate))
            timeRemaining = max(0, timeRemainingAtStart - elapsed)
        }
        timer?.invalidate()
        timer = nil
        startDate = nil
    }
    
    func reset() {
        cancelDelayedRestart()
        isRunning = false
        timer?.invalidate()
        timer = nil
        startDate = nil
        timeRemaining = totalTime
        isCompleted = false
    }
    
    /// Fully reset back to work mode (initial state)
    func resetToWork() {
        cancelDelayedRestart()
        isRunning = false
        timer?.invalidate()
        timer = nil
        startDate = nil
        prepare(mode: .work)
    }
    
    private func complete() {
        // Stop timer directly instead of calling pause() to avoid
        // infinite recursion: recalculateTimeRemaining → complete → pause → recalculateTimeRemaining
        isRunning = false
        timer?.invalidate()
        timer = nil
        startDate = nil
        timeRemaining = 0
        isCompleted = true
        
        // Increment session count when completing work
        if currentMode == .work {
            sessionCount += 1
        }
        
        sendNotification()
    }
    
    private func sendNotification() {
        let content = UNMutableNotificationContent()
        
        switch currentMode {
        case .work:
            content.title = "Work Session Complete!"
            if schedule.nextMode(after: .work, completedWorkSessions: sessionCount) == .longBreak {
                content.body = "Great work! Time for a long break."
            } else {
                content.body = "Great work! Time for a short break."
            }
            content.categoryIdentifier = Self.workNotificationCategoryID
        case .shortBreak, .longBreak:
            content.title = "Break Complete!"
            content.body = "Ready to focus again?"
            content.categoryIdentifier = Self.breakNotificationCategoryID
        }
        
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // Public method for handling notification actions
    func restartTimer(afterDelay seconds: Int = 0) {
        cancelDelayedRestart()

        guard seconds > 0 else {
            startNextMode()
            return
        }

        let restartTimer = Timer(
            timeInterval: TimeInterval(seconds),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.delayedRestartTimer = nil
                self.startNextMode()
            }
        }
        delayedRestartTimer = restartTimer
        RunLoop.main.add(restartTimer, forMode: .common)
    }
    
    // Start a specific break mode from notification
    func startBreak(long: Bool) {
        if currentMode == .work {
            prepare(mode: long ? .longBreak : .shortBreak)
            start()
        } else {
            startNextMode()
        }
    }
    
    func updateTime(workMinutes: Int, breakMinutes: Int? = nil, longBreakMinutes: Int? = nil) {
        let previousDuration = schedule.duration(for: currentMode)
        schedule.update(
            workMinutes: workMinutes,
            breakMinutes: breakMinutes,
            longBreakMinutes: longBreakMinutes
        )
        
        let newDuration = schedule.duration(for: currentMode)
        if !isRunning && !isCompleted && newDuration != previousDuration {
            totalTime = newDuration
            timeRemaining = totalTime
        }
    }
    
    func startNextMode() {
        let nextMode = schedule.nextMode(
            after: currentMode,
            completedWorkSessions: sessionCount
        )
        prepare(mode: nextMode)
        start()
    }

    private func prepare(mode: TimerMode) {
        pause()
        currentMode = mode
        totalTime = schedule.duration(for: mode)
        timeRemaining = totalTime
        isCompleted = false
    }

    private func cancelDelayedRestart() {
        delayedRestartTimer?.invalidate()
        delayedRestartTimer = nil
    }

    var totalDuration: TimeInterval {
        TimeInterval(totalTime)
    }

    /// Use the same wall-clock anchor as the countdown for smooth clock hands.
    func elapsedTime(at date: Date) -> TimeInterval {
        let remaining: TimeInterval
        if isRunning, let startDate {
            remaining = TimeInterval(timeRemainingAtStart) - max(0, date.timeIntervalSince(startDate))
        } else {
            remaining = TimeInterval(timeRemaining)
        }
        return min(max(totalDuration - remaining, 0), totalDuration)
    }
    
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
