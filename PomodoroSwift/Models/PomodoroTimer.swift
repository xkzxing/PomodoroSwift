//
//  PomodoroTimer.swift
//  PomodoroSwift
//

import Foundation
import UserNotifications
import Combine  // 添加这个 import

class PomodoroTimer: ObservableObject {
    @Published var timeRemaining: Int
    @Published var isRunning = false
    @Published var isCompleted = false
    
    private var timer: Timer?
    private let totalTime: Int
    private var delayedRestartTimer: Timer?
    
    static let notificationCategoryID = "POMODORO_COMPLETE"
    static let actionRestartNow = "RESTART_NOW"
    static let actionRestart5Min = "RESTART_5MIN"
    static let actionRestart10Min = "RESTART_10MIN"
    
    init(minutes: Int) {
        self.totalTime = minutes * 60
        self.timeRemaining = minutes * 60
        setupNotificationCategory()
        setupNotificationObserver()
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
        sendNotification()
    }
    
    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Pomodoro Complete!"
        content.body = "Time to take a break."
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
    
    func updateTime(minutes: Int) {
        let newTotal = minutes * 60
        self.timeRemaining = newTotal
        // Don't update if timer is running
    }
    
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
