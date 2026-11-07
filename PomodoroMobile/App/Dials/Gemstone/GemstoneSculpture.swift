import CoreGraphics
import Foundation

/// Immutable, procedural geometry. Both maps are atlases: the fixed dial above,
/// and its single rotating hand below. No lighting or background is baked in.
nonisolated struct GemstoneSurfaceMaps: @unchecked Sendable {
    let normals: CGImage
    let surfaces: CGImage

    static func decodeCache(_ data: Data, resolution: Int) -> GemstoneSurfaceMaps? {
        guard data.prefix(8) == Data("GEMSURF1".utf8),
              let decoded = try? GemstoneCompression.decode(Data(data.dropFirst(8)), count: resolution * resolution * 2 * 8 * 2) else { return nil }
        let raw = decoded
        let bytesPerMap = resolution * resolution * 2 * 8
        guard raw.count == bytesPerMap * 2 else { return nil }
        func image(_ bytes: Data) -> CGImage? {
            let info = CGBitmapInfo.floatComponents.union(.byteOrder16Little)
                .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
            return CGImage(width: resolution, height: resolution * 2, bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: resolution * 8, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                bitmapInfo: info, provider: CGDataProvider(data: bytes as CFData)!, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent)
        }
        guard let normals = image(raw.subdata(in: 0..<bytesPerMap)),
              let surfaces = image(raw.subdata(in: bytesPerMap..<raw.count)) else { return nil }
        return GemstoneSurfaceMaps(normals: normals, surfaces: surfaces)
    }
}

nonisolated enum GemstoneSculpture {
    static let resolution = 1536
    static let maps = Task.detached(priority: .userInitiated) {
        if let url = Bundle.main.url(forResource: "GemstoneSurface-v1", withExtension: "bin"),
           let data = try? Data(contentsOf: url),
           let maps = GemstoneSurfaceMaps.decodeCache(data, resolution: resolution) {
            return maps
        }
        return GemstoneSculptureBuilder(resolution: resolution).build()
    }
}

/// Squared Euclidean distance to a zero pixel. Separable lower envelopes avoid
/// an approximate blur, so narrow bezels and broad curved gems share real edges.
nonisolated enum GemstoneDistanceField {
    static func inside(_ mask: [UInt8], width: Int, height: Int) -> [Float] {
        guard width > 0, height > 0 else { return [] }
        var field = mask.map { $0 == 0 ? Float(0) : Float.infinity }
        var input = [Float](repeating: 0, count: max(width, height))
        var output = input
        var sites = [Int](repeating: 0, count: input.count)
        var limits = [Float](repeating: 0, count: input.count + 1)
        func transform(_ count: Int) {
            var last = -1
            for q in 0..<count where input[q].isFinite {
                var crossing: Float = -.infinity
                while last >= 0 {
                    let v = sites[last]
                    crossing = ((input[q] + Float(q * q)) - (input[v] + Float(v * v))) / Float(2 * (q - v))
                    if crossing > limits[last] { break }
                    last -= 1
                }
                last += 1
                sites[last] = q
                limits[last] = last == 0 ? -.infinity : crossing
                limits[last + 1] = .infinity
            }
            guard last >= 0 else {
                for q in 0..<count { output[q] = .infinity }
                return
            }
            var k = 0
            for q in 0..<count {
                while limits[k + 1] < Float(q) { k += 1 }
                let delta = q - sites[k]
                output[q] = Float(delta * delta) + input[sites[k]]
            }
        }
        for y in 0..<height {
            for x in 0..<width { input[x] = field[y * width + x] }
            transform(width)
            for x in 0..<width { field[y * width + x] = output[x] }
        }
        for x in 0..<width {
            for y in 0..<height { input[y] = field[y * width + x] }
            transform(height)
            for y in 0..<height { field[y * width + x] = output[y].squareRoot() }
        }
        return field
    }
}

nonisolated private struct GemstoneSculptureBuilder {
    let resolution: Int
    // Materials: 1 gold, 2 opal glass, 3 clear, 4 sapphire, 5 emerald,
    // 6 amber, 7 garnet, 8 opal hub, 9 opaque enamel hand.
    private struct Surface {
        var height: [Float]
        var material: [UInt8]
        var coverage: [Float]
        var slopeX: [Float]
        var slopeY: [Float]
        init(count: Int) {
            height = .init(repeating: 0, count: count)
            material = .init(repeating: 0, count: count)
            coverage = .init(repeating: 0, count: count)
            slopeX = .init(repeating: 0, count: count)
            slopeY = .init(repeating: 0, count: count)
        }
    }

    func build() -> GemstoneSurfaceMaps {
        var body = Surface(count: resolution * resolution)
        var hand = Surface(count: resolution * resolution)
        let backing = CGMutablePath()
        backing.addPath(outline)
        backing.addPath(circle(radius: 0.333))
        add(backing, base: 0.006, rise: 0.014, material: 3, to: &body)
        flutedDial(to: &body)
        bezel(circle(radius: 0.350), width: 0.006, base: 0.041, to: &body)
        bezel(outline, width: 0.0068, base: 0.048, to: &body)
        let colors: [UInt8] = [4, 6, 5, 3, 5, 4, 5, 6, 3, 4, 5, 3, 4, 6, 5, 3, 5, 3]
        for index in 0..<18 {
            let angle = CGFloat(index) * .pi / 9 + sin(CGFloat(index) * 2.1) * 0.018
            let stone = rotated(paisley(index), angle)
            add(stone, base: 0.010, rise: index % 3 == 0 ? 0.036 : 0.029,
                material: colors[index], to: &body)
            bezel(stone, width: index % 3 == 0 ? 0.008 : 0.0068, base: 0.028, to: &body)
            let drop = rotated(smallDrop(index), angle)
            add(drop, base: 0.012, rise: 0.020, material: index % 3 == 0 ? 7 : index % 3 == 1 ? 3 : 6, to: &body)
            bezel(drop, width: 0.0043, base: 0.025, to: &body)
        }
        for index in 0..<12 {
            let angle = CGFloat(index) * .pi / 6
            let leaf = rotated(petal(start: 0.278, end: 0.379, width: index % 2 == 0 ? 0.031 : 0.026, twist: 0.012), angle)
            add(leaf, base: 0.024, rise: 0.018, material: index % 4 == 1 ? 4 : 5, to: &body)
            bezel(leaf, width: 0.0045, base: 0.040, to: &body)
            let vein = CGMutablePath()
            vein.move(to: CGPoint(x: 0, y: -0.279))
            vein.addQuadCurve(to: CGPoint(x: 0, y: -0.377), control: CGPoint(x: 0.013, y: -0.335))
            bezel(rotated(vein, angle), width: 0.00125, base: 0.041, to: &body)
            add(circle(radius: 0.0061, center: CGPoint(x: sin(angle) * 0.277, y: -cos(angle) * 0.277)),
                base: 0.026, rise: 0.008, material: 1, to: &body)

            // Fine floral wire has a round section, and sits above the glass.
            let wire = rotated(petal(start: 0.050, end: 0.277, width: 0.078, twist: -0.024), angle)
            bezel(wire, width: 0.00135, base: 0.026, to: &body)
        }
        for index in 0..<8 {
            let rosette = rotated(petal(start: 0.027, end: 0.128, width: 0.035, twist: 0.009), CGFloat(index) * .pi / 4)
            add(rosette, base: 0.028, rise: 0.018, material: index % 3 == 0 ? 3 : 5, to: &body)
            bezel(rosette, width: 0.0024, base: 0.042, to: &body)
        }
        for index in 0..<60 where !index.isMultiple(of: 5) {
            let angle = CGFloat(index) * .pi / 30
            let wire = CGMutablePath()
            wire.move(to: CGPoint(x: 0, y: -0.349))
            wire.addLine(to: CGPoint(x: 0, y: -0.326))
            bezel(rotated(wire, angle), width: 0.0011, base: 0.025, to: &body)
            add(circle(radius: 0.0025, center: CGPoint(x: sin(angle) * 0.350, y: -cos(angle) * 0.350)),
                base: 0.025, rise: 0.0035, material: 1, to: &body)
        }
        // Hub is higher than the rotating hand, so it actually occludes its root.
        add(circle(radius: 0.034), base: 0.060, rise: 0.014, material: 8, to: &body)
        bezel(circle(radius: 0.035), width: 0.0058, base: 0.070, to: &body)
        bezel(circle(radius: 0.040), width: 0.0020, base: 0.053, to: &body)

        add(handOutline, base: 0.047, rise: 0.009, material: 9, to: &hand)
        bezel(handOutline, width: 0.0063, base: 0.058, to: &hand)
        let spine = CGMutablePath()
        spine.move(to: CGPoint(x: 0, y: 0.012))
        spine.addCurve(to: CGPoint(x: 0, y: -0.332), control1: CGPoint(x: -0.017, y: -0.100), control2: CGPoint(x: 0.020, y: -0.242))
        bezel(spine, width: 0.0017, base: 0.058, to: &hand)
        return atlas(body: body, hand: hand)
    }

    private func flutedDial(to surface: inout Surface) {
        let side = resolution
        for y in 0..<side {
            for x in 0..<side {
                let px = (Float(x) + 0.5) / Float(side) - 0.5
                let py = (Float(y) + 0.5) / Float(side) - 0.5
                let r = sqrt(px * px + py * py)
                guard r < 0.350 else { continue }
                let angle = atan2(py, px)
                let envelope = sin(min(1, max(0, (r - 0.06) / 0.290)) * .pi)
                let curl = angle + 0.20 * sin(r * 11)
                let lobe = pow(0.5 + 0.5 * cos(curl * 12), 2.2)
                let fine = pow(0.5 + 0.5 * cos(curl * 24 + r * 14), 8)
                let z: Float = 0.007 + 0.004 * (1 - pow(r / 0.350, 2)) + envelope * (lobe * 0.010 + fine * 0.0017)
                let i = y * side + x
                surface.height[i] = z
                surface.material[i] = 2
                surface.coverage[i] = min(1, (0.350 - r) * Float(side))
            }
        }
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                guard surface.material[i] == 2 else { continue }
                surface.slopeX[i] = (surface.height[i + 1] - surface.height[i - 1]) * Float(side) / 2
                surface.slopeY[i] = (surface.height[i + side] - surface.height[i - side]) * Float(side) / 2
            }
        }
    }

    private func bezel(_ path: CGPath, width: CGFloat, base: Float, to surface: inout Surface) {
        add(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2),
            base: base, rise: Float(width) * 0.72, material: 1, to: &surface)
    }

    private func add(_ path: CGPath, base: Float, rise: Float, material: UInt8, to surface: inout Surface) {
        let scale = CGFloat(resolution)
        let bounds = path.boundingBoxOfPath
        let minX = max(0, Int(floor((bounds.minX + 0.5) * scale)) - 3)
        let minY = max(0, Int(floor((bounds.minY + 0.5) * scale)) - 3)
        let maxX = min(resolution, Int(ceil((bounds.maxX + 0.5) * scale)) + 3)
        let maxY = min(resolution, Int(ceil((bounds.maxY + 0.5) * scale)) + 3)
        let width = maxX - minX, height = maxY - minY
        guard width > 0, height > 0 else { return }
        var mask = [UInt8](repeating: 0, count: width * height)
        mask.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return }
            context.translateBy(x: -CGFloat(minX), y: -CGFloat(minY))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0.5, y: 0.5)
            context.addPath(path)
            context.setFillColor(gray: 1, alpha: 1)
            context.drawPath(using: .eoFill)
        }
        let distance = GemstoneDistanceField.inside(mask, width: width, height: height)
        let peak = max(distance.max() ?? 1, 1)
        let heights = distance.map { d -> Float in
            let t = min(1, max(0, (d - 0.45) / peak))
            return base + rise * sqrt(max(0, 1 - (1 - t) * (1 - t)))
        }
        // Polish the medial ridge of the distance surface. Its exact distance
        // is useful for thickness, but differentiating its sharp skeleton would
        // put artificial white seams through the middle of a curved gemstone.
        let polished = Self.polish(heights, width: width, height: height, radius: material == 1 ? 1 : max(1, min(10, min(width, height) / 18)))
        func sample(_ x: Int, _ y: Int) -> Float {
            polished[min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))]
        }
        for y in 0..<height {
            for x in 0..<width {
                let local = y * width + x
                guard mask[local] > 0 else { continue }
                let z = heights[local]
                let target = (y + minY) * resolution + x + minX
                if z >= surface.height[target] {
                    surface.height[target] = z
                    surface.material[target] = material
                    surface.coverage[target] = Float(mask[local]) / 255
                    // Each component keeps its own rounded surface normal.
                    // Differentiating the composed depth would turn the jump
                    // between a bezel and its gem into a false black cliff.
                    surface.slopeX[target] = (sample(x + 2, y) - sample(x - 2, y)) * Float(resolution) / 4
                    surface.slopeY[target] = (sample(x, y + 2) - sample(x, y - 2)) * Float(resolution) / 4
                }
            }
        }
    }

    private static func polish(_ field: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let sigma = max(0.8, Float(radius) * 0.5)
        var weights = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        for i in weights.indices { weights[i] /= total }
        var horizontal = field
        var result = field
        for y in 0..<height {
            for x in 0..<width {
                var value: Float = 0
                for k in -radius...radius {
                    value += field[y * width + min(width - 1, max(0, x + k))] * weights[k + radius]
                }
                horizontal[y * width + x] = value
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var value: Float = 0
                for k in -radius...radius {
                    value += horizontal[min(height - 1, max(0, y + k)) * width + x] * weights[k + radius]
                }
                result[y * width + x] = value
            }
        }
        return result
    }

    private func atlas(body: Surface, hand: Surface) -> GemstoneSurfaceMaps {
        let count = resolution * resolution
        var normals = [Float16](repeating: 0, count: count * 8)
        var metadata = normals
        for (layer, surface) in [body, hand].enumerated() {
            for y in 0..<resolution {
                for x in 0..<resolution {
                    let i = y * resolution + x
                    let target = (layer * count + i) * 4
                    normals[target + 3] = 1
                    let alpha = surface.coverage[i]
                    guard alpha > 0 else { continue }
                    // Depth is composited for occlusion; normals belong to the
                    // selected curved component, independently of its elevation.
                    func h(_ dx: Int, _ dy: Int) -> Float {
                        surface.height[min(resolution - 1, max(0, y + dy)) * resolution + min(resolution - 1, max(0, x + dx))]
                    }
                    let dx = surface.slopeX[i]
                    let dy = surface.slopeY[i]
                    let inverse = 1 / sqrt(dx * dx + dy * dy + 1)
                    normals[target] = Float16(-dx * inverse * 0.5 + 0.5)
                    normals[target + 1] = Float16(-dy * inverse * 0.5 + 0.5)
                    normals[target + 2] = Float16(inverse * 0.5 + 0.5)
                    metadata[target] = Float16(surface.height[i] * 10 * alpha)
                    metadata[target + 1] = Float16(Float(surface.material[i]) / 16 * alpha)
                    // Local concavity makes the contact under each bezel darker.
                    let cavity = max(0, (h(7, 0) + h(-7, 0) + h(0, 7) + h(0, -7)) * 0.25 - surface.height[i])
                    metadata[target + 2] = Float16(exp(-cavity * 65) * alpha)
                    metadata[target + 3] = Float16(alpha)
                }
            }
        }
        func image(_ pixels: [Float16]) -> CGImage {
            let data = pixels.withUnsafeBytes { Data($0) }
            let provider = CGDataProvider(data: data as CFData)!
            let info = CGBitmapInfo.floatComponents.union(.byteOrder16Little)
                .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
            return CGImage(width: resolution, height: resolution * 2, bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: resolution * 8, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        }
        return GemstoneSurfaceMaps(normals: image(normals), surfaces: image(metadata))
    }

    private func circle(radius: CGFloat, center: CGPoint = .zero) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
    private func rotated(_ path: CGPath, _ angle: CGFloat) -> CGPath {
        var transform = CGAffineTransform(rotationAngle: angle)
        return path.copy(using: &transform)!
    }
    private func petal(start: CGFloat, end: CGFloat, width: CGFloat, twist: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -start))
        path.addCurve(to: CGPoint(x: 0, y: -end), control1: CGPoint(x: -width + twist, y: -start - (end - start) * 0.30),
                      control2: CGPoint(x: -width * 0.55 + twist, y: -end + (end - start) * 0.12))
        path.addCurve(to: CGPoint(x: 0, y: -start), control1: CGPoint(x: width * 0.68 + twist, y: -end + (end - start) * 0.22),
                      control2: CGPoint(x: width + twist, y: -start - (end - start) * 0.28))
        path.closeSubpath()
        return path
    }
    private func paisley(_ index: Int) -> CGPath {
        let path = CGMutablePath()
        let variation = CGFloat(index % 3)
        path.move(to: CGPoint(x: -0.058, y: -0.343))
        path.addCurve(to: CGPoint(x: 0.027 - variation * 0.008, y: -0.488),
            control1: CGPoint(x: -0.129, y: -0.404 - variation * 0.004), control2: CGPoint(x: -0.019, y: -0.488))
        path.addCurve(to: CGPoint(x: 0.104, y: -0.421 + variation * 0.007),
            control1: CGPoint(x: 0.087, y: -0.493), control2: CGPoint(x: 0.142, y: -0.469))
        path.addCurve(to: CGPoint(x: -0.058, y: -0.343),
            control1: CGPoint(x: 0.102, y: -0.339), control2: CGPoint(x: -0.004 - variation * 0.009, y: -0.420))
        path.closeSubpath()
        return path
    }
    private func smallDrop(_ index: Int) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -0.049, y: -0.481))
        path.addCurve(to: CGPoint(x: -0.089, y: -0.430), control1: CGPoint(x: -0.085, y: -0.479), control2: CGPoint(x: -0.108, y: -0.451))
        path.addCurve(to: CGPoint(x: -0.049, y: -0.481), control1: CGPoint(x: -0.067, y: -0.416), control2: CGPoint(x: -0.046, y: -0.452))
        path.closeSubpath()
        return path
    }
    private var outline: CGPath {
        let path = CGMutablePath()
        for step in 0...720 {
            let angle = CGFloat(step) * .pi / 360
            let radius = 0.478 + 0.008 * cos(angle * 12) + 0.003 * sin(angle * 24)
            let point = CGPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
    private var handOutline: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0.028))
        path.addCurve(to: CGPoint(x: -0.004, y: -0.182), control1: CGPoint(x: -0.033, y: -0.035), control2: CGPoint(x: 0.031, y: -0.115))
        path.addCurve(to: CGPoint(x: 0, y: -0.337), control1: CGPoint(x: -0.049, y: -0.210), control2: CGPoint(x: -0.015, y: -0.283))
        path.addCurve(to: CGPoint(x: 0.013, y: -0.177), control1: CGPoint(x: 0.008, y: -0.280), control2: CGPoint(x: 0.048, y: -0.231))
        path.addCurve(to: CGPoint(x: 0, y: 0.028), control1: CGPoint(x: -0.017, y: -0.107), control2: CGPoint(x: 0.038, y: -0.040))
        path.closeSubpath()
        return path
    }
}
