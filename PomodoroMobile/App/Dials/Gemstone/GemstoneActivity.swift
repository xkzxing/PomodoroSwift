import Metal
import UIKit

nonisolated enum GemstoneActivity {
    /// iOS disallows submitting GPU work while the app is in the background.
    static func commitWhenActive(_ command: MTLCommandBuffer) async throws {
        while true {
            try Task.checkCancellation()
            let committed = await MainActor.run {
                guard UIApplication.shared.applicationState == .active else { return false }
                command.commit()
                return true
            }
            if committed { return }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
