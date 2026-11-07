import ImageIO
import SwiftUI

extension PanelTint {
    var color: Color {
        switch self {
        case .green: return Color(red: 0.57, green: 0.88, blue: 0.56)
        case .blue: return Color(red: 0.53, green: 0.65, blue: 0.96)
        case .yellow: return Color(red: 0.98, green: 0.88, blue: 0.34)
        case .neutral: return .white
        case .pink: return Color(red: 0.98, green: 0.64, blue: 0.72)
        case .purple: return Color(red: 0.74, green: 0.62, blue: 0.96)
        }
    }
}

@MainActor
final class CanvasStyle: ObservableObject {
    private let defaults: UserDefaults
    @Published var preferences: CanvasPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: "mobile.canvas.preferences")
            }
        }
    }
    @Published private(set) var background: UIImage?
    @Published var backdropFrame: CGRect = .zero
    @Published var backgroundPreview: BackgroundTimePreview = .live
    @Published private(set) var liveSky = TodaySkyAstronomy.sky(at: .now, coordinates: nil)
    @Published var sceneBackdrop: UIImage?
    private let backgroundURL: URL

    var sceneSky: TodaySkyAstronomy.Sky? {
        guard preferences.backgroundTheme.isDynamic else { return nil }
        return backgroundPreview == .live ? liveSky : backgroundPreview.sky(at: .now, coordinates: nil)
    }
    var scenePhase: ScenePanelPhase? { sceneSky.map(ScenePanelPhase.init(sky:)) }
    var usesDarkText: Bool { scenePhase.map { $0 == .light } ?? preferences.darkText }
    var textColor: Color { usesDarkText ? .black : .white }
    var chromeTint: Color {
        let tint = preferences.pairedGlassTint ?? (scenePhase == nil ? nil :
            ScenePanelColor.nearestHue(to: preferences.glassTintRGB) ?? .blue)
        guard let tint else { return glassTint }
        return tint.rgb(for: usesDarkText ? .light : .dark).canvasColor
    }
    var dialBackdrop: UIImage? {
        if preferences.backgroundTheme.isDynamic { return sceneBackdrop }
        return preferences.usesPhoto ? background : nil
    }
    var dialBackdropPosition: Double { preferences.backgroundTheme.isDynamic ? 0.5 : preferences.photoPosition }

    func updateSky(coordinates: TodaySkyAstronomy.Coordinates?) {
        liveSky = TodaySkyAstronomy.sky(at: .now, coordinates: coordinates)
    }

    var glassTint: Color {
        let rgb = preferences.glassTintRGB
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
    func setGlassTint(_ color: Color) {
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        preferences.glassTintRGB = [red, green, blue].map { min(max(Double($0), 0), 1) }
    }
    func resetLayout() {
        preferences.clockSize = 300
        preferences.sectionSpacing = 26
        for id in preferences.panels.keys {
            preferences.panels[id]?.expandedHeight = 260
        }
    }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("PomodoroMobile", isDirectory: true)
        backgroundURL = directory.appendingPathComponent("background.jpg")
        if let data = defaults.data(forKey: "mobile.canvas.preferences"),
           let saved = try? JSONDecoder().decode(CanvasPreferences.self, from: data) {
            preferences = saved
        } else { preferences = CanvasPreferences() }
        if let data = try? Data(contentsOf: backgroundURL) { background = Self.downsample(data) }
        if background == nil { background = Self.defaultBackground() }
    }

    func look(for group: TaskGroup, index: Int) -> PanelLook {
        preferences.panels[group.id.uuidString] ?? PanelLook(
            tint: [PanelTint.green, .blue, .yellow, .neutral][index % 4], expanded: index == 0
        )
    }

    func update(_ look: PanelLook, for group: TaskGroup) { preferences.panels[group.id.uuidString] = look }

    func setBackground(_ data: Data) throws {
        guard let image = Self.downsample(data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: backgroundURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: backgroundURL, options: .atomic)
        background = image
        preferences.backgroundTheme = .image
        preferences.usesPhoto = true
    }

    func restoreBackground() throws {
        if FileManager.default.fileExists(atPath: backgroundURL.path) { try FileManager.default.removeItem(at: backgroundURL) }
        background = Self.defaultBackground()
        preferences.backgroundTheme = .image
        preferences.usesPhoto = true
        preferences.photoPosition = 0.66
    }

    private static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2600
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func defaultBackground() -> UIImage? {
        guard let url = Bundle.main.url(forResource: "DesktopBackground", withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        return downsample(data)
    }
}

struct CanvasBackdrop: View {
    @EnvironmentObject private var style: CanvasStyle
    @Environment(\.scenePhase) private var appPhase
    var tracksFrame = false
    var capturesForGemstone = false

    private struct SceneSnapshot: Equatable {
        let scene: DynamicBackgroundView
        let size: CGSize
    }

    var body: some View {
        GeometryReader { geometry in
            if let sky = style.sceneSky {
                let scene = DynamicBackgroundView(sky: sky)
                let size = geometry.size
                let snapshot = sceneSnapshot(scene, size: size)
                scene.equatable()
                    .task(id: snapshot) {
                        guard tracksFrame else { return }
                        guard let snapshot else { style.sceneBackdrop = nil; return }
                        try? await Task.sleep(for: .milliseconds(140))
                        guard !Task.isCancelled else { return }
                        let renderer = ImageRenderer(content: snapshot.scene.frame(width: snapshot.size.width, height: snapshot.size.height))
                        style.sceneBackdrop = renderer.uiImage
                    }
            } else if style.preferences.usesPhoto, let image = style.background {
                let scale = max(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                Image(uiImage: image).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .position(x: size.width / 2 + (geometry.size.width - size.width) * style.preferences.photoPosition,
                              y: geometry.size.height / 2)
            } else { Color.black }
        }
        .onChange(of: style.preferences.backgroundTheme) { _, theme in
            if tracksFrame && !theme.isDynamic { style.sceneBackdrop = nil }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if tracksFrame && style.backdropFrame != frame { style.backdropFrame = frame }
        }
        .clipped().ignoresSafeArea().accessibilityHidden(true)
    }

    private func sceneSnapshot(_ scene: DynamicBackgroundView, size: CGSize) -> SceneSnapshot? {
        guard tracksFrame, capturesForGemstone, appPhase == .active, size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, 1024 / max(size.width, size.height))
        return SceneSnapshot(scene: scene, size: CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded()))
    }
}

private struct DesktopGlassModifier<S: Shape>: ViewModifier {
    @EnvironmentObject private var style: CanvasStyle
    let shape: S
    var tint: Color?
    var opacity: Double?
    var clearGlass: Bool?

    func body(content: Content) -> some View {
        content.background {
            if #available(iOS 26, *) {
                Color.clear.glassEffect(glass, in: shape)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill((tint ?? style.chromeTint).opacity(opacity ?? style.preferences.glassOpacity)))
                    .overlay(shape.stroke(.white.opacity(0.5), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            }
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        var result: Glass = (clearGlass ?? style.preferences.clearGlass) ? .clear : .regular
        result = result.tint((tint ?? style.chromeTint).opacity(opacity ?? style.preferences.glassOpacity))
        if style.preferences.interactive { result = result.interactive() }
        return result
    }
}

extension Array where Element == Double {
    var canvasColor: Color { count == 3 ? Color(red: self[0], green: self[1], blue: self[2]) : .clear }
}

extension View {
    func desktopGlass<S: Shape>(in shape: S, tint: Color? = nil, opacity: Double? = nil, clearGlass: Bool? = nil) -> some View {
        modifier(DesktopGlassModifier(shape: shape, tint: tint, opacity: opacity, clearGlass: clearGlass))
    }
}

struct CanvasIconButton: View {
    let symbol: String
    let title: String
    var size: CGFloat = 44
    let action: () -> Void
    @EnvironmentObject private var style: CanvasStyle

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size > 50 ? 21 : 17, weight: .medium))
                .foregroundStyle(style.textColor.opacity(0.85))
                .frame(width: size, height: size).contentShape(Circle())
                .desktopGlass(in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
