import SwiftUI

private struct TodoTextColorKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

extension EnvironmentValues {
    var todoTextColor: Color {
        get { self[TodoTextColorKey.self] }
        set { self[TodoTextColorKey.self] = newValue }
    }
}
