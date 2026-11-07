import Foundation

@MainActor
enum DesktopTaskMirrorSource {
    struct Contents: Equatable {
        let panels: [TaskMirrorSnapshot.Panel]
        let today: TaskMirrorSnapshot.TodayAppearance
    }

    static func contents(defaults: UserDefaults, coordinates: TodaySkyAstronomy.Coordinates?) throws -> Contents {
        typealias Appearance = TaskMirrorSnapshot.TodayAppearance
        func color(_ key: String, fallback: Int) -> Int {
            guard let value = defaults.object(forKey: key) as? Int, (0...0xFFFFFF).contains(value) else { return fallback }
            return value
        }
        func strength(_ key: String, maximum: Double, fallback: Double) -> Double {
            guard let value = defaults.object(forKey: key) as? Double, value.isFinite else { return fallback }
            return min(max(value, 0), maximum)
        }
        return Contents(panels: try panels(defaults: defaults, coordinates: coordinates), today: Appearance(
            theme: Appearance.Theme(rawValue: defaults.string(forKey: "todayPanelTheme") ?? "") ?? .custom,
            gradientStart: color("todayGradientStart", fallback: Appearance.defaultGradientStart),
            gradientEnd: color("todayGradientEnd", fallback: Appearance.defaultGradientEnd),
            gradientOpacity: strength("todayGradientOpacity", maximum: 0.65, fallback: Appearance.defaultGradientOpacity),
            skyConcentration: strength("todaySkyColorConcentration", maximum: 1, fallback: Appearance.defaultSkyConcentration)
        ))
    }

    /// Read only the existing task and appearance keys. Never import from the phone.
    static func panels(defaults: UserDefaults = .standard, now: Date = .now,
                       coordinates: TodaySkyAstronomy.Coordinates? = nil) throws -> [TaskMirrorSnapshot.Panel] {
        guard let panelData = defaults.data(forKey: "todoPanels") else { throw CocoaError(.fileNoSuchFile) }
        let panels = try JSONDecoder().decode([ToDoPanel].self, from: panelData)
        let background = BackgroundTheme(storedValue: defaults.string(forKey: "backgroundTheme"))
        let phase: ScenePanelPhase = if background.isDynamic {
            ScenePanelPhase(sky: TodaySkyAstronomy.sky(at: now, coordinates: coordinates))
        } else {
            (defaults.object(forKey: "sidebarDarkMode") as? Bool ?? true) ? .dark : .light
        }
        let clearGlass = defaults.string(forKey: "glassVariant") == "clear"
        let tintOpacity = Settings.panelGlassTintOpacity(defaults: defaults)
        return try panels.enumerated().map { index, panel in
            let data = defaults.data(forKey: "toDoItems_\(panel.id.uuidString)")
                ?? (index == 0 && !defaults.bool(forKey: "hasMigratedLegacyToDoStore") ? defaults.data(forKey: "toDoItems") : nil)
            let decoded = try data.map { try JSONDecoder().decode([ToDoItem].self, from: $0) } ?? []
            let remaining = decoded.filter { !$0.isDone }
            let ordered = remaining.filter(\.isPinned) + remaining.filter { !$0.isPinned }
            let colors = PanelAppearanceSettings.resolvedColors(
                for: panel.id, fallback: .taskDefault(at: index), defaults: defaults
            )
            let appearance = TaskMirrorSnapshot.Appearance(
                clearGlass: clearGlass,
                tintRGB: colors.tint.rgb(for: phase),
                opacity: tintOpacity,
                darkText: phase == .light,
                daylightPalette: .init(lightRGB: colors.tint.rgb(for: .light), darkRGB: colors.tint.rgb(for: .dark))
            )
            return TaskMirrorSnapshot.Panel(id: panel.id, title: panel.title,
                items: ordered.map { .init(id: $0.id, text: $0.text, isPinned: $0.isPinned, isInToday: $0.isInToday) },
                appearance: appearance)
        }
    }
}

/// The writer exists only in the macOS target.
actor DesktopTaskMirrorWriter {
    func publish(panels: [TaskMirrorSnapshot.Panel], directory: URL, publisherID: UUID,
                 previousRevision: UInt64, today: TaskMirrorSnapshot.TodayAppearance? = nil) throws -> TaskMirrorSnapshot {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let file = directory.appendingPathComponent(TaskMirrorSnapshot.fileName)
        let placeholder = directory.appendingPathComponent(".\(TaskMirrorSnapshot.fileName).icloud")
        var coordinationError: NSError?
        var result: Result<TaskMirrorSnapshot, Error>?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { coordinated in
            result = Result {
                var revision = previousRevision
                if FileManager.default.fileExists(atPath: coordinated.path) || FileManager.default.fileExists(atPath: placeholder.path) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: coordinated)
                    if let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 16 * 1024 * 1024 { throw TaskMirrorError.invalidSnapshot }
                    let existing = try TaskMirrorSnapshot.decode(Data(contentsOf: coordinated))
                    guard existing.publisherID == publisherID else { throw TaskMirrorError.differentPublisher }
                    revision = max(revision, existing.revision)
                }
                guard revision < UInt64.max else { throw TaskMirrorError.revisionOverflow }
                let snapshot = TaskMirrorSnapshot(publisherID: publisherID, revision: revision + 1,
                                                  publishedAt: Date(), panels: panels, today: today)
                try snapshot.encoded().write(to: coordinated, options: .atomic)
                return snapshot
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
