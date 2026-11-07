import SwiftUI

struct DynamicBackgroundView: View, Equatable {
    struct Frame: Equatable {
        let theme: BackgroundTheme
        let sky: TodaySkyAstronomy.Sky
        let date: Date
        let schedule: LakeDaySchedule?
    }

    let frame: Frame
    let advancesMotion: Bool

    var body: some View {
        ZStack {
            if let schedule = frame.schedule {
                let motion = schedule.motion(at: frame.date)
                let daylight = LakeDaySchedule.detailVisibility(sunAltitude: frame.sky.sunAltitude)
                let waterTone = Palette(sky: frame.sky, lakeside: true).water
                LakeSceneryView(sky: frame.sky, windowLight: schedule.windowLight(at: frame.date))
                    .equatable()
                if advancesMotion && (motion.boat != nil
                    || (daylight > 0 && (motion.ducks != nil || motion.walker != nil))
                    || motion.lanternVisitor != nil) {
                    TimelineView(.periodic(from: frame.date, by: 5)) { tick in
                        LakeMotionView(motion: schedule.motion(at: max(tick.date, frame.date)),
                                       daylight: daylight, waterTone: waterTone)
                            .equatable()
                    }
                } else {
                    LakeMotionView(motion: motion, daylight: daylight, waterTone: waterTone).equatable()
                }
            } else if frame.theme == .mistLight {
                MistLightView(sky: frame.sky).equatable()
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LakeSceneryView: View, Equatable {
    let sky: TodaySkyAstronomy.Sky
    let windowLight: Double

    var body: some View {
        Canvas(opaque: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }
            LakeScene(context: context, size: size, sky: sky).draw(windowLight: windowLight)
        }
    }
}

private struct MistLightView: View, Equatable {
    let sky: TodaySkyAstronomy.Sky

    var body: some View {
        Canvas(opaque: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let palette = Palette(sky: sky)
            let light = sky.sunTrack.map { 0.83 - $0.progress * 0.66 } ?? (sky.isMorning ? 0.83 : 0.17)
            let twilight = fade((sky.sunAltitude + 15) / 15) * (1 - fade(sky.sunAltitude / 27))
            let daylight = fade((sky.sunAltitude + 10) / 25)
            let x = size.width * (0.5 + (light - 0.5) * max(twilight, daylight))
            let bounds = Path(CGRect(origin: .zero, size: size))
            context.fill(bounds, with: .linearGradient(
                Gradient(colors: [palette.sky, palette.water, palette.near]),
                startPoint: .zero, endPoint: CGPoint(x: size.width * 0.35, y: size.height)
            ))

            var wash = context
            wash.translateBy(x: x, y: size.height * 0.63)
            wash.rotate(by: .degrees(-11))
            let length = max(size.width, size.height)
            wash.scaleBy(x: length, y: size.height * 0.36)
            let field = Path(CGRect(x: -1, y: -1, width: 2, height: 2))
            wash.fill(field, with: .radialGradient(
                Gradient(stops: [.init(color: palette.haze.opacity(0.49 + 0.20 * daylight), location: 0),
                                 .init(color: palette.haze.opacity(0.17), location: 0.50),
                                 .init(color: .clear, location: 1)]),
                center: .zero, startRadius: 0, endRadius: 1
            ))
            wash.scaleBy(x: 0.77, y: 0.43)
            wash.fill(field, with: .radialGradient(
                Gradient(colors: [palette.light.opacity(0.34 * twilight + 0.07 * daylight), .clear]),
                center: .zero, startRadius: 0, endRadius: 1
            ))

            if let moon = sky.moonTrack {
                let glow = fade((-sky.sunAltitude - 5) / 13) * sky.moon.illumination * fade(moon.height / 0.3)
                context.fill(bounds, with: .radialGradient(
                    Gradient(colors: [Color(red: 0.68, green: 0.78, blue: 0.96).opacity(0.24 * glow), .clear]),
                    center: CGPoint(x: size.width * (0.82 - moon.progress * 0.64), y: size.height * 0.31),
                    startRadius: 0, endRadius: length * 0.57
                ))
            }
        }
    }
}

private struct LakeScene {
    let context: GraphicsContext
    let size: CGSize
    let sky: TodaySkyAstronomy.Sky

    private let horizon = LakeLayout.horizon
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
    private var highSun: Double { fade(sky.sunAltitude / 34) }
    private var shadowStretch: Double { 1 - fade((sky.sunAltitude + 1) / 43) }

    private var moonlight: (x: CGFloat, strength: Double)? {
        guard let moon = sky.moonTrack else { return nil }
        let darkness = fade((-sky.sunAltitude - 3) / 14)
        let strength = darkness * fade(moon.height / 0.25) * pow(sky.moon.illumination, 1.5)
        guard strength > 0 else { return nil }
        return (0.86 - moon.progress * 0.72, strength)
    }

    func draw(windowLight: Double) {
        let palette = Palette(sky: sky, lakeside: true)
        drawSky(palette)
        drawWater(palette)
        drawMountains(palette)
        drawMorningMist(palette)
        drawShore(palette)
        LakeObjects(context: context, layout: LakeLayout(size: size), daylight:
            LakeDaySchedule.detailVisibility(sunAltitude: sky.sunAltitude))
            .drawStructures(bankTone: palette.near, windowLight: windowLight, moonlight: moonlight?.strength ?? 0,
                            sunX: lightX, shadowStretch: shadowStretch)
        drawGrain()
        fill(rect(0, 0, 1, 1), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.34), .init(color: .black.opacity(0.23), location: 1)]),
            center: point(0.5, 0.42), startRadius: 0, endRadius: max(size.width, size.height) * 0.66
        ))
    }

    private func drawSky(_ palette: Palette) {
        fill(rect(0, 0, 1, horizon), with: vertical([palette.sky, palette.haze], from: 0, to: horizon))

        let afterglow = fade((sky.sunAltitude + 9) / 12) * (1 - fade((sky.sunAltitude - 6) / 29))
        let daylightGlow = 1 - 0.7 * highSun
        fill(rect(0, 0, 1, horizon), with: .radialGradient(
            Gradient(colors: [palette.light.opacity(0.27 * daylight * daylightGlow + 0.53 * afterglow),
                              palette.light.opacity(0.10 * daylight * daylightGlow + 0.10 * afterglow),
                              palette.light.opacity(0)]),
            center: point(lightX, min(lightY, horizon - 0.025)), startRadius: 0, endRadius: scale * 0.67
        ))
        if daylight > 0 {
            var wisps = context
            wisps.addFilter(.blur(radius: scale * 0.012))
            wisps.drawLayer { clouds in
                for index in 0..<8 {
                    let x = noise(420 + index * 4)
                    let y = 0.13 + noise(421 + index * 4) * 0.30
                    let width = 0.12 + noise(422 + index * 4) * 0.24
                    let opacity = 0.09 + noise(423 + index * 4) * 0.16
                    let bounds = CGRect(x: (x - width / 2) * size.width, y: y * size.height,
                                        width: width * size.width, height: (0.008 + width * 0.045) * size.height)
                    clouds.fill(Path(ellipseIn: bounds), with: .color(palette.haze.opacity(opacity * daylight)))
                }
            }
        }

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
            let halo = visibility * (1 - 0.35 * highSun)
            // The glow can brighten the sky but must never shade it.
            var glow = context
            glow.blendMode = .screen
            let outerRadius = radius * 4.6
            glow.fill(disk(at: center, radius: outerRadius), with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.light.opacity(0.68 * halo), location: 0),
                    .init(color: palette.light.opacity(0.25 * halo), location: 0.40),
                    .init(color: palette.light.opacity(0.04 * halo), location: 0.75),
                    .init(color: palette.light.opacity(0), location: 1)
                ]),
                center: center, startRadius: 0, endRadius: outerRadius
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
        let waterAfterglow = fade((sky.sunAltitude + 13) / 14)
        let reflection = point(lightX, horizon - 0.04)
        fill(water, with: .radialGradient(
            Gradient(colors: [palette.light.opacity(waterAfterglow * (0.41 - 0.25 * highSun)), .clear]),
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
        context.stroke(rippleShade, with: .color(palette.near.opacity(0.18)), style: StrokeStyle(lineWidth: scale * 0.0016, lineCap: .round))
        context.stroke(rippleLight, with: .color(palette.haze.opacity(0.25)), style: StrokeStyle(lineWidth: scale * 0.0011, lineCap: .round))

        if waterAfterglow > 0 {
            let lowSun = 1 - highSun
            drawWaterGlints(x: lightX, color: palette.light, strength: waterAfterglow * (0.20 + 0.31 * lowSun), seed: 1500)
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
        for (index, silhouette) in Self.ridges.enumerated() {
            let ridge = contour(silhouette, seed: 2400 + index * 200)
            let reflectedRidge = ridge.map { (x, y) in (x, horizon + (horizon - y) * 0.57) }
            let reflection = polygon(reflectedRidge + [(1, horizon), (0, horizon)])
            var softReflection = context
            softReflection.addFilter(.blur(radius: scale * 0.006))
            softReflection.fill(reflection, with: .color(palette.near.opacity(0.09 + 0.035 * Double(index))))

            let slope = polygon(ridge + [(1, horizon + 0.004), (0, horizon + 0.004)])
            let ridgeColors: [Color] = switch index {
            case 0: [palette.far.opacity(0.62), palette.haze.opacity(0.42)]
            case 1: [palette.far, palette.haze]
            default: [palette.near, palette.far]
            }
            fill(slope, with: vertical(ridgeColors, from: 0.31, to: 0.64))
        }

        let faces: [[(CGFloat, CGFloat)]] = [
            [(0.035, 0.427), (0.088, 0.389), (0.128, 0.424), (0.151, 0.431), (0.185, 0.459), (0.133, 0.446), (0.105, 0.427)],
            [(0.214, 0.462), (0.294, 0.394), (0.318, 0.404), (0.374, 0.456), (0.335, 0.440), (0.310, 0.422), (0.271, 0.427)],
            [(0.696, 0.469), (0.771, 0.391), (0.791, 0.417), (0.814, 0.425), (0.846, 0.463), (0.778, 0.434), (0.751, 0.440)]
        ]
        for face in faces {
            fill(polygon(face), palette.haze.opacity(0.15))
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
        let land = LakeLayout(size: size).banks
        let bank = vertical([palette.near, palette.ink], from: 0.68, to: 1)
        fill(land, with: bank)

        if daylight > 0 {
            fill(land, with: .radialGradient(
                Gradient(colors: [palette.light.opacity(0.31 * daylight), palette.light.opacity(0.08 * daylight), .clear]),
                center: point(lightX, 0.76), startRadius: 0, endRadius: max(scale * 0.70, size.width * 0.45)
            ))
            fill(land, with: .radialGradient(
                Gradient(colors: [Color(red: 0.83, green: 0.68, blue: 0.39).opacity(0.37 * daylight), .clear]),
                center: point(0.15, 0.86), startRadius: 0, endRadius: scale * 0.41
            ))
            var meadow = context
            meadow.clip(to: land)
            drawMeadow(in: meadow, color: palette.light)
        }
        if let moonlight {
            fill(land, with: .radialGradient(
                Gradient(colors: [moonlightColor.opacity(0.20 * moonlight.strength), .clear]),
                center: point(moonlight.x, 0.80), startRadius: 0, endRadius: max(scale * 0.49, size.width * 0.25)
            ))
        }

        var trees = Path()
        var shadows = Path()
        let stretch = shadowStretch
        let shadowDirection = (0.5 - lightX) * size.height / size.width
        for index in 0..<35 {
            let distance = noise(index * 3 + 201)
            let onLeft = index.isMultiple(of: 2)
            let x = onLeft ? distance * 0.109 - 0.018 : 1.016 - distance * 0.21
            if !onLeft && abs(x - 0.878) < 0.027 { continue }
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
            ground.fill(shadows, with: .color(palette.ink.opacity(daylight * (0.21 + 0.14 * stretch))))
        }
        fill(trees, with: vertical([palette.near, palette.ink], from: 0.57, to: 0.85))
    }

    private func drawMeadow(in ground: GraphicsContext, color: Color) {
        var flecks = Path()
        for index in 0..<160 {
            let seed = 7600 + index * 4
            let side = index.isMultiple(of: 2)
            let distance = noise(seed) * 0.39
            let x = side ? distance : 1 - distance
            let y = 0.73 + noise(seed + 1) * 0.27
            let rise = 0.002 + noise(seed + 2) * 0.004
            let lean = (noise(seed + 3) - 0.34) * 0.005
            flecks.move(to: point(x, y))
            flecks.addQuadCurve(to: point(x + lean, y - rise), control: point(x + lean * 0.3, y - rise * 0.7))
        }
        ground.stroke(flecks, with: .color(color.opacity(0.25 * daylight)),
                      style: StrokeStyle(lineWidth: max(0.55, scale * 0.0011), lineCap: .round))
    }

    private func drawGrain() {
        var grain = Path()
        for index in 0..<2800 {
            let p = point(noise(index * 2 + 6000), noise(index * 2 + 6001))
            let dot = max(scale * 0.0011, 0.6)
            grain.addRect(CGRect(x: p.x, y: p.y, width: dot, height: dot))
        }
        fill(grain, .white.opacity(0.075))
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

    private func contour(_ silhouette: [(CGFloat, CGFloat)], seed: Int) -> [(CGFloat, CGFloat)] {
        var result: [(CGFloat, CGFloat)] = []
        for (index, segment) in zip(silhouette, silhouette.dropFirst()).enumerated() {
            let (start, end) = segment
            for step in 0..<5 {
                let t = CGFloat(step) / 5
                let x = start.0 + (end.0 - start.0) * t
                let edge = 1 - pow(2 * t - 1, 2)
                let texture = (noise(seed + index * 5 + step) - 0.5) * 0.014 * edge
                result.append((x, min(horizon, start.1 + (end.1 - start.1) * t + texture)))
            }
        }
        if let end = silhouette.last { result.append(end) }
        return result
    }

    private static let ridges: [[(CGFloat, CGFloat)]] = [
        [(0, 0.442), (0.073, 0.427), (0.121, 0.397), (0.167, 0.387), (0.238, 0.430),
         (0.298, 0.437), (0.361, 0.414), (0.420, 0.436), (0.474, 0.471), (0.524, 0.484),
         (0.579, 0.455), (0.652, 0.427), (0.703, 0.443), (0.760, 0.434), (0.832, 0.386),
         (0.879, 0.396), (0.943, 0.440), (1, 0.419)],
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

    init(sky: TodaySkyAstronomy.Sky, lakeside: Bool = false) {
        let twilight: [Int] = sky.isMorning
            ? (lakeside ? [0x637E94, 0xF3C29A, 0x74858C, 0x8A807F, 0x485754, 0x283A38, 0xFFE0A6]
                        : [0x486F94, 0xEDAD89, 0x657D92, 0x746E86, 0x304C64, 0x1A2937, 0xFFDEA9])
            : (lakeside ? [0x615F83, 0xF2AA86, 0x7A7489, 0x947D86, 0x4C4B60, 0x313041, 0xFFCE94]
                        : [0x545C90, 0xF09874, 0x6C6A89, 0x836F88, 0x3D405E, 0x24263C, 0xFFD09C])
        let stops: [(altitude: Double, colors: [Int])] = [
            (-18, [0x101A2C, 0x354557, 0x20333F, 0x2E3F51, 0x1A2A37, 0x0D1722, 0xB1C9E3]),
            (-7, [0x243550, 0x77748D, 0x485467, 0x545970, 0x2A3549, 0x192437, 0xDBA8A2]),
            (0, twilight),
            (14, lakeside ? [0x7898A3, 0xE1D8C3, 0x7B9D9B, 0x9AA59D, 0x546652, 0x334535, 0xFFEAC5]
                          : [0x508399, 0xC5C8AB, 0x629091, 0x789093, 0x39575B, 0x213438, 0xFFF0BD]),
            (43, lakeside ? [0x7D9FAE, 0xD7DFD5, 0x7BA0A3, 0x9CA9A7, 0x526C58, 0x324737, 0xFFF3D9]
                          : [0x528598, 0xC6D4C6, 0x629695, 0x779396, 0x3A5B56, 0x203736, 0xFFF9D6])
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
