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
        
        switch response.actionIdentifier {
        case PomodoroTimer.actionStartBreak:
            NotificationCenter.default.post(
                name: NSNotification.Name("RestartPomodoroTimer"),
                object: nil,
                userInfo: ["action": "shortBreak"]
            )
        case PomodoroTimer.actionStartLongBreak:
            NotificationCenter.default.post(
                name: NSNotification.Name("RestartPomodoroTimer"),
                object: nil,
                userInfo: ["action": "longBreak"]
            )
        case UNNotificationDefaultActionIdentifier:
            // User clicked the notification itself
            NotificationCenter.default.post(
                name: NSNotification.Name("RestartPomodoroTimer"),
                object: nil,
                userInfo: ["action": "next"]
            )
        default:
            break
        }
        
        completionHandler()
    }
    
    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
