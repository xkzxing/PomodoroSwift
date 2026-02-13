//
//  PomodoroTimer.swift
//  PomodoroSwift
//

import Foundation
import UserNotifications
import Combine  // 添加这个 import

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

class PomodoroTimer: ObservableObject {
    @Published var timeRemaining: Int
    @Published var isRunning = false
    @Published var isCompleted = false
    @Published var currentMode: TimerMode = .work
    @Published var sessionCount: Int = 0
    
    private var timer: Timer?
    private var totalTime: Int
    private var delayedRestartTimer: Timer?
    private var workTime: Int
    private var breakTime: Int
    private var longBreakTime: Int
    
    private let sessionsBeforeLongBreak = 4
    
    static let notificationCategoryID = "POMODORO_COMPLETE"
    static let actionRestartNow = "RESTART_NOW"
    static let actionRestart5Min = "RESTART_5MIN"
    static let actionRestart10Min = "RESTART_10MIN"
    
    init(workMinutes: Int, breakMinutes: Int = 5, longBreakMinutes: Int = 15) {
        self.workTime = workMinutes * 60
        self.breakTime = breakMinutes * 60
        self.longBreakTime = longBreakMinutes * 60
        self.totalTime = workMinutes * 60
        self.timeRemaining = workMinutes * 60
        setupNotificationCategory()
        setupNotificationObserver()
    }
    
    deinit {
        // Clean up timers
        timer?.invalidate()
        delayedRestartTimer?.invalidate()
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("RestartPomodoroTimer"), object: nil)
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RestartPomodoroTimer"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let delaySeconds = notification.userInfo?["delaySeconds"] as? Int {
                self?.restartTimer(afterDelay: delaySeconds)
            }
        }
    }
    
    private func setupNotificationCategory() {
        let restartNow = UNNotificationAction(
            identifier: Self.actionRestartNow,
            title: "Restart Now",
            options: [.foreground]
        )
        
        let restart5Min = UNNotificationAction(
            identifier: Self.actionRestart5Min,
            title: "5 minutes later",
            options: []
        )
        
        let restart10Min = UNNotificationAction(
            identifier: Self.actionRestart10Min,
            title: "10 minutes later",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [restartNow, restart5Min, restart10Min],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        isCompleted = false
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.complete()
            }
        }
    }
    
    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        pause()
        timeRemaining = totalTime
        isCompleted = false
    }
    
    private func complete() {
        pause()
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
            if sessionCount % sessionsBeforeLongBreak == 0 {
                content.body = "Great work! Time for a long break."
            } else {
                content.body = "Great work! Time for a short break."
            }
        case .shortBreak, .longBreak:
            content.title = "Break Complete!"
            content.body = "Ready to focus again?"
        }
        
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategoryID
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // Public method for restarting timer (called from notification actions)
    func restartTimer(afterDelay seconds: Int = 0) {
        delayedRestartTimer?.invalidate()
        
        if seconds == 0 {
            // Restart immediately
            reset()
            start()
        } else {
            // Schedule restart after delay
            delayedRestartTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
                self?.reset()
                self?.start()
            }
        }
    }
    
    func updateTime(workMinutes: Int, breakMinutes: Int? = nil, longBreakMinutes: Int? = nil) {
        self.workTime = workMinutes * 60
        if let breakMinutes = breakMinutes {
            self.breakTime = breakMinutes * 60
        }
        if let longBreakMinutes = longBreakMinutes {
            self.longBreakTime = longBreakMinutes * 60
        }
        
        // Update current time if not running and in work mode
        if !isRunning && currentMode == .work {
            self.totalTime = workTime
            self.timeRemaining = workTime
        }
    }
    
    func startNextMode() {
        // Determine next mode
        switch currentMode {
        case .work:
            if sessionCount % sessionsBeforeLongBreak == 0 {
                currentMode = .longBreak
                totalTime = longBreakTime
            } else {
                currentMode = .shortBreak
                totalTime = breakTime
            }
        case .shortBreak, .longBreak:
            currentMode = .work
            totalTime = workTime
        }
        
        // Reset and start
        timeRemaining = totalTime
        isCompleted = false
        start()
    }
    
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
