//
//  PomodoroSwiftApp.swift
//  PomodoroSwift
//
//  Native macOS Pomodoro Timer
//

import SwiftUI
import UserNotifications

@main
struct PomodoroSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Configure window to show traffic lights but hide title
        // Use delay to ensure window is created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
            }
        }
    }
    
    // Handle notification action responses
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        var delaySeconds = 0
        
        switch response.actionIdentifier {
        case PomodoroTimer.actionRestartNow:
            delaySeconds = 0
        case PomodoroTimer.actionRestart5Min:
            delaySeconds = 5 * 60
        case PomodoroTimer.actionRestart10Min:
            delaySeconds = 10 * 60
        case UNNotificationDefaultActionIdentifier:
            // User clicked the notification itself (default action)
            delaySeconds = 0
        default:
            completionHandler()
            return
        }
        
        // Post notification for timer to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("RestartPomodoroTimer"),
            object: nil,
            userInfo: ["delaySeconds": delaySeconds]
        )
        
        completionHandler()
    }
    
    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
