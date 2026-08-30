import SwiftUI
import Combine

class ToDoGlassSettings: ObservableObject {
    let panelId: UUID

    private func key(_ base: String) -> String {
        "\(base)_\(panelId.uuidString)"
    }

    @Published var useCustom: Bool {
        didSet { UserDefaults.standard.set(useCustom, forKey: key("todoGlassUseCustom")) }
    }
    @Published var variant: String {
        didSet { UserDefaults.standard.set(variant, forKey: key("todoGlassVariant")) }
    }
    @Published var tintColor: Color {
        didSet {
            if let components = tintColor.cgColor?.components, components.count >= 3 {
                UserDefaults.standard.set([components[0], components[1], components[2]], forKey: key("todoGlassTintColor"))
            }
        }
    }
    @Published var tintOpacity: Double {
        didSet { UserDefaults.standard.set(tintOpacity, forKey: key("todoGlassTintOpacity")) }
    }
    @Published var fontDark: Bool {
        didSet { UserDefaults.standard.set(fontDark, forKey: key("todoFontDark")) }
    }
    @Published var panelExpanded: Bool {
        didSet { UserDefaults.standard.set(panelExpanded, forKey: key("todoPanelExpanded")) }
    }

    init(panelId: UUID) {
        self.panelId = panelId

        func k(_ base: String) -> String { "\(base)_\(panelId.uuidString)" }

        func migrate<T>(base: String, type: T.Type) -> T? {
            let uniqueKey = k(base)
            if UserDefaults.standard.object(forKey: uniqueKey) != nil {
                return UserDefaults.standard.object(forKey: uniqueKey) as? T
            }
            if !UserDefaults.standard.bool(forKey: "hasMigratedLegacyGlass") {
                if UserDefaults.standard.object(forKey: base) != nil {
                    let val = UserDefaults.standard.object(forKey: base) as? T
                    UserDefaults.standard.set(val, forKey: uniqueKey)
                    return val
                }
            }
            return nil
        }

        self.useCustom = migrate(base: "todoGlassUseCustom", type: Bool.self) ?? false
        self.variant = migrate(base: "todoGlassVariant", type: String.self) ?? "regular"
        if let arr = migrate(base: "todoGlassTintColor", type: [CGFloat].self), arr.count >= 3 {
            self.tintColor = Color(red: arr[0], green: arr[1], blue: arr[2])
        } else {
            self.tintColor = .white
        }
        let savedOpacity = migrate(base: "todoGlassTintOpacity", type: Double.self) ?? 0
        self.tintOpacity = savedOpacity != 0 ? savedOpacity : 0.15

        self.fontDark = migrate(base: "todoFontDark", type: Bool.self) ?? false
        self.panelExpanded = migrate(base: "todoPanelExpanded", type: Bool.self) ?? true

        UserDefaults.standard.set(true, forKey: "hasMigratedLegacyGlass")
    }

    static let variants: [(String, String)] = [
        ("Clear", "clear"),
        ("Regular", "regular")
    ]

    func buildGlass() -> Glass {
        let base: Glass = variant == "clear" ? .clear : .regular
        return base.tint(tintColor.opacity(tintOpacity))
    }
}
