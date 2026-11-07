import SwiftUI

struct LakeLayout {
    struct GroundPoint {
        let x: CGFloat
        let depth: CGFloat

        func offset(_ x: CGFloat, _ depth: CGFloat) -> Self {
            Self(x: self.x + x, depth: self.depth + depth)
        }

        func toward(_ end: Self, at t: CGFloat) -> Self {
            offset((end.x - x) * t, (end.depth - depth) * t)
        }
    }

    struct Dock {
        let shore: GroundPoint
        let tip: GroundPoint
        let halfWidth: CGFloat

        func point(at t: CGFloat, across: CGFloat = 0) -> GroundPoint {
            let dx = tip.x - shore.x, dz = tip.depth - shore.depth
            let width = across * halfWidth / hypot(dx, dz)
            return shore.toward(tip, at: t).offset(-dz * width, dx * width)
        }
    }

    let size: CGSize

    static let horizon: CGFloat = 0.56
    private let cameraHeight: CGFloat = 0.27
    var unit: CGFloat { min(size.width, size.height) }
    private var horizonY: CGFloat { Self.horizon * size.height }
    var door: CGPoint { project(cabinPoint(0.81, 0)) }
    var porchLamp: CGPoint { project(cabinPoint(0.96, -0.012), height: 0.030) }
    var leftDock: Dock {
        Dock(shore: ground(0.237, 0.840), tip: ground(0.285, 0.800), halfWidth: 0.012)
    }
    var rightDock: Dock {
        Dock(shore: ground(0.893, 0.763), tip: ground(0.859, 0.741), halfWidth: 0.0105)
    }
    private var trailJunction: CGPoint { project(cabinPoint(0.82, -0.39)) }
    var doorstepPath: [CGPoint] { [trailJunction, door] }

    func trailPoints(toCabin: Bool) -> [CGPoint] {
        func curve(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> [CGPoint] {
            (0...8).map { step in
                let t = CGFloat(step) / 8, s = 1 - t
                let aa = s * s * s, bb = 3 * s * s * t, cc = 3 * s * t * t, dd = t * t * t
                return CGPoint(x: aa * a.x + bb * b.x + cc * c.x + dd * d.x,
                               y: aa * a.y + bb * b.y + cc * c.y + dd * d.y)
            }
        }
        let approach = curve(point(0.020, 0.762), point(0.061, 0.795), point(0.100, 0.847), trailJunction)
        if toCabin { return approach + [door] }
        let shore = curve(trailJunction, point(0.172, 0.861), point(0.214, 0.858), project(leftDock.shore))
        return approach + shore.dropFirst()
    }

    var banks: Path {
        var land = bank(edge: [(0, 0.70), (0.062, 0.729), (0.119, 0.771), (0.204, 0.797),
                               (0.264, 0.847), (0.319, 0.897), (0.39, 1)], bottom: 0)
        land.addPath(bank(edge: [(1, 0.661), (0.94, 0.692), (0.898, 0.736), (0.819, 0.789),
                                 (0.778, 0.844), (0.71, 0.909), (0.68, 1)], bottom: 1))
        return land
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    func offset(_ origin: CGPoint, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
    }

    // The horizon and camera are shared by the bank structures and the water traffic.
    func ground(_ x: CGFloat, _ y: CGFloat) -> GroundPoint {
        ground(at: point(x, y))
    }

    func ground(at screen: CGPoint) -> GroundPoint {
        let depth = cameraHeight * unit / (screen.y - horizonY)
        return GroundPoint(x: (screen.x - size.width / 2) * depth / unit, depth: depth)
    }

    func project(_ point: GroundPoint, height: CGFloat = 0) -> CGPoint {
        let scale = unit / point.depth
        return CGPoint(x: size.width / 2 + point.x * scale, y: horizonY + (cameraHeight - height) * scale)
    }

    func cabinPoint(_ front: CGFloat, _ side: CGFloat) -> GroundPoint {
        let width = front * 0.084, depth = side * 0.037
        // Rotate the two perpendicular walls together, with verticals kept upright.
        return ground(0.108, 0.829).offset(0.9563 * width + 0.2924 * depth,
                                          -0.2924 * width + 0.9563 * depth)
    }

    func boat(at position: Double) -> (center: GroundPoint, heading: CGVector) {
        let t = CGFloat(position)
        let a = ground(0.264, 0.869), b = ground(0.395, 0.751)
        let c = ground(0.690, 0.719), d = ground(0.875, 0.799)
        let middle = b.toward(c, at: t)
        let first = a.toward(b, at: t).toward(middle, at: t)
        let second = middle.toward(c.toward(d, at: t), at: t)
        let dx = second.x - first.x, dz = second.depth - first.depth
        let length = hypot(dx, dz)
        return (first.toward(second, at: t), CGVector(dx: dx / length, dy: dz / length))
    }

    func trail(at fraction: Double, toCabin: Bool) -> CGPoint {
        let points = trailPoints(toCabin: toCabin)
        let segments = zip(points, points.dropFirst()).map { a, b in hypot(b.x - a.x, b.y - a.y) }
        var distance = min(max(fraction, 0), 1) * segments.reduce(0, +)
        for (index, length) in segments.enumerated() {
            if distance <= length, length > 0 {
                let a = points[index], b = points[index + 1]
                let t = distance / length
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            distance -= length
        }
        return points[points.count - 1]
    }

    func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }

    private func bank(edge: [(CGFloat, CGFloat)], bottom: CGFloat) -> Path {
        let points = edge.map { point($0.0, $0.1) }
        return Path { path in
            path.move(to: points[0])
            for (control, next) in zip(points.dropFirst(), points.dropFirst(2)) {
                let midpoint = CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2)
                path.addQuadCurve(to: midpoint, control: control)
            }
            path.addLine(to: points[points.count - 1])
            path.addLine(to: point(bottom, 1))
            path.closeSubpath()
        }
    }
}

struct LakeMotionView: View, Equatable {
    let motion: LakeDaySchedule.Motion
    let daylight: Double
    let waterTone: Color

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            LakeObjects(context: context, layout: LakeLayout(size: size), daylight: daylight)
                .drawMotion(motion, waterTone: waterTone)
        }
    }
}

struct LakeObjects {
    let context: GraphicsContext
    let layout: LakeLayout
    let daylight: Double

    private let lampColor = Color(red: 1, green: 0.70, blue: 0.39)
    private let brightLamp = Color(red: 1, green: 0.87, blue: 0.63)
    private let shadedWood = Color(red: 0.23, green: 0.20, blue: 0.19)
    private let weatheredWood = Color(red: 0.57, green: 0.46, blue: 0.35)
    private var darkness: Double { 1 - daylight }
    private var unit: CGFloat { layout.unit }

    func drawStructures(bankTone: Color, windowLight: Double, moonlight: Double, sunX: CGFloat, shadowStretch: Double) {
        if daylight > 0 {
            var sunlit = context
            sunlit.opacity *= daylight
            var ground = sunlit
            ground.clip(to: layout.banks)
            drawCabinShadow(in: ground, sunX: sunX, stretch: shadowStretch)
            drawTrail(in: ground, bankTone: bankTone)
            drawGarden(in: sunlit, bankTone: bankTone)
            drawDock(layout.leftDock, in: sunlit, bankTone: bankTone)
            drawDock(layout.rightDock, in: sunlit, bankTone: bankTone)
        }
        drawCabin(in: context, bankTone: bankTone, moonlight: moonlight, windowPower: darkness * windowLight)
    }

    func drawMotion(_ motion: LakeDaySchedule.Motion, waterTone: Color) {
        let porchPower = darkness * motion.porch
        if porchPower > 0 {
            glow(in: context, center: layout.porchLamp, radius: 0.035, intensity: porchPower * 0.72)
            dot(in: context, at: layout.porchLamp, radius: 0.0023, color: brightLamp.opacity(porchPower))
        }
        var water = context
        var waterMask = Path(CGRect(x: 0, y: layout.size.height * LakeLayout.horizon,
                                   width: layout.size.width, height: layout.size.height * (1 - LakeLayout.horizon)))
        waterMask.addPath(layout.banks)
        water.clip(to: waterMask, style: FillStyle(eoFill: true))
        if let boat = motion.boat, boat.opacity > 0 { drawBoat(boat, in: water, waterTone: waterTone) }
        if daylight > 0, let ducks = motion.ducks { drawDucks(at: ducks, count: motion.duckCount, in: water) }
        if daylight > 0, let walker = motion.walker { drawWalker(at: walker, carryingLamp: false) }
        if let visitor = motion.lanternVisitor { drawWalker(at: visitor, carryingLamp: true) }
    }

    private func drawGarden(in scene: GraphicsContext, bankTone: Color) {
        let tree = layout.point(0.100, 0.824)
        let bark = Color(red: 0.34, green: 0.33, blue: 0.26).mix(with: bankTone, by: 0.30)
        let amber = Color(red: 0.65, green: 0.53, blue: 0.32).mix(with: bankTone, by: 0.23)
        scene.fill(shape(tree, [(-0.002, 0), (-0.003, -0.038), (0.001, -0.043), (0.002, 0)]),
                   with: .color(bark))
        let crown = roundedShape(tree, [(-0.023, -0.043), (-0.017, -0.052), (-0.014, -0.061),
                                       (-0.002, -0.065), (0.004, -0.061), (0.014, -0.060), (0.023, -0.048),
                                       (0.022, -0.038), (0.011, -0.034), (0.002, -0.030), (-0.013, -0.032)])
        scene.fill(crown, with: .linearGradient(
            Gradient(colors: [amber.mix(with: .white, by: 0.11), amber, amber.mix(with: bark, by: 0.35)]),
            startPoint: layout.offset(tree, -0.013, -0.063), endPoint: layout.offset(tree, 0.013, -0.030)
        ))
        scene.fill(roundedShape(tree, [(-0.017, -0.051), (-0.011, -0.060), (0.002, -0.061), (0.009, -0.055),
                                      (0.003, -0.050), (-0.007, -0.048)]),
                   with: .color(amber.mix(with: .white, by: 0.15).opacity(0.42)))

        for (x, y) in [(0.179, 0.846), (0.196, 0.827), (0.210, 0.869), (0.099, 0.853)] {
            let patch = layout.point(x, y)
            let leaves = Color(red: 0.43, green: 0.47, blue: 0.31).mix(with: bankTone, by: 0.46)
            scene.fill(roundedShape(patch, [(-0.011, 0.002), (-0.009, -0.003), (-0.005, -0.007),
                                           (-0.001, -0.006), (0.004, -0.009), (0.010, -0.005), (0.011, 0.001),
                                           (0.005, 0.003), (-0.004, 0.004)]), with: .color(leaves))
            dot(in: scene, at: layout.offset(patch, -0.003, -0.002), radius: 0.0014,
                color: amber.mix(with: .white, by: 0.18))
            dot(in: scene, at: layout.offset(patch, 0.005, -0.004), radius: 0.0011,
                color: amber)
        }

        let reeds = Color(red: 0.36, green: 0.43, blue: 0.33).mix(with: bankTone, by: 0.30)
        for (x, y) in [(0.257, 0.844), (0.285, 0.867), (0.306, 0.887)] {
            let patch = layout.point(x, y)
            var stems = Path()
            for index in 0..<7 {
                let lean = CGFloat(index - 3) * 0.0034
                let height = 0.010 + CGFloat(index % 4) * 0.004
                stems.move(to: layout.offset(patch, lean * 0.40, 0.003))
                stems.addQuadCurve(to: layout.offset(patch, lean, -height),
                                   control: layout.offset(patch, lean * 0.45, -height * 0.61))
            }
            scene.stroke(stems, with: .color(reeds), style: StrokeStyle(lineWidth: max(0.55, unit * 0.0014), lineCap: .round))
        }
    }

    private func drawTrail(in ground: GraphicsContext, bankTone: Color) {
        let color = Color(red: 0.67, green: 0.58, blue: 0.43).mix(with: bankTone, by: 0.35)
        let centers = layout.trailPoints(toCabin: false)
        func edge(_ side: CGFloat) -> [CGPoint] {
            centers.indices.map { index in
                let center = centers[index]
                let previous = centers[max(0, index - 1)]
                let next = centers[min(centers.count - 1, index + 1)]
                let dx = next.x - previous.x, dy = next.y - previous.y
                let width = 0.0049 * (0.96 + 0.10 * sin(CGFloat(index) * 1.6))
                let offset = side * width / (layout.ground(at: center).depth * hypot(dx, dy))
                return layout.offset(center, -dy * offset, dx * offset)
            }
        }
        ground.fill(layout.polygon(edge(-1) + edge(1).reversed()), with: .color(color.opacity(0.49)))
        ground.stroke(line(centers), with: .color(color.opacity(0.17)),
                      style: StrokeStyle(lineWidth: unit * 0.003, lineCap: .round, lineJoin: .round))
        ground.stroke(line(layout.doorstepPath), with: .color(color.opacity(0.52)),
                      style: StrokeStyle(lineWidth: unit * 0.008, lineCap: .round))
    }

    private func drawDock(_ dock: LakeLayout.Dock, in scene: GraphicsContext, bankTone: Color) {
        let deck: CGFloat = 0.006
        func place(_ t: CGFloat, _ across: CGFloat, _ height: CGFloat? = nil) -> CGPoint {
            layout.project(dock.point(at: t, across: across), height: height ?? deck * min(t / 0.13, 1))
        }
        func plank(_ from: CGFloat, _ to: CGFloat) -> Path {
            layout.polygon([place(from, -1), place(from, 1), place(to, 1), place(to, -1)])
        }
        let top = Color(red: 0.59, green: 0.51, blue: 0.40).mix(with: bankTone, by: 0.26)
        let edge = Color(red: 0.35, green: 0.34, blue: 0.29).mix(with: bankTone, by: 0.25)
        let posts: [(CGFloat, CGFloat)] = [(0.90, -0.79), (0.90, 0.79)]
        let reflected = edge.opacity(0.25)
        for (t, across) in posts {
            let feet = place(t, across, 0)
            scene.stroke(line([feet, place(t, across, -0.013)]), with: .color(reflected),
                         style: StrokeStyle(lineWidth: unit * 0.0024, lineCap: .round))
            scene.stroke(line([feet, place(t, across, deck)]), with: .color(edge),
                         style: StrokeStyle(lineWidth: unit * 0.003, lineCap: .round))
        }

        let near: CGFloat = dock.tip.x > dock.shore.x ? -1 : 1
        scene.fill(layout.polygon([place(0, near), place(0.13, near), place(1, near),
                                   place(1, near, deck - 0.003), place(0.13, near, deck - 0.003)]),
                   with: .color(edge))
        scene.fill(plank(0, 0.13), with: .color(top.mix(with: bankTone, by: 0.21)))
        scene.fill(plank(0.13, 1), with: .color(top))
        for index in 0..<6 {
            let t = CGFloat(index) / 6
            let tone = index.isMultiple(of: 2) ? edge.opacity(0.21) : Color.white.opacity(0.06)
            scene.fill(plank(t + 0.015, t + 0.156), with: .color(tone))
        }
        for (t, across) in posts {
            scene.stroke(line([place(t, across, deck), place(t, across, deck + 0.013)]), with: .color(edge),
                         style: StrokeStyle(lineWidth: unit * 0.003, lineCap: .round))
        }
    }

    private func drawCabinShadow(in ground: GraphicsContext, sunX: CGFloat, stretch: Double) {
        let a = layout.project(layout.cabinPoint(0, 0))
        let b = layout.project(layout.cabinPoint(1, 0))
        let c = layout.project(layout.cabinPoint(1, 1))
        let d = layout.project(layout.cabinPoint(0, 1))
        let base = layout.polygon([a, b, c, d])
        let dx = (0.5 - sunX) * (0.04 + 0.17 * stretch)
        let dy = 0.012 + 0.044 * stretch
        let cast = layout.polygon([a, b, c, layout.offset(c, dx, dy), layout.offset(b, dx, dy),
                                  layout.offset(a, dx, dy)])
        var soft = ground
        soft.addFilter(.blur(radius: unit * 0.003))
        soft.fill(cast, with: .color(.black.opacity(0.17)))
        soft.fill(base, with: .color(.black.opacity(0.36)))
    }

    private func drawCabin(in scene: GraphicsContext, bankTone: Color, moonlight: Double, windowPower: Double) {
        func material(_ red: Double, _ green: Double, _ blue: Double, night: Double) -> Color {
            let ambient = night + moonlight * 0.052
            return Color(red: daylight * red + darkness * (ambient - 0.024),
                         green: daylight * green + darkness * ambient,
                         blue: daylight * blue + darkness * (ambient + 0.030))
                .mix(with: bankTone, by: 0.20)
        }

        let trim = material(0.36, 0.32, 0.26, night: 0.123)
        let paleWood = material(0.72, 0.62, 0.46, night: 0.220)
        let stone = material(0.43, 0.43, 0.36, night: 0.150)
        let eave: CGFloat = 0.042
        let ridge: CGFloat = 0.068
        let foundation: CGFloat = 0.004
        let hairline = max(0.38, unit * 0.0008)
        typealias Surface = (CGFloat, CGFloat) -> CGPoint

        func place(_ u: CGFloat, _ v: CGFloat, _ height: CGFloat) -> CGPoint {
            layout.project(layout.cabinPoint(u, v), height: height)
        }
        func front(_ u: CGFloat, _ height: CGFloat) -> CGPoint { place(u, 0, height) }
        func side(_ v: CGFloat, _ height: CGFloat) -> CGPoint { place(1, v, height) }
        func roofHeight(_ v: CGFloat) -> CGFloat { ridge - abs(v - 0.5) * (ridge - eave) * 2 }
        func roof(_ u: CGFloat, _ v: CGFloat) -> CGPoint { place(u, v, roofHeight(v)) }
        func panel(_ face: Surface, _ width: ClosedRange<CGFloat>, _ height: ClosedRange<CGFloat>) -> Path {
            layout.polygon([face(width.lowerBound, height.lowerBound), face(width.upperBound, height.lowerBound),
                            face(width.upperBound, height.upperBound), face(width.lowerBound, height.upperBound)])
        }

        scene.fill(panel(front, 0...1, 0...foundation), with: .color(stone))
        scene.fill(panel(side, 0...1, 0...foundation), with: .color(stone.mix(with: trim, by: 0.35)))
        scene.fill(panel(front, 0...1, foundation...eave), with: .linearGradient(
            Gradient(colors: [material(0.54, 0.44, 0.34, night: 0.158), material(0.65, 0.53, 0.39, night: 0.185)]),
            startPoint: front(0.35, eave), endPoint: front(0.55, foundation)
        ))
        let gable = layout.polygon([side(0, foundation), side(1, foundation), side(1, eave),
                                    side(0.5, ridge), side(0, eave)])
        scene.fill(gable, with: .linearGradient(
            Gradient(colors: [material(0.51, 0.43, 0.35, night: 0.142), material(0.55, 0.47, 0.37, night: 0.163)]),
            startPoint: side(0.5, ridge), endPoint: side(0.5, foundation)
        ))
        scene.fill(panel(front, 0...1, 0.036...eave), with: .color(trim.opacity(0.28)))
        for height: CGFloat in [0.010, 0.018, 0.026, 0.034] {
            scene.stroke(line([front(0.035, height), front(0.95, height)]),
                         with: .color(trim.opacity(0.22)), lineWidth: hairline)
        }
        for height: CGFloat in [0.013, 0.025, 0.034] {
            scene.stroke(line([side(0.05, height), side(0.95, height)]),
                         with: .color(trim.opacity(0.19)), lineWidth: hairline)
        }

        func window(_ face: Surface, left: CGFloat, right: CGFloat, sill: CGFloat, glowRadius: CGFloat) {
            let top = sill + 0.012
            let center = (left + right) / 2
            let panes = panel(face, left...right, sill...top)
            if windowPower > 0 {
                glow(in: scene, center: face(center, (sill + top) / 2), radius: glowRadius,
                     intensity: windowPower * 0.55)
            }
            scene.fill(panel(face, (left - 0.027)...(right + 0.027), (sill - 0.0015)...(top + 0.0015)),
                       with: .color(trim))
            scene.fill(panes, with: .color(material(0.58, 0.65, 0.60, night: 0.132)))
            scene.fill(panes, with: .color(brightLamp.opacity(windowPower)))
            scene.stroke(line([face(center, sill), face(center, top)]),
                         with: .color(trim.opacity(0.87)), lineWidth: hairline)
            scene.stroke(line([face(left - 0.034, sill - 0.0018), face(right + 0.034, sill - 0.0018)]),
                         with: .color(paleWood.opacity(0.70)), lineWidth: unit * 0.0012)
        }

        window(front, left: 0.27, right: 0.54, sill: 0.017, glowRadius: 0.037)
        window(side, left: 0.41, right: 0.67, sill: 0.019, glowRadius: 0.027)
        scene.fill(panel(front, 0.69...0.91, foundation...0.030), with: .color(trim))
        scene.fill(panel(front, 0.72...0.88, foundation...0.028), with:
            .color(material(0.48, 0.40, 0.31, night: 0.138)))
        let step = layout.polygon([place(0.65, 0, foundation), place(0.95, 0, foundation),
                                   place(0.95, -0.21, 0.001), place(0.65, -0.21, 0.001)])
        scene.fill(step, with: .color(stone))

        let overhang: ClosedRange<CGFloat> = -0.07...1.07
        let rake = layout.polygon([roof(1, 0.5), roof(overhang.upperBound, 0.5),
                                   roof(overhang.upperBound, 1.09), roof(1, 1)])
        scene.fill(rake, with: .color(trim))
        let roofSlope = panel(roof, overhang, -0.09...0.5)
        scene.fill(roofSlope, with: .linearGradient(
            Gradient(colors: [material(0.58, 0.43, 0.36, night: 0.220), material(0.49, 0.35, 0.30, night: 0.180)]),
            startPoint: roof(0.4, 0.5), endPoint: roof(0.5, -0.09)
        ))
        for (u, v, end) in [(0.04, 0.10, 0.90), (0.14, 0.27, 0.99), (-0.02, 0.42, 0.76)] {
            scene.stroke(line([roof(u, v), roof(end, v)]), with: .color(trim.opacity(0.22)),
                         style: StrokeStyle(lineWidth: hairline, lineCap: .round))
        }
        scene.stroke(line([roof(overhang.lowerBound, -0.09), roof(overhang.upperBound, -0.09)]),
                     with: .color(trim.opacity(0.64)), lineWidth: unit * 0.0016)
        scene.stroke(line([roof(overhang.lowerBound, 0.5), roof(overhang.upperBound, 0.5)]),
                     with: .color(paleWood.opacity(0.35)), lineWidth: unit * 0.0010)

        let chimneyTop: CGFloat = 0.079
        scene.fill(panel({ u, h in place(u, 0.23, h) }, 0.24...0.36, roofHeight(0.23)...chimneyTop),
                   with: .color(stone))
        scene.fill(layout.polygon([roof(0.36, 0.23), roof(0.36, 0.44),
                                   place(0.36, 0.44, chimneyTop), place(0.36, 0.23, chimneyTop)]),
                   with: .color(trim))
        scene.fill(layout.polygon([place(0.22, 0.21, chimneyTop), place(0.38, 0.21, chimneyTop),
                                   place(0.38, 0.47, chimneyTop), place(0.22, 0.47, chimneyTop)]),
                   with: .color(stone.mix(with: paleWood, by: 0.30)))
    }

    private func drawBoat(_ boat: LakeDaySchedule.Boat, in water: GraphicsContext, waterTone: Color) {
        let (center, heading) = layout.boat(at: boat.position)
        let direction: CGFloat = boat.returning ? -1 : 1
        let seenFromBow = (center.x * heading.dx + center.depth * heading.dy) * direction < 0
        func place(_ along: CGFloat, _ across: CGFloat, _ height: CGFloat = 0) -> CGPoint {
            layout.project(center.offset(heading.dx * along * direction - heading.dy * across,
                                         heading.dy * along * direction + heading.dx * across), height: height)
        }
        func face(_ points: [(CGFloat, CGFloat, CGFloat)]) -> Path {
            layout.polygon(points.map { place($0.0, $0.1, $0.2) })
        }

        let hull = boat.opacity * daylight
        if hull > 0 {
            let ripple = waterTone.mix(with: .white, by: 0.50)
            for side: CGFloat in [-1, 1] {
                water.stroke(line([place(-0.022, side * 0.006), place(-0.047, side * 0.012),
                                   place(-0.067, side * 0.017)]),
                             with: .color(ripple.opacity(hull * (side < 0 ? 0.35 : 0.21))),
                             style: StrokeStyle(lineWidth: unit * 0.0013, lineCap: .round, lineJoin: .round))
            }

            let timber = Color(red: 0.47, green: 0.42, blue: 0.35).mix(with: waterTone, by: 0.30)
            let upper = Color(red: 0.62, green: 0.56, blue: 0.45).mix(with: waterTone, by: 0.27)
            let wheelhouse = Color(red: 0.73, green: 0.69, blue: 0.56).mix(with: waterTone, by: 0.30)
            if !seenFromBow {
                water.fill(face([(-0.024, -0.008, 0.006), (-0.024, 0.007, 0.006),
                                 (-0.021, 0.005, -0.001), (-0.021, -0.006, -0.001)]),
                           with: .color(timber.mix(with: waterTone, by: 0.21).opacity(hull)))
            }
            water.fill(face([(-0.024, -0.008, 0.006), (0.013, -0.008, 0.006), (0.029, 0, 0.009),
                             (0.015, -0.005, -0.001), (-0.021, -0.006, -0.001)]),
                       with: .color(timber.opacity(hull)))
            water.fill(face([(-0.024, -0.008, 0.006), (-0.024, 0.007, 0.006), (0.012, 0.007, 0.006),
                             (0.029, 0, 0.009), (0.013, -0.008, 0.006)]),
                       with: .color(upper.opacity(hull)))
            let wall: [(CGFloat, CGFloat, CGFloat)] = seenFromBow
                ? [(0.006, -0.005, 0.006), (0.006, 0.005, 0.006), (0.001, 0.005, 0.019), (0.001, -0.005, 0.019)]
                : [(-0.015, -0.005, 0.006), (-0.015, 0.005, 0.006), (-0.015, 0.005, 0.019), (-0.015, -0.005, 0.019)]
            water.fill(face(wall),
                       with: .color(wheelhouse.mix(with: timber, by: 0.27).opacity(hull)))
            water.fill(face([(-0.015, -0.005, 0.006), (0.006, -0.005, 0.006),
                             (0.001, -0.005, 0.019), (-0.015, -0.005, 0.019)]),
                       with: .color(wheelhouse.opacity(hull)))
            water.fill(face([(-0.016, -0.006, 0.019), (0.002, -0.006, 0.019),
                             (0.002, 0.006, 0.019), (-0.016, 0.006, 0.019)]),
                       with: .color(wheelhouse.mix(with: .white, by: 0.13).opacity(hull)))
            water.fill(face([(-0.012, -0.005, 0.012), (-0.002, -0.005, 0.012),
                             (-0.003, -0.005, 0.016), (-0.012, -0.005, 0.016)]),
                       with: .color(timber.mix(with: waterTone, by: 0.34).opacity(hull)))
            water.stroke(line([place(0.007, 0, 0.006), place(0.007, 0, 0.023)]),
                         with: .color(timber.opacity(hull * 0.85)), lineWidth: unit * 0.0014)
        }

        let light = boat.opacity * darkness
        if light > 0 {
            let lamp = place(0.007, 0, 0.023)
            let scale = 1 / center.depth
            glow(in: water, center: lamp, radius: 0.027 * scale, intensity: light * 0.74)
            dot(in: water, at: lamp, radius: 0.0028 * scale, color: brightLamp.opacity(light))
            let surface = place(0.007, 0)
            for index in 0..<6 {
                let t = CGFloat(index)
                let y = (0.003 + t * 0.004) * scale
                let x = 0.0024 * sin(t * 2) * scale
                let width = (0.003 + t * 0.0009) * scale
                water.stroke(line([layout.offset(surface, x - width, y), layout.offset(surface, x + width, y)]),
                             with: .color(lampColor.opacity(light * (0.48 - Double(index) * 0.062))),
                             style: StrokeStyle(lineWidth: unit * 0.0014, lineCap: .round))
            }
        }
    }

    private func drawDucks(at fraction: Double, count: Int, in water: GraphicsContext) {
        let opacity = daylight * edgeFade(fraction, duration: 0.10)
        let curve = sin(.pi * fraction)
        for index in 0..<count {
            let delta = Double(index)
            let center = layout.point(0.258 + 0.218 * fraction - delta * 0.012,
                                      0.840 - 0.080 * curve - 0.037 * fraction + delta * 0.006)
            water.stroke(line([layout.offset(center, -0.004, 0.001), layout.offset(center, -0.017, 0.005)]),
                         with: .color(.white.opacity(opacity * 0.23)), lineWidth: max(0.55, unit * 0.0013))
            water.fill(Path(ellipseIn: CGRect(x: center.x - unit * 0.006, y: center.y - unit * 0.003,
                                              width: unit * 0.012, height: unit * 0.006)),
                       with: .color(shadedWood.opacity(opacity)))
            dot(in: water, at: layout.offset(center, 0.0035, -0.004), radius: 0.0029,
                color: Color(red: 0.25, green: 0.35, blue: 0.28).opacity(opacity))
            dot(in: water, at: layout.offset(center, 0.007, -0.003), radius: 0.0015,
                color: lampColor.opacity(opacity * 0.82))
        }
    }

    private func drawWalker(at fraction: Double, carryingLamp: Bool) {
        let ground = layout.ground(at: layout.trail(at: fraction, toCabin: carryingLamp))
        func place(_ x: CGFloat, _ height: CGFloat) -> CGPoint {
            layout.project(ground.offset(x, 0), height: height)
        }
        let presence = edgeFade(fraction, duration: 0.10)
        let visibility = daylight * presence
        if visibility > 0 {
            let coat = carryingLamp ? shadedWood : Color(red: 0.48, green: 0.40, blue: 0.31)
            context.fill(layout.polygon([place(-0.0035, 0.018), place(0.003, 0.018),
                                         place(0.004, 0.007), place(-0.0035, 0.007)]),
                         with: .color(coat.opacity(visibility)))
            for x in [-0.003, 0.003] {
                context.stroke(line([place(x * 0.6, 0.009), place(x * 1.25, 0)]),
                               with: .color(shadedWood.opacity(visibility)), lineWidth: unit * 0.0018 / ground.depth)
            }
            dot(in: context, at: place(0, 0.021), radius: 0.0032 / ground.depth,
                color: weatheredWood.opacity(visibility))
        }
        let light = darkness * presence
        if carryingLamp && light > 0 {
            let lamp = place(0.006, 0.013)
            glow(in: context, center: lamp, radius: 0.021, intensity: light * 0.80)
            dot(in: context, at: lamp, radius: 0.0026, color: brightLamp.opacity(light))
        }
    }

    private func edgeFade(_ fraction: Double, duration: Double) -> Double {
        let t = min(1, min(fraction, 1 - fraction) / duration)
        return t * t * (3 - 2 * t)
    }

    private func shape(_ origin: CGPoint, _ points: [(CGFloat, CGFloat)]) -> Path {
        layout.polygon(points.map { layout.offset(origin, $0.0, $0.1) })
    }

    private func roundedShape(_ origin: CGPoint, _ vertices: [(CGFloat, CGFloat)]) -> Path {
        let points = vertices.map { layout.offset(origin, $0.0, $0.1) }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        return Path { path in
            path.move(to: midpoint(points[points.count - 1], points[0]))
            for index in points.indices {
                path.addQuadCurve(to: midpoint(points[index], points[(index + 1) % points.count]), control: points[index])
            }
            path.closeSubpath()
        }
    }

    private func line(_ points: [CGPoint]) -> Path { Path { $0.addLines(points) } }

    private func glow(in layer: GraphicsContext, center: CGPoint, radius: CGFloat, intensity: Double) {
        let radius = radius * unit
        let colors = Gradient(colors: [lampColor.opacity(intensity), lampColor.opacity(intensity * 0.24), lampColor.opacity(0)])
        layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2)),
                   with: .radialGradient(colors, center: center, startRadius: 0, endRadius: radius))
    }

    private func dot(in layer: GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color) {
        let radius = max(0.55, radius * unit)
        layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2)), with: .color(color))
    }
}
