import Foundation
import UserNotifications

@MainActor
final class TimerNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onAction: ((TimerCompletionAction, UUID) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private let identifier = "pomodoro-mobile.timer"
    private let workCategory = "POMODORO_WORK_COMPLETE"
    private let breakCategory = "POMODORO_BREAK_COMPLETE"

    override init() {
        super.init()
        center.delegate = self
        let short = UNNotificationAction(identifier: TimerCompletionAction.shortBreak.rawValue, title: "开始短休息", options: [.foreground])
        let long = UNNotificationAction(identifier: TimerCompletionAction.longBreak.rawValue, title: "开始长休息", options: [.foreground])
        let focus = UNNotificationAction(identifier: TimerCompletionAction.focus.rawValue, title: "开始专注", options: [.foreground])
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "关闭", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: workCategory, actions: [short, long, dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: breakCategory, actions: [focus, dismiss], intentIdentifiers: [])
        ])
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func update(timer: FocusTimer, enabled: Bool) async throws {
        if enabled && timer.status == .completed { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        guard enabled, timer.status == .running, let deadline = timer.deadline, deadline > Date() else { return }
        let permission = await center.notificationSettings()
        guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = timer.mode == .focus ? "专注完成" : "休息结束"
        content.body = timer.mode == .focus ? "可以选择短休息或长休息。" : "准备好后，开启下一段专注。"
        content.categoryIdentifier = timer.mode == .focus ? workCategory : breakCategory
        content.userInfo = ["sessionID": timer.id.uuidString]
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler([.banner, .sound]) }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let action = TimerCompletionAction(rawValue: response.actionIdentifier),
              let value = response.notification.request.content.userInfo["sessionID"] as? String,
              let sessionID = UUID(uuidString: value) else { completionHandler(); return }
        Task { @MainActor in
            onAction?(action, sessionID)
            completionHandler()
        }
    }
}
