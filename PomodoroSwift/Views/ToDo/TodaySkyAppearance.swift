import SwiftUI

struct TodaySkyAppearance {
    let sky: TodaySkyAstronomy.Sky

    private struct PaletteStop {
        let altitude: Double
        let top: Int
        let bottom: Int
    }

    func gradient(concentration: Double) -> LinearGradient {
        let horizon = sky.isMorning
            ? PaletteStop(altitude: 0, top: 0x80ACCD, bottom: 0xFFDBB6)
            : PaletteStop(altitude: 0, top: 0x7390C4, bottom: 0xF6B28C)
        let stops = [
            PaletteStop(altitude: -18, top: 0x1B2B51, bottom: 0x3B5481),
            PaletteStop(altitude: -12, top: 0x2B4374, bottom: 0x7286AF),
            PaletteStop(altitude: -6, top: 0x536FA6, bottom: 0xB6B4C4),
            horizon,
            PaletteStop(altitude: 12, top: 0x72B9DB, bottom: 0xF3E8BA),
            PaletteStop(altitude: 45, top: 0x55B7E6, bottom: 0xBEEAF6)
        ]
        let altitude = min(max(sky.sunAltitude, -18), 45)
        let upperIndex = stops.firstIndex { $0.altitude >= altitude } ?? (stops.count - 1)
        let lower = stops[max(0, upperIndex - 1)]
        let upper = stops[upperIndex]
        let span = upper.altitude - lower.altitude
        let progress = span > 0 ? (altitude - lower.altitude) / span : 0
        // At the default 50% concentration the original 24–36% opacity is preserved.
        let darkness = min(max(-altitude / 18, 0), 1)
        let opacity = (0.48 + 0.24 * darkness) * concentration
        return LinearGradient(
            colors: [
                blend(lower.top, upper.top, progress: progress).opacity(opacity),
                blend(lower.bottom, upper.bottom, progress: progress).opacity(opacity * 0.9)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func blend(_ lower: Int, _ upper: Int, progress: Double) -> Color {
        func channel(_ shift: Int) -> Double {
            let start = Double((lower >> shift) & 0xFF)
            let end = Double((upper >> shift) & 0xFF)
            return (start + (end - start) * progress) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}

struct TodaySkyBodies: View {
    let sky: TodaySkyAstronomy.Sky

    var body: some View {
        Canvas { context, size in
            guard size.width > 24, size.height > 12 else { return }
            if let point = sky.sunTrack {
                drawSun(in: context, at: center(for: point, in: size))
            }
            if let point = sky.moonTrack {
                var moonlight = context
                let darkness = min(max((-sky.sunAltitude - 2) / 10, 0), 1)
                moonlight.opacity = 0.74 + 0.26 * darkness
                drawMoon(in: moonlight, at: center(for: point, in: size), darkness: darkness)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(visibleBodies)
    }

    private func center(for point: TodaySkyAstronomy.TrackPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width - 12 - (size.width - 24) * point.progress,
            y: size.height - (size.height - 12) * pow(point.height, 1.4)
        )
    }

    private var visibleBodies: String {
        switch (sky.sunTrack, sky.moonTrack) {
        case (.some, .some): "太阳与\(moonLabel)"
        case (.some, nil): "太阳"
        case (nil, .some): moonLabel
        case (nil, nil): sky.starVisibility > 0 ? "夜空" : "天空"
        }
    }

    private var moonLabel: String {
        if sky.moon.isFull { return "满月" }
        let illumination = sky.moon.illumination.formatted(.percent.precision(.fractionLength(0)))
        return sky.moon.isWaxing ? "盈月，照亮 \(illumination)" : "亏月，照亮 \(illumination)"
    }

    private func drawSun(in context: GraphicsContext, at center: CGPoint) {
        let radius: CGFloat = 6.4
        let gold = Color(red: 1, green: 0.81, blue: 0.46)
        drawGlow(in: context, at: center, radius: 14, color: gold, strength: 0.52)
        context.fill(disk(at: center, radius: radius), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 1, green: 0.99, blue: 0.94), location: 0),
                .init(color: Color(red: 1, green: 0.96, blue: 0.79), location: 0.68),
                .init(color: Color(red: 0.98, green: 0.84, blue: 0.58), location: 1)
            ]),
            center: CGPoint(x: center.x - 0.7, y: center.y - 0.9), startRadius: 0, endRadius: radius + 1.1
        ))
    }

    private func drawMoon(in context: GraphicsContext, at center: CGPoint, darkness: Double) {
        let radius: CGFloat = 7.5
        let outline = disk(at: center, radius: radius)
        if darkness > 0 {
            let moonlight = Color(red: 0.82, green: 0.9, blue: 1)
            drawGlow(in: context, at: center, radius: 14, color: moonlight,
                     strength: (0.06 + 0.30 * sky.moon.illumination) * darkness)
            if !sky.moon.isFull {
                let earthshine = Color(red: 0.59, green: 0.68, blue: 0.77)
                context.fill(outline, with: .radialGradient(
                    Gradient(colors: [earthshine.opacity(0.22 * darkness), earthshine.opacity(0.07 * darkness)]),
                    center: center, startRadius: 0, endRadius: radius
                ))
            }
        }

        var illuminated = context
        illuminated.clip(to: sky.moon.isFull ? outline : illuminatedLimb(center: center, radius: radius))
        let lightSide: CGFloat = sky.moon.isWaxing ? 1 : -1
        illuminated.fill(outline, with: .radialGradient(
            Gradient(colors: [Color(red: 0.99, green: 0.99, blue: 0.95),
                              Color(red: 0.79, green: 0.85, blue: 0.90)]),
            center: CGPoint(x: center.x + 2 * lightSide, y: center.y - 2.2),
            startRadius: 0, endRadius: radius + 2.5
        ))
        var shaded = illuminated
        shaded.addFilter(.blur(radius: 0.25))
        let maria = Self.lunarMaria.applying(CGAffineTransform(
            a: radius, b: 0, c: 0, d: radius, tx: center.x, ty: center.y
        ))
        shaded.fill(maria, with: .color(Color(red: 0.40, green: 0.46, blue: 0.52).opacity(0.34)))
    }

    // Stylized outlines of the darker lunar plains, in unit-disk coordinates.
    private static let lunarMaria = Path { path in
        path.move(to: CGPoint(x: -0.63, y: -0.49))
        path.addQuadCurve(to: CGPoint(x: -0.27, y: -0.65), control: CGPoint(x: -0.49, y: -0.69))
        path.addQuadCurve(to: CGPoint(x: -0.10, y: -0.38), control: CGPoint(x: -0.05, y: -0.59))
        path.addQuadCurve(to: CGPoint(x: -0.40, y: -0.12), control: CGPoint(x: -0.14, y: -0.23))
        path.addQuadCurve(to: CGPoint(x: -0.33, y: 0.21), control: CGPoint(x: -0.49, y: 0.02))
        path.addQuadCurve(to: CGPoint(x: -0.62, y: 0.33), control: CGPoint(x: -0.49, y: 0.39))
        path.addQuadCurve(to: CGPoint(x: -0.63, y: -0.49), control: CGPoint(x: -0.77, y: 0.02))
        path.closeSubpath()

        path.move(to: CGPoint(x: 0.05, y: -0.47))
        path.addQuadCurve(to: CGPoint(x: 0.39, y: -0.40), control: CGPoint(x: 0.20, y: -0.62))
        path.addQuadCurve(to: CGPoint(x: 0.44, y: -0.22), control: CGPoint(x: 0.48, y: -0.34))
        path.addQuadCurve(to: CGPoint(x: 0.56, y: 0.10), control: CGPoint(x: 0.67, y: -0.07))
        path.addQuadCurve(to: CGPoint(x: 0.19, y: 0.04), control: CGPoint(x: 0.45, y: 0.23))
        path.addQuadCurve(to: CGPoint(x: 0.05, y: -0.47), control: CGPoint(x: -0.04, y: -0.18))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: 0.57, y: -0.39, width: 0.20, height: 0.14))
        path.addEllipse(in: CGRect(x: -0.13, y: 0.30, width: 0.25, height: 0.13))
    }

    private func illuminatedLimb(center: CGPoint, radius: CGFloat) -> Path {
        let side: CGFloat = sky.moon.isWaxing ? 1 : -1
        let terminator = CGFloat(1 - 2 * sky.moon.illumination)
        let tangent: CGFloat = 0.55228475
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * side * radius, y: center.y + y * radius)
        }
        var path = Path()
        path.move(to: point(0, -1))
        path.addCurve(to: point(1, 0), control1: point(tangent, -1), control2: point(1, -tangent))
        path.addCurve(to: point(0, 1), control1: point(1, tangent), control2: point(tangent, 1))
        path.addCurve(to: point(terminator, 0), control1: point(terminator * tangent, 1),
                      control2: point(terminator, tangent))
        path.addCurve(to: point(0, -1), control1: point(terminator, -tangent),
                      control2: point(terminator * tangent, -1))
        path.closeSubpath()
        return path
    }
}

struct TodaySkyStars: View {
    enum Area {
        case header, rim
    }

    private struct Star {
        let area: Area
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat

        init(_ area: Area, _ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) {
            self.area = area
            self.x = x
            self.y = y
            self.diameter = diameter
        }
    }

    // The first stars are the brightest. Fewer stars use a prefix of this fixed field.
    private static let field: [Star] = [
        Star(.header, 0.65, 9, 2.5), Star(.rim, 0.81, 7, 2.3),
        Star(.header, 0.31, 19, 1.6), Star(.rim, 0.57, 41, 1.6),
        Star(.header, 0.89, 17, 1.8), Star(.rim, 0.25, 7, 1.9),
        Star(.header, 0.16, 8, 1.4), Star(.header, 0.76, 22, 1.2),
        Star(.rim, 0.94, 36, 1.6), Star(.header, 0.46, 11, 1.2),
        Star(.rim, 0.43, 5, 1.0), Star(.header, 0.56, 21, 1.0),
        Star(.rim, 0.23, 40, 1.1), Star(.header, 0.96, 5, 1.0),
        Star(.rim, 0.87, 41, 1.2), Star(.header, 0.08, 21, 1.0),
        Star(.rim, 0.06, 34, 1.1), Star(.rim, 0.67, 7, 1.0)
    ]

    let sky: TodaySkyAstronomy.Sky
    let area: Area

    var body: some View {
        Canvas { context, size in
            guard sky.starVisibility > 0, size.width >= (area == .header ? 22 : 10) else { return }
            for star in Self.field.prefix(sky.moon.starCount) where star.area == area {
                guard star.y + star.diameter < size.height else { continue }
                let center = CGPoint(x: size.width * star.x, y: star.y)
                let brightness = min(1, 0.32 + star.diameter * 0.25) * sky.starVisibility
                let halo = Color(red: 0.63, green: 0.80, blue: 1)
                drawGlow(in: context, at: center, radius: star.diameter * 1.65, color: halo, strength: brightness * 0.70)
                context.fill(disk(at: center, radius: star.diameter * 0.36),
                             with: .color(Color(red: 0.95, green: 0.98, blue: 1).opacity(brightness)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private func disk(at center: CGPoint, radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                           width: radius * 2, height: radius * 2))
}

private func drawGlow(in context: GraphicsContext, at center: CGPoint, radius: CGFloat,
                      color: Color, strength: Double) {
    context.fill(disk(at: center, radius: radius), with: .radialGradient(
        Gradient(stops: [
            .init(color: color.opacity(strength), location: 0),
            .init(color: color.opacity(strength * 0.44), location: 0.48),
            .init(color: color.opacity(strength * 0.08), location: 0.78),
            .init(color: color.opacity(0), location: 1)
        ]),
        center: center, startRadius: 0, endRadius: radius
    ))
}
