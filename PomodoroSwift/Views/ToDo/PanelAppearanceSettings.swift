import Foundation
import Combine

final class PanelAppearanceSettings: ObservableObject {
    private static func colorsKey(for panelID: UUID) -> String { "panelColors_\(panelID.uuidString)" }

    static func resolvedColors(for panelID: UUID, fallback: ScenePanelColors, defaults: UserDefaults) -> ScenePanelColors {
        if let rawValue = defaults.string(forKey: colorsKey(for: panelID)), let saved = ScenePanelColors(rawValue: rawValue) {
            return saved
        }
        if defaults.bool(forKey: "todoGlassUseCustom_\(panelID.uuidString)"),
           let rgb = defaults.array(forKey: "todoGlassTintColor_\(panelID.uuidString)") as? [Double],
           let tint = ScenePanelColor.nearestHue(to: rgb) {
            return ScenePanelColors(tint)
        }
        return fallback
    }

    private let defaults: UserDefaults
    private let colorsKey: String
    private let expandedKey: String

    @Published var colors: ScenePanelColors {
        didSet { defaults.set(colors.rawValue, forKey: colorsKey) }
    }

    @Published var panelExpanded: Bool {
        didSet { defaults.set(panelExpanded, forKey: expandedKey) }
    }

    init(panelId: UUID, fallback: ScenePanelColors, migrateLegacy: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let colorsKey = Self.colorsKey(for: panelId)
        let expandedKey = "todoPanelExpanded_\(panelId.uuidString)"
        self.colorsKey = colorsKey
        self.expandedKey = expandedKey
        let resolvedColors = Self.resolvedColors(for: panelId, fallback: fallback, defaults: defaults)
        colors = resolvedColors
        let savedExpansion = defaults.object(forKey: expandedKey) as? Bool
        let migrateExpansion = migrateLegacy && !defaults.bool(forKey: "hasMigratedLegacyGlass")
        let legacyExpansion = migrateExpansion ? defaults.object(forKey: "todoPanelExpanded") as? Bool : nil
        panelExpanded = savedExpansion ?? legacyExpansion ?? true
        if savedExpansion == nil, let legacyExpansion { defaults.set(legacyExpansion, forKey: expandedKey) }
        if migrateExpansion { defaults.set(true, forKey: "hasMigratedLegacyGlass") }
        // Remember the assigned colors by ID so reordering the panels doesn't recolor them.
        if defaults.string(forKey: colorsKey) != resolvedColors.rawValue {
            defaults.set(resolvedColors.rawValue, forKey: colorsKey)
        }
    }
}
