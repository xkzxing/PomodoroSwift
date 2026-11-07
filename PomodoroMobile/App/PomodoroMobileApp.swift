import SwiftUI

@main
struct PomodoroMobileApp: App {
    @StateObject private var store = MobileStore()
    @StateObject private var canvasStyle = CanvasStyle()
    @StateObject private var taskMirror = MobileTaskMirror()
    @StateObject private var skyLocation = MobileSkyLocation()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                RootView()
                    .environmentObject(store)
                    .environmentObject(canvasStyle)
                    .environmentObject(taskMirror)
                    .environmentObject(skyLocation)
            }
        }
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
