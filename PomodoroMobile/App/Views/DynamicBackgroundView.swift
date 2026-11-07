import SwiftUI

struct DynamicBackgroundView: View, Equatable {
    let sky: TodaySkyAstronomy.Sky

    var body: some View {
        Canvas(opaque: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }
            LakeScene(context: context, size: size, sky: sky).draw()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LakeScene {
    let context: GraphicsContext
    let size: CGSize
    let sky: TodaySkyAstronomy.Sky

    private let horizon: CGFloat = 0.56
    private let moonlightColor = Color(red: 0.73, green: 0.86, blue: 1)
    private var scale: CGFloat { min(size.width, size.height) }

    private var lightX: CGFloat {
        if let sun = sky.sunTrack { return 0.86 - sun.progress * 0.72 }
        return sky.isMorning ? 0.86 : 0.14
    }

    private var lightY: CGFloat {
        horizon - (sky.sunTrack?.height ?? 0) * 0.42
    }

    private var daylight: Double { fade((sky.sunAltitude + 8) / 13) }

    private var moonlight: (x: CGFloat, strength: Double)? {
        guard let moon = sky.moonTrack else { return nil }
        let darkness = fade((-sky.sunAltitude - 3) / 14)
        let strength = darkness * fade(moon.height / 0.25) * pow(sky.moon.illumination, 1.5)
        guard strength > 0 else { return nil }
        return (0.86 - moon.progress * 0.72, strength)
    }

    func draw() {
        let palette = Palette(sky: sky)
        drawSky(palette)
        drawWater(palette)
        drawMountains(palette)
        drawMorningMist(palette)
        drawShore(palette)
        drawGrain()
        fill(rect(0, 0, 1, 1), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.34), .init(color: .black.opacity(0.23), location: 1)]),
            center: point(0.5, 0.42), startRadius: 0, endRadius: max(size.width, size.height) * 0.66
        ))
    }

    private func drawSky(_ palette: Palette) {
        fill(rect(0, 0, 1, horizon), with: vertical([palette.sky, palette.haze], from: 0, to: horizon))

        let afterglow = fade((sky.sunAltitude + 15) / 18) * (1 - fade((sky.sunAltitude - 6) / 29))
        fill(rect(0, 0, 1, horizon), with: .radialGradient(
            Gradient(colors: [palette.light.opacity(0.6 * afterglow), palette.light.opacity(0.13 * afterglow), .clear]),
            center: point(lightX, min(lightY, horizon - 0.025)), startRadius: 0, endRadius: scale * 0.67
        ))

        if sky.starVisibility > 0 {
            let visibility = sky.starVisibility * (1 - (moonlight?.strength ?? 0) * 0.4)
            for index in 0..<94 {
                let x = noise(index * 3)
                let y = 0.025 + noise(index * 3 + 1) * 0.49
                let brightness = noise(index * 3 + 2)
                let radius = scale * (0.00045 + brightness * 0.00105)
                fill(disk(at: point(x, y), radius: radius),
                     .white.opacity(visibility * (0.15 + 0.68 * brightness) * (1 - y)))
            }
        }

        if sky.sunTrack != nil {
            let center = point(lightX, lightY)
            let radius = scale * 0.017
            let visibility = fade((sky.sunAltitude + 0.5) / 2.0)
            fill(disk(at: center, radius: radius * 4.5), with: .radialGradient(
                Gradient(colors: [palette.light.opacity(0.8 * visibility), palette.light.opacity(0.24 * visibility), .clear]),
                center: center, startRadius: 0, endRadius: radius * 4.5
            ))
            fill(disk(at: center, radius: radius), palette.light.opacity(visibility))
            // Keep the sun's disk visible against the warm halo.
            fill(disk(at: center, radius: radius * 0.82), .white.opacity(0.62 * visibility))
        }

        if let moon = sky.moonTrack {
            drawMoon(at: point(0.86 - moon.progress * 0.72, horizon - moon.height * 0.42))
        }
    }

    private func drawMoon(at center: CGPoint) {
        let radius = scale * 0.013
        let glow = fade((-sky.sunAltitude + 7) / 20)
        let moonlight = Color(red: 0.80, green: 0.89, blue: 1)
        fill(disk(at: center, radius: radius * 4), with: .radialGradient(
            Gradient(colors: [moonlight.opacity(0.27 * glow * sky.moon.illumination), .clear]),
            center: center, startRadius: 0, endRadius: radius * 4
        ))

        let side: CGFloat = sky.moon.isWaxing ? 1 : -1
        let terminator = side * (1 - 2 * sky.moon.illumination)
        var crescent = Path()
        for step in 0...24 {
            let angle = CGFloat(step) / 24 * .pi
            let p = CGPoint(x: center.x + side * radius * sin(angle), y: center.y - radius * cos(angle))
            if step == 0 { crescent.move(to: p) } else { crescent.addLine(to: p) }
        }
        for step in (0...24).reversed() {
            let angle = CGFloat(step) / 24 * .pi
            crescent.addLine(to: CGPoint(x: center.x + terminator * radius * sin(angle), y: center.y - radius * cos(angle)))
        }
        crescent.closeSubpath()
        fill(crescent, moonlight.opacity(0.18 + 0.65 * glow))
    }

    private func drawWater(_ palette: Palette) {
        let water = rect(0, horizon, 1, 1 - horizon)
        fill(water, with: vertical([palette.haze, palette.water, palette.near], from: horizon - 0.09, to: 1.08))
        let reflection = point(lightX, horizon - 0.04)
        fill(water, with: .radialGradient(
            Gradient(colors: [palette.light.opacity(0.35 * fade((sky.sunAltitude + 13) / 14)), .clear]),
            center: reflection, startRadius: 0, endRadius: scale * 0.54
        ))

        var rippleShade = Path()
        var rippleLight = Path()
        for index in 0..<220 {
            let depth = pow(noise(index * 4 + 912), 1.8)
            let y = horizon + depth * (1 - horizon)
            let x = noise(index * 4 + 913)
            let length = (0.007 + depth * 0.065) * (0.15 + noise(index * 4 + 914) * 0.85)
            let bright = noise(index * 4 + 915) > 0.49
            let start = point(x - length / 2, y)
            let end = point(x + length / 2, y)
            if bright {
                rippleLight.move(to: start)
                rippleLight.addLine(to: end)
            } else {
                rippleShade.move(to: start)
                rippleShade.addLine(to: end)
            }
        }
        context.stroke(rippleShade, with: .color(palette.near.opacity(0.22)), style: StrokeStyle(lineWidth: scale * 0.0019, lineCap: .round))
        context.stroke(rippleLight, with: .color(palette.haze.opacity(0.26)), style: StrokeStyle(lineWidth: scale * 0.0012, lineCap: .round))

        if daylight > 0 {
            let lowSun = 1 - fade(sky.sunAltitude / 34)
            drawWaterGlints(x: lightX, color: palette.light, strength: daylight * (0.38 + 0.34 * lowSun), seed: 1500)
        }

        if let moonlight {
            fill(water, with: .radialGradient(
                Gradient(colors: [moonlightColor.opacity(0.19 * moonlight.strength), .clear]),
                center: point(moonlight.x, horizon + 0.13), startRadius: 0, endRadius: scale * 0.33
            ))
            drawWaterGlints(x: moonlight.x, color: moonlightColor, strength: moonlight.strength, seed: 2100)
        }
    }

    private func drawWaterGlints(x: CGFloat, color: Color, strength: Double, seed: Int) {
        for index in 0..<64 {
            let sample = seed + index * 4
            let depth = pow(noise(sample), 1.45)
            let y = horizon + 0.017 + depth * 0.36
            let spread = 0.016 + depth * 0.10
            let center = x + (noise(sample + 1) - 0.5) * spread
            let width = (0.003 + depth * 0.033) * (0.25 + noise(sample + 2) * 0.75)
            let energy = (0.18 + noise(sample + 3) * 0.46) * (1 - depth * 0.54)
            var glint = Path()
            glint.move(to: point(center - width / 2, y))
            glint.addLine(to: point(center + width / 2, y))
            context.stroke(glint, with: .color(color.opacity(strength * energy)),
                           style: StrokeStyle(lineWidth: max(0.6, scale * (0.0011 + depth * 0.0018)), lineCap: .round))
        }
    }

    private func drawMountains(_ palette: Palette) {
        for (index, ridge) in Self.ridges.enumerated() {
            let reflectedRidge = ridge.map { (x, y) in (x, horizon + (horizon - y) * 0.57) }
            let reflection = polygon(reflectedRidge + [(1, horizon), (0, horizon)])
            var softReflection = context
            softReflection.addFilter(.blur(radius: scale * 0.006))
            softReflection.fill(reflection, with: .color(palette.near.opacity(0.09 + 0.035 * Double(index))))

            let slope = polygon(ridge + [(1, horizon + 0.004), (0, horizon + 0.004)])
            let top = index == 0 ? palette.far : palette.near
            let bottom = index == 0 ? palette.haze : palette.far
            fill(slope, with: vertical([top, bottom], from: 0.31, to: 0.64))
        }

        let faces: [[(CGFloat, CGFloat)]] = [
            [(0.035, 0.427), (0.088, 0.389), (0.128, 0.424), (0.151, 0.431), (0.185, 0.459), (0.133, 0.446), (0.105, 0.427)],
            [(0.214, 0.462), (0.294, 0.394), (0.318, 0.404), (0.374, 0.456), (0.335, 0.440), (0.310, 0.422), (0.271, 0.427)],
            [(0.696, 0.469), (0.771, 0.391), (0.791, 0.417), (0.814, 0.425), (0.846, 0.463), (0.778, 0.434), (0.751, 0.440)]
        ]
        for face in faces {
            fill(polygon(face), palette.haze.opacity(0.24))
        }

        var shore = Path()
        shore.move(to: point(0.16, horizon + 0.009))
        shore.addLine(to: point(0.85, horizon + 0.009))
        context.stroke(shore, with: .color(palette.haze.opacity(0.26)), lineWidth: scale * 0.0015)
    }

    private func drawMorningMist(_ palette: Palette) {
        guard sky.isMorning else { return }
        let strength = fade((sky.sunAltitude + 12) / 11) * (1 - fade((sky.sunAltitude - 1) / 13))
        guard strength > 0 else { return }

        var mist = context
        mist.addFilter(.blur(radius: scale * 0.012))
        let drift = (lightX - 0.7) * 0.18
        let wisps: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, opacity: Double)] = [
            (-0.05, 0.545, 0.82, 0.039, 0.28),
            (0.20, 0.568, 0.86, 0.048, 0.30),
            (0.03, 0.612, 0.58, 0.030, 0.18)
        ]
        for wisp in wisps {
            let bounds = CGRect(x: (wisp.x + drift) * size.width, y: wisp.y * size.height,
                                width: wisp.width * size.width, height: wisp.height * size.height)
            mist.fill(Path(ellipseIn: bounds), with: .color(palette.haze.opacity(wisp.opacity * strength)))
        }
    }

    private func drawShore(_ palette: Palette) {
        let leftBank = polygon([(0, 0.70), (0.062, 0.729), (0.119, 0.771), (0.204, 0.797),
                                (0.264, 0.847), (0.319, 0.897), (0.39, 1), (0, 1)])
        let rightBank = polygon([(1, 0.661), (0.94, 0.692), (0.898, 0.736), (0.819, 0.789),
                                 (0.778, 0.844), (0.71, 0.909), (0.68, 1), (1, 1)])
        var land = leftBank
        land.addPath(rightBank)
        let bank = vertical([palette.near, palette.ink], from: 0.68, to: 1)
        fill(land, with: bank)

        if daylight > 0 {
            fill(land, with: .radialGradient(
                Gradient(colors: [palette.light.opacity(0.31 * daylight), palette.light.opacity(0.08 * daylight), .clear]),
                center: point(lightX, 0.76), startRadius: 0, endRadius: max(scale * 0.70, size.width * 0.45)
            ))
        }
        if let moonlight {
            fill(land, with: .radialGradient(
                Gradient(colors: [moonlightColor.opacity(0.20 * moonlight.strength), .clear]),
                center: point(moonlight.x, 0.80), startRadius: 0, endRadius: max(scale * 0.49, size.width * 0.25)
            ))
        }

        var trees = Path()
        var shadows = Path()
        let stretch = 1 - fade((sky.sunAltitude + 1) / 43)
        let shadowDirection = (0.5 - lightX) * size.height / size.width
        for index in 0..<35 {
            let distance = noise(index * 3 + 201)
            let onLeft = index.isMultiple(of: 2)
            let x = onLeft ? distance * 0.21 - 0.018 : 1.016 - distance * 0.21
            let y = 0.734 + distance * 0.12 - (onLeft ? 0 : 0.046)
            let height = (0.033 + noise(index * 3 + 202) * 0.106) * (1 - distance * 0.72)
            let halfWidth = height * (0.13 + noise(index * 3 + 203) * 0.085) * size.height / size.width
            if daylight > 0 {
                let tipX = x + shadowDirection * height * (0.45 + 2.3 * stretch)
                let tipY = y + height * (0.19 + 0.85 * stretch)
                shadows.addPath(polygon([(x - halfWidth * 0.55, y), (x + halfWidth * 0.55, y), (tipX, tipY)]))
            }
            trees.addPath(polygon([(x, y - height), (x + halfWidth * 0.6, y - height * 0.52),
                                   (x + halfWidth * 0.35, y - height * 0.55), (x + halfWidth, y - height * 0.19),
                                   (x + halfWidth * 0.45, y - height * 0.24), (x + halfWidth * 0.12, y),
                                   (x - halfWidth * 0.12, y), (x - halfWidth * 0.12, y - height * 0.25),
                                   (x - halfWidth, y - height * 0.19), (x - halfWidth * 0.36, y - height * 0.58),
                                   (x - halfWidth * 0.62, y - height * 0.51)]))
        }
        if daylight > 0 {
            var ground = context
            ground.clip(to: land)
            ground.addFilter(.blur(radius: scale * 0.0018))
            ground.fill(shadows, with: .color(.black.opacity(daylight * (0.23 + 0.17 * stretch))))
        }
        fill(trees, with: vertical([palette.near, palette.ink], from: 0.57, to: 0.85))

        let lamps = [(0.085, 0.748), (0.13, 0.782), (0.174, 0.797), (0.207, 0.814)]
        let glow = fade((-sky.sunAltitude + 2) / 12)
        for (x, y) in lamps {
            let center = point(x, y)
            let light = Color(red: 1, green: 0.68, blue: 0.34)
            fill(disk(at: center, radius: scale * 0.021), with: .radialGradient(
                Gradient(colors: [light.opacity(0.66 * glow), .clear]),
                center: center, startRadius: 0, endRadius: scale * 0.021
            ))
            fill(disk(at: center, radius: scale * 0.0018), light.opacity(glow))
        }
    }

    private func drawGrain() {
        var grain = Path()
        for index in 0..<4400 {
            let p = point(noise(index * 2 + 6000), noise(index * 2 + 6001))
            let dot = max(scale * 0.0011, 0.6)
            grain.addRect(CGRect(x: p.x, y: p.y, width: dot, height: dot))
        }
        fill(grain, .white.opacity(0.11))
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
        Path(CGRect(origin: point(x, y), size: CGSize(width: width * size.width, height: height * size.height)))
    }

    private func disk(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: point(first.0, first.1))
            for (x, y) in points.dropFirst() { path.addLine(to: point(x, y)) }
            path.closeSubpath()
        }
    }

    private func fill(_ path: Path, _ color: Color) { fill(path, with: .color(color)) }

    private func fill(_ path: Path, with shading: GraphicsContext.Shading) { context.fill(path, with: shading) }

    private func vertical(_ colors: [Color], from top: CGFloat, to bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: point(0, top), endPoint: point(0, bottom))
    }

    private func noise(_ seed: Int) -> CGFloat {
        var bits = UInt32(seed) &+ 0x9E3779B9
        bits = (bits ^ (bits >> 16)) &* 0x85EBCA6B
        bits = (bits ^ (bits >> 13)) &* 0xC2B2AE35
        return CGFloat((bits ^ (bits >> 16)) & 0x00FFFFFF) / 0x01000000
    }

    private static let ridges: [[(CGFloat, CGFloat)]] = [
        [(0, 0.445), (0.04, 0.426), (0.088, 0.389), (0.151, 0.431), (0.20, 0.468), (0.244, 0.434),
         (0.294, 0.394), (0.318, 0.404), (0.382, 0.467), (0.442, 0.485), (0.485, 0.504),
         (0.535, 0.48), (0.602, 0.466), (0.637, 0.437), (0.692, 0.474), (0.735, 0.429),
         (0.771, 0.391), (0.814, 0.425), (0.866, 0.474), (0.931, 0.417), (0.974, 0.447), (1, 0.442)],
        [(0, 0.46), (0.044, 0.444), (0.093, 0.452), (0.135, 0.482), (0.198, 0.502), (0.23, 0.507),
         (0.291, 0.535), (0.353, 0.539), (0.412, 0.551), (0.47, 0.555), (0.54, 0.552), (0.6, 0.549),
         (0.653, 0.535), (0.701, 0.517), (0.746, 0.505), (0.813, 0.505), (0.856, 0.49), (0.9, 0.457),
         (0.963, 0.429), (1, 0.443)]
    ]
}

private func fade(_ fraction: Double) -> Double {
    let t = min(max(fraction, 0), 1)
    return t * t * (3 - 2 * t)
}

private struct Palette {
    let sky: Color
    let haze: Color
    let water: Color
    let far: Color
    let near: Color
    let ink: Color
    let light: Color

    init(sky: TodaySkyAstronomy.Sky) {
        let twilight: [Int] = sky.isMorning
            ? [0x486F94, 0xEDAD89, 0x657D92, 0x746E86, 0x304C64, 0x1A2937, 0xFFDEA9]
            : [0x545C90, 0xF09874, 0x6C6A89, 0x836F88, 0x3D405E, 0x24263C, 0xFFD09C]
        let stops: [(altitude: Double, colors: [Int])] = [
            (-18, [0x09162D, 0x243E60, 0x17334F, 0x253855, 0x121F36, 0x091323, 0xACCCF8]),
            (0, twilight),
            (14, [0x4E8CBA, 0xD5C8A5, 0x60939D, 0x778E9D, 0x355A64, 0x20333B, 0xFFF0BD]),
            (43, [0x5595BF, 0xCFDFD7, 0x6496A4, 0x718D99, 0x345C61, 0x1D3739, 0xFFF9D6])
        ]
        let altitude = min(max(sky.sunAltitude, -18), 43)
        let upperIndex = stops.dropFirst().firstIndex { $0.altitude >= altitude } ?? stops.count - 1
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let t = fade((altitude - lower.altitude) / (upper.altitude - lower.altitude))

        func color(_ index: Int) -> Color {
            func channel(_ shift: Int) -> Double {
                let a = Double((lower.colors[index] >> shift) & 255)
                let b = Double((upper.colors[index] >> shift) & 255)
                return (a + (b - a) * t) / 255
            }
            return Color(red: channel(16), green: channel(8), blue: channel(0))
        }

        self.sky = color(0)
        haze = color(1)
        water = color(2)
        far = color(3)
        near = color(4)
        ink = color(5)
        light = color(6)
    }
}
