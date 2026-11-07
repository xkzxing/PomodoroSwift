import CryptoKit
import Foundation

/// Shared wire format. The desktop is the only publisher; the phone has no writer.
nonisolated public struct TaskMirrorSnapshot: Codable, Equatable, Sendable {
    public static let fileName = "PomodoroSwift-Tasks.json"
    public let publisherID: UUID
    public let revision: UInt64
    public let publishedAt: Date
    public let panels: [Panel]
    /// Absent in snapshots from desktops predating the Today panel.
    public let today: TodayAppearance?

    nonisolated public struct Item: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let text: String
        public let isPinned: Bool
        public let isInToday: Bool
        public init(id: UUID, text: String, isPinned: Bool, isInToday: Bool = false) {
            self.id = id; self.text = text; self.isPinned = isPinned
            self.isInToday = isInToday
        }

        private enum CodingKeys: String, CodingKey { case id, text, isPinned, isInToday }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            text = try values.decode(String.self, forKey: .text)
            isPinned = try values.decode(Bool.self, forKey: .isPinned)
            isInToday = try values.decodeIfPresent(Bool.self, forKey: .isInToday) ?? false
        }
    }

    nonisolated public struct DaylightPalette: Codable, Equatable, Sendable {
        public let lightRGB: [Double]
        public let darkRGB: [Double]
        public init(lightRGB: [Double], darkRGB: [Double]) {
            self.lightRGB = lightRGB; self.darkRGB = darkRGB
        }
    }

    nonisolated public struct Appearance: Codable, Equatable, Sendable {
        public let clearGlass: Bool
        public let tintRGB: [Double]
        public let opacity: Double
        public let darkText: Bool
        public let daylightPalette: DaylightPalette?
        public init(clearGlass: Bool, tintRGB: [Double], opacity: Double, darkText: Bool,
                    daylightPalette: DaylightPalette? = nil) {
            self.clearGlass = clearGlass; self.tintRGB = tintRGB
            self.opacity = opacity; self.darkText = darkText
            self.daylightPalette = daylightPalette
        }

        /// A static backdrop or an older snapshot uses the desktop's resolved appearance.
        public func colors(forLightScene light: Bool?) -> (tint: [Double], darkText: Bool) {
            guard let light, let daylightPalette else { return (tintRGB, darkText) }
            return (light ? daylightPalette.lightRGB : daylightPalette.darkRGB, light)
        }
    }

    nonisolated public struct TodayAppearance: Codable, Equatable, Sendable {
        nonisolated public enum Theme: String, Codable, CaseIterable, Sendable { case custom, sky }
        public static let defaultGradientStart = 0x40BAA6
        public static let defaultGradientEnd = 0x61A1E6
        public static let defaultGradientOpacity = 0.24
        public static let defaultSkyConcentration = 0.5

        public let theme: Theme
        public let gradientStart: Int
        public let gradientEnd: Int
        public let gradientOpacity: Double
        public let skyConcentration: Double

        public init(theme: Theme = .custom, gradientStart: Int = Self.defaultGradientStart,
                    gradientEnd: Int = Self.defaultGradientEnd, gradientOpacity: Double = Self.defaultGradientOpacity,
                    skyConcentration: Double = Self.defaultSkyConcentration) {
            self.theme = theme
            self.gradientStart = gradientStart; self.gradientEnd = gradientEnd
            self.gradientOpacity = gradientOpacity; self.skyConcentration = skyConcentration
        }
    }

    nonisolated public struct Panel: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let items: [Item]
        public let appearance: Appearance
        public init(id: UUID, title: String, items: [Item], appearance: Appearance) {
            self.id = id; self.title = title; self.items = items; self.appearance = appearance
        }
    }

    nonisolated public struct TodayEntry: Identifiable, Sendable {
        public let panelTitle: String
        public let item: Item
        public var id: UUID { item.id }
    }

    public var todayEntries: [TodayEntry] {
        panels.flatMap { panel in
            panel.items.filter(\.isInToday).map { TodayEntry(panelTitle: panel.title, item: $0) }
        }
    }

    public init(publisherID: UUID, revision: UInt64, publishedAt: Date, panels: [Panel], today: TodayAppearance? = nil) {
        self.publisherID = publisherID; self.revision = revision
        self.publishedAt = publishedAt; self.panels = panels
        self.today = today
    }

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let payload: Data
        let sha256: String
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(self)
        let data = try encoder.encode(Envelope(format: "PomodoroSwift.TaskMirror", version: 1,
                                               payload: payload, sha256: Self.digest(payload)))
        guard data.count <= 16 * 1024 * 1024 else { throw TaskMirrorError.invalidSnapshot }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { throw TaskMirrorError.invalidSnapshot }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.format == "PomodoroSwift.TaskMirror", envelope.version == 1 else {
            throw TaskMirrorError.unsupportedFormat
        }
        guard envelope.sha256 == digest(envelope.payload) else { throw TaskMirrorError.failedChecksum }
        let snapshot = try JSONDecoder().decode(Self.self, from: envelope.payload)
        try snapshot.validate()
        return snapshot
    }

    public func validate() throws {
        guard revision > 0, publishedAt.timeIntervalSince1970.isFinite, panels.count <= 512 else {
            throw TaskMirrorError.invalidSnapshot
        }
        if let today {
            guard (0...0xFFFFFF).contains(today.gradientStart), (0...0xFFFFFF).contains(today.gradientEnd),
                  (0...0.65).contains(today.gradientOpacity), (0...1).contains(today.skyConcentration) else {
                throw TaskMirrorError.invalidSnapshot
            }
        }
        var panelIDs = Set<UUID>()
        var itemIDs = Set<UUID>()
        for panel in panels {
            guard panelIDs.insert(panel.id).inserted, panel.title.count <= 1024,
                  Self.validRGB(panel.appearance.tintRGB),
                  panel.appearance.opacity.isFinite, (0...1).contains(panel.appearance.opacity) else {
                throw TaskMirrorError.invalidSnapshot
            }
            if let palette = panel.appearance.daylightPalette {
                guard Self.validRGB(palette.lightRGB), Self.validRGB(palette.darkRGB) else {
                    throw TaskMirrorError.invalidSnapshot
                }
            }
            for item in panel.items {
                guard itemIDs.insert(item.id).inserted, itemIDs.count <= 50_000,
                      !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      item.text.count <= 100_000 else { throw TaskMirrorError.invalidSnapshot }
            }
        }
    }

    private static func validRGB(_ rgb: [Double]) -> Bool {
        rgb.count == 3 && rgb.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    /// An older cloud copy never replaces a more recent accepted result.
    public func shouldReplace(_ current: Self?, expectedPublisherID: UUID?) throws -> Bool {
        try validate()
        if let expectedPublisherID, publisherID != expectedPublisherID { throw TaskMirrorError.differentPublisher }
        guard let current, current.publisherID == publisherID else { return true }
        if revision < current.revision { return false }
        if revision == current.revision {
            guard self == current else { throw TaskMirrorError.conflictingRevision }
            return false
        }
        return true
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated public enum TaskMirrorError: LocalizedError, Sendable {
    case invalidSnapshot, unsupportedFormat, failedChecksum, differentPublisher, conflictingRevision, revisionOverflow
    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot: return "同步文件不完整或内容无效，已保留上次读取的结果。"
        case .unsupportedFormat: return "同步文件版本不兼容，请更新应用。"
        case .failedChecksum: return "同步文件校验未通过，已保留上次读取的结果。"
        case .differentPublisher: return "这个同步文件来自其他电脑，请重新选择对应的文件夹。"
        case .conflictingRevision: return "同步文件的版本与内容不一致，已保留上次读取的结果。"
        case .revisionOverflow: return "同步版本已超出支持范围，请重新设置同步。"
        }
    }
}
