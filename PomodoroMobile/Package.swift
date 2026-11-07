// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroMobileCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PomodoroCore", targets: ["PomodoroCore"])],
    targets: [
        .target(name: "PomodoroCore"),
        .target(name: "TaskMirrorReader", dependencies: ["PomodoroCore"], path: "App/Services",
                exclude: ["AmbientAudio.swift", "CanvasStyle.swift", "MobileSkyLocation.swift", "MobileStore.swift", "TimerNotifications.swift"],
                sources: ["MobileTaskMirror.swift"]),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"]),
        .testTarget(name: "TaskMirrorReaderTests", dependencies: ["TaskMirrorReader", "PomodoroCore"])
    ]
)
