import Foundation

struct SwissClockProgress {
    let totalDuration: TimeInterval
    let elapsedTime: TimeInterval

    init(totalDuration: TimeInterval, elapsedTime: TimeInterval) {
        self.totalDuration = max(0, totalDuration)
        self.elapsedTime = min(max(0, elapsedTime), self.totalDuration)
    }

    var redHandDegrees: Double {
        guard totalDuration > 0 else { return 0 }
        return elapsedTime / totalDuration * 360
    }
}
