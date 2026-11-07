import SwiftUI

struct SwissClockView: View {
    let progress: SwissClockProgress
    let palette: ScenePanelPalette

    private var ink: Color { palette.ink }
    private var colorScheme: ColorScheme { palette.colorScheme }

    private let red = Color(red: 0.89, green: 0.12, blue: 0.10)

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let redHand = SwissRedGlassHand(degrees: progress.redHandDegrees)
            ZStack {
                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    drawIndices(in: context, diameter: diameter)
                }
                .scenePanelSurface(Circle(), palette: palette)

                // Keep the tinted hand separate from the user-controlled dial
                // material, so its red tint never changes the clock body.
                // A translucent foreground tint keeps the thin hand readable
                // when the system dims the glass in an inactive window.
                redHand
                    .fill(red.opacity(0.42))
                    .glassEffect(.regular.tint(red), in: redHand)
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.30 : 0.24),
                        radius: max(0.75, diameter * 0.004),
                        x: diameter * 0.0015,
                        y: diameter * 0.006
                    )
                    .allowsHitTesting(false)

                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    drawHub(in: context, diameter: diameter)
                }
                .allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func drawIndices(in context: GraphicsContext, diameter: CGFloat) {
        for index in 0..<12 {
            var indexContext = context
            indexContext.rotate(by: .degrees(Double(index) * 30))
            let isQuarter = index.isMultiple(of: 3)
            let width = diameter * (isQuarter ? 0.0175 : 0.014)
            let length = diameter * (isQuarter ? 0.074 : 0.063)
            indexContext.fill(
                Path(roundedRect: CGRect(x: -width / 2, y: -diameter * 0.438, width: width, height: length), cornerRadius: diameter * 0.001),
                with: .color(ink)
            )
        }
    }

    private func drawHub(in context: GraphicsContext, diameter: CGFloat) {
        let hubRadius = diameter * 0.0155
        context.fill(
            Path(ellipseIn: CGRect(x: -hubRadius, y: -hubRadius, width: hubRadius * 2, height: hubRadius * 2)),
            with: .color(ink)
        )
        let capRadius = diameter * 0.0095
        let cap = Path(ellipseIn: CGRect(x: -capRadius, y: -capRadius, width: capRadius * 2, height: capRadius * 2))
        context.fill(cap, with: .color(Color(white: colorScheme == .dark ? 0.78 : 0.22)))
        context.stroke(cap, with: .color(.white.opacity(0.16)), lineWidth: max(0.4, diameter * 0.001))
    }
}

private struct SwissRedGlassHand: Shape {
    var degrees: Double

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let width = max(1, diameter * 0.0065)
        let stem = Path(roundedRect: CGRect(x: -width / 2, y: -diameter * 0.303, width: width, height: diameter * 0.3165), cornerRadius: width / 2)
        let tip = Path(ellipseIn: CGRect(x: -diameter * 0.022, y: -diameter * 0.325, width: diameter * 0.044, height: diameter * 0.044))

        // A continuous silhouette gives the stem and tip one native glass edge.
        return stem.union(tip)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .applying(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }
}
