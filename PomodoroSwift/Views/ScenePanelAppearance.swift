import SwiftUI

private struct ScenePanelPhaseKey: EnvironmentKey {
    static let defaultValue = ScenePanelPhase.light
}

private struct PanelGlassStyleKey: EnvironmentKey {
    static let defaultValue = PanelGlassStyle()
}

extension EnvironmentValues {
    var scenePanelPhase: ScenePanelPhase {
        get { self[ScenePanelPhaseKey.self] }
        set { self[ScenePanelPhaseKey.self] = newValue }
    }

    var panelGlassStyle: PanelGlassStyle {
        get { self[PanelGlassStyleKey.self] }
        set { self[PanelGlassStyleKey.self] = newValue }
    }
}

struct PanelGlassStyle {
    var variant = "regular"
    var tintOpacity = 0.50
    var interactive = false

    func material(tint color: Color? = nil) -> Glass {
        let base: Glass = variant == "clear" ? .clear : .regular
        let glass = color.map { base.tint($0.opacity(tintOpacity)) } ?? base
        return interactive ? glass.interactive() : glass
    }

    func tinted(_ color: Color) -> Glass { material(tint: color) }
}

extension ScenePanelColor {
    var title: LocalizedStringKey {
        switch self {
        case .red: "红"
        case .orange: "橙"
        case .yellow: "黄"
        case .green: "绿"
        case .cyan: "青"
        case .blue: "蓝"
        case .purple: "紫"
        case .monochrome: "黑/白"
        }
    }

    func color(for phase: ScenePanelPhase) -> Color {
        let rgb = rgb(for: phase)
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}

struct ScenePanelPalette {
    let phase: ScenePanelPhase
    let tint: ScenePanelColor

    var colorScheme: ColorScheme { phase == .light ? .light : .dark }
    var ink: Color { phase == .light ? Color(red: 0.055, green: 0.095, blue: 0.14) : Color(white: 0.96) }
    var color: Color { tint.color(for: phase) }
}

extension ScenePanelColors {
    func palette(for phase: ScenePanelPhase) -> ScenePanelPalette {
        ScenePanelPalette(phase: phase, tint: tint)
    }
}

extension View {
    func scenePanelSurface<S: Shape>(_ shape: S, palette: ScenePanelPalette) -> some View {
        modifier(TintedPanelGlass(shape: shape, palette: palette))
    }

    func taskPanelSurface(tint: Color? = nil, gradient: LinearGradient? = nil,
                          roundsTop: Bool = false, roundsBottom: Bool = false) -> some View {
        modifier(TaskPanelGlass(tint: tint, gradient: gradient, roundsTop: roundsTop, roundsBottom: roundsBottom))
    }
}

private struct TaskPanelGlass: ViewModifier {
    let tint: Color?
    let gradient: LinearGradient?
    let roundsTop: Bool
    let roundsBottom: Bool
    @Environment(\.panelGlassStyle) private var style

    func body(content: Content) -> some View {
        let top: CGFloat = roundsTop ? 14 : 0
        let bottom: CGFloat = roundsBottom ? 14 : 0
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                          bottomTrailingRadius: bottom, topTrailingRadius: top)
        let topSeamInset: CGFloat = roundsTop ? 0 : 0.5
        let bottomSeamInset: CGFloat = roundsBottom ? 0 : 0.5
        content
            .background {
                if let gradient {
                    shape.fill(gradient)
                }
            }
            // Trim only the outermost part of the native rim at each shared edge.
            .padding(.top, topSeamInset)
            .padding(.bottom, bottomSeamInset)
            .glassEffect(style.material(tint: tint), in: shape)
            .padding(.top, -topSeamInset)
            .padding(.bottom, -bottomSeamInset)
            .clipShape(TaskPanelSeamClip(clipsTop: !roundsTop, clipsBottom: !roundsBottom))
    }
}

private struct TaskPanelSeamClip: Shape {
    let clipsTop: Bool
    let clipsBottom: Bool

    func path(in rect: CGRect) -> Path {
        let overscan: CGFloat = 24
        let top = clipsTop ? rect.minY : rect.minY - overscan
        let bottom = clipsBottom ? rect.maxY : rect.maxY + overscan
        return Path(CGRect(x: rect.minX - overscan, y: top, width: rect.width + 2 * overscan, height: bottom - top))
    }
}

private struct TintedPanelGlass<S: Shape>: ViewModifier {
    let shape: S
    let palette: ScenePanelPalette
    @Environment(\.panelGlassStyle) private var style

    func body(content: Content) -> some View {
        content.glassEffect(style.tinted(palette.color), in: shape)
            .environment(\.colorScheme, palette.colorScheme)
    }
}

struct ScenePanelColorControls: View {
    @Binding var colors: ScenePanelColors
    @Environment(\.scenePanelPhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("亮暗配色").font(.subheadline.weight(.medium))
                Spacer()
                Text(phase == .light ? "当前亮色" : "当前暗色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(ScenePanelColor.allCases) { tint in
                    let selected = colors.tint == tint
                    Button { colors = ScenePanelColors(tint) } label: {
                        VStack(spacing: 3) {
                            VStack(spacing: 0) {
                                tint.color(for: .light)
                                tint.color(for: .dark)
                            }
                            .frame(width: 25, height: 25)
                            .clipShape(Circle())
                            .overlay {
                                Circle().strokeBorder(.primary.opacity(selected ? 0.85 : 0.22),
                                                      lineWidth: selected ? 1.5 : 1)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color(white: 0.12))
                                        .offset(x: 2, y: 2)
                                }
                            }
                            Text(tint.title)
                                .font(.caption2.weight(selected ? .semibold : .regular))
                        }
                        .frame(width: 29, height: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tint.title))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("panelColor.\(tint.rawValue)")
                }
            }
        }
    }
}
