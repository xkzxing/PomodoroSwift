import Foundation
import simd

nonisolated struct GemstoneVertex: Sendable {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

nonisolated struct GemstoneMesh: Sendable {
    var vertices: [GemstoneVertex] = []
    var indices: [UInt32] = []
    var materials: [UInt32] = []
    var opticalBodies: [UInt32] = []
    private(set) var emissiveRanges: [Range<Int>] = []
    private(set) var emitterMedia: [UInt32] = []
    static let emissionFlag: UInt32 = 0x8000_0000
    private var nextOpticalBody: UInt32 = 1

    init(opticalBodyBase:UInt32 = 1) {
        precondition(opticalBodyBase>0 && opticalBodyBase<0x0080_0000)
        nextOpticalBody=opticalBodyBase
    }

    /// Mark complete solids or wires without changing their optical identity.
    mutating func markEmissive(startingAt firstTriangle: Int, inside medium: UInt32 = 0) {
        guard firstTriangle >= 0, firstTriangle < materials.count else { return }
        emissiveRanges.append(firstTriangle..<materials.count)
        emitterMedia.append(medium)
    }

    /// Labels one closed solid, independently of its colour. Two blue stones
    /// must remain distinct when a ray enters or exits overlapping objects.
    mutating func sealOpticalBody(startingAt firstTriangle: Int) {
        guard firstTriangle < materials.count else { return }
        for index in firstTriangle..<materials.count { opticalBodies[index] = nextOpticalBody }
        nextOpticalBody += 1
    }

    var packedBoundaries: [UInt32] {
        var packed = zip(materials, opticalBodies).map { material, object in (object << 8) | material }
        for range in emissiveRanges {
            for index in range { packed[index] |= Self.emissionFlag }
        }
        return packed
    }

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                           material: UInt32, interior: SIMD3<Float>? = nil,
                           normals: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)? = nil) {
        var b = b, c = c
        var ns = normals
        var n = simd_cross(b - a, c - a)
        guard simd_length_squared(n) > 1e-16 else { return }
        if let interior, simd_dot(n, (a + b + c) / 3 - interior) < 0 {
            swap(&b, &c)
            if let old = ns { ns = (old.0, old.2, old.1) }
            n = -n
        }
        n = simd_normalize(n)
        let start = UInt32(vertices.count)
        vertices.append(GemstoneVertex(position: a, normal: ns?.0 ?? n))
        vertices.append(GemstoneVertex(position: b, normal: ns?.1 ?? n))
        vertices.append(GemstoneVertex(position: c, normal: ns?.2 ?? n))
        indices.append(contentsOf: [start, start + 1, start + 2])
        materials.append(material)
        opticalBodies.append(0)
    }

    mutating func tube(_ points: [SIMD3<Float>], radius: Float, closed: Bool = true, sides: Int = 12, material: UInt32 = 1) {
        guard points.count > 2 else { return }
        let count = points.count
        var rings: [[SIMD3<Float>]] = [], normals: [[SIMD3<Float>]] = []
        for i in points.indices {
            let before = points[closed ? (i + count - 1) % count : max(0, i - 1)]
            let after = points[closed ? (i + 1) % count : min(count - 1, i + 1)]
            let tangent = simd_normalize(after - before)
            let reference = abs(tangent.z) < 0.90 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
            let u = simd_normalize(simd_cross(tangent, reference)), v = simd_cross(tangent, u)
            var ring: [SIMD3<Float>] = [], ns: [SIMD3<Float>] = []
            for side in 0..<sides {
                let a = Float(side) * 2 * .pi / Float(sides)
                let n = cos(a) * u + sin(a) * v
                ns.append(n); ring.append(points[i] + n * radius)
            }
            rings.append(ring); normals.append(ns)
        }
        for i in 0..<(closed ? count : count - 1) {
            let j = (i + 1) % count
            for side in 0..<sides {
                let t = (side + 1) % sides
                triangle(rings[i][side], rings[j][side], rings[j][t], material: material,
                         normals: (normals[i][side], normals[j][side], normals[j][t]))
                triangle(rings[i][side], rings[j][t], rings[i][t], material: material,
                         normals: (normals[i][side], normals[j][t], normals[i][t]))
            }
        }
    }

    mutating func sphere(center: SIMD3<Float>, radius: Float, material: UInt32, segments: Int = 24, rings: Int = 12) {
        func point(_ a: Int, _ b: Int) -> SIMD3<Float> {
            let theta = Float(a) * 2 * .pi / Float(segments), phi = Float(b) * .pi / Float(rings)
            return SIMD3(sin(phi) * cos(theta), sin(phi) * sin(theta), cos(phi))
        }
        for ring in 0..<rings {
            for segment in 0..<segments {
                let a = point(segment, ring), b = point(segment + 1, ring)
                let c = point(segment + 1, ring + 1), d = point(segment, ring + 1)
                triangle(center + a * radius, center + b * radius, center + c * radius,
                         material: material, interior: center, normals: (a, b, c))
                triangle(center + a * radius, center + c * radius, center + d * radius,
                         material: material, interior: center, normals: (a, c, d))
            }
        }
    }
}

nonisolated enum GemstoneMeshScene: Sendable, Equatable {
    case study, dial
}

nonisolated struct GemstoneMeshSceneData: Sendable {
    var body: GemstoneMesh
    var hand: GemstoneMesh
    var pigmentDensity: Float = 1

    static let study = Task.detached(priority: .userInitiated) { GemstoneMeshBuilder.study() }
    static let dial = Task.detached(priority: .userInitiated) { GemstoneMeshBuilder.dial() }
}

nonisolated enum GemstoneMeshBuilder {
    private static func rotate(_ point: SIMD2<Float>, _ angle: Float) -> SIMD2<Float> {
        SIMD2(cos(angle) * point.x - sin(angle) * point.y, sin(angle) * point.x + cos(angle) * point.y)
    }
    private static func cubic(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ d: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
        let s = 1 - t
        return a * (s * s * s) + b * (3 * s * s * t) + c * (3 * s * t * t) + d * (t * t * t)
    }
    static func pearOutline(samples: Int) -> [SIMD2<Float>] {
        let curves: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(-1, 0), SIMD2(-0.73, -0.10), SIMD2(-0.33, -0.78), SIMD2(0.30, -0.75)),
            (SIMD2(0.30, -0.75), SIMD2(0.76, -0.73), SIMD2(1, -0.37), SIMD2(1, 0)),
            (SIMD2(1, 0), SIMD2(1, 0.37), SIMD2(0.76, 0.73), SIMD2(0.30, 0.75)),
            (SIMD2(0.30, 0.75), SIMD2(-0.33, 0.78), SIMD2(-0.73, 0.10), SIMD2(-1, 0))
        ]
        return (0..<samples).map { i in
            let u = Float(i) * 4 / Float(samples)
            let curve = curves[min(3, Int(u))]
            return cubic(curve.0, curve.1, curve.2, curve.3, u - floor(u))
        }
    }

    static func jewel(_ mesh: inout GemstoneMesh, center: SIMD3<Float>, scale: SIMD2<Float>, angle: Float,
                      material: UInt32, detailed: Bool = false, mounted: Bool = true, settingWidth: Float? = nil,
                      withLightCore: Bool = false) {
        let angularSteps = detailed ? 128 : 64
        let radialSteps = detailed ? 24 : 16
        let outline = pearOutline(samples: angularSteps)
        func world(_ p: SIMD2<Float>, _ z: Float) -> SIMD3<Float> {
            let xy = rotate(p * scale, angle)
            return center + SIMD3(xy.x, xy.y, z)
        }
        // Closed, polished cabochon. A continuous crown and curved underside
        // remove the large table window and repeated planar pavilion images.
        let depth = min(scale.x, scale.y) * 0.50
        let crown = min(scale.x, scale.y) * 0.55
        let origin = SIMD2<Float>(0.10, 0)
        func point(_ row: Int, _ index: Int, front: Bool) -> SIMD3<Float> {
            let r = Float(row) / Float(radialSteps)
            let p = outline[(index + angularSteps) % angularSteps]
            let xy = origin + (p - origin) * r
            let height = pow(max(0, 1 - r * r), 0.58)
            return world(xy, front ? 0.003 + crown * height : -0.003 - depth * height)
        }
        func normal(_ row: Int, _ index: Int, front: Bool) -> SIMD3<Float> {
            if row == 0 { return SIMD3(0, 0, front ? 1 : -1) }
            let r = min(Float(row) / Float(radialSteps), 0.9995)
            let p = outline[index % angularSteps] - origin
            let tangent = outline[(index + 1) % angularSteps] - outline[(index + angularSteps - 1) % angularSteps]
            let dh = -1.16 * r * pow(1 - r * r, -0.42) * (front ? crown : -depth)
            let dr = SIMD3(p.x * scale.x, p.y * scale.y, dh)
            let da = SIMD3(tangent.x * scale.x * r, tangent.y * scale.y * r, 0)
            var n = simd_normalize(simd_cross(dr, da))
            if !front { n = -n }
            let xy = rotate(SIMD2(n.x, n.y), angle)
            return SIMD3(xy.x, xy.y, n.z)
        }
        let firstTriangle = mesh.materials.count
        let interior = center
        for front in [true, false] {
            for row in 0..<radialSteps {
                for i in outline.indices {
                    let j = (i + 1) % angularSteps
                    let a = point(row, i, front: front), b = point(row + 1, i, front: front)
                    let c = point(row + 1, j, front: front), d = point(row, j, front: front)
                    mesh.triangle(a, b, c, material: material, interior: interior,
                        normals: (normal(row, i, front: front), normal(row + 1, i, front: front), normal(row + 1, j, front: front)))
                    mesh.triangle(a, c, d, material: material, interior: interior,
                        normals: (normal(row, i, front: front), normal(row + 1, j, front: front), normal(row, j, front: front)))
                }
            }
        }
        for i in outline.indices {
            let j = (i + 1) % angularSteps
            mesh.triangle(point(radialSteps, i, front: true), point(radialSteps, i, front: false), point(radialSteps, j, front: false), material: material, interior: interior)
            mesh.triangle(point(radialSteps, i, front: true), point(radialSteps, j, front: false), point(radialSteps, j, front: true), material: material, interior: interior)
        }
        mesh.sealOpticalBody(startingAt: firstTriangle)
        if withLightCore {
            let origin=world(.zero,0)
            lightInclusion(&mesh,center:world(SIMD2(0.12,-0.04),0),
                axisU:world(SIMD2(0.24,0),0)-origin,axisV:world(SIMD2(0,0.22),0)-origin,
                thickness:min(scale.x,scale.y)*0.07,material:material==4 ? 15 : material==7 ? 16 : 14,
                medium:(mesh.opticalBodies[firstTriangle]<<8)|material)
        }
        let fine = pearOutline(samples: detailed ? 192 : settingWidth == nil ? 72 : 48)
        let radius = min(scale.x, scale.y) * (mounted ? (detailed ? 0.035 : 0.046) : 0.024)
        let rim = fine.map { world($0 * 1.025, 0.006) }
        if let settingWidth { rolledSetting(&mesh, outline: rim, width: settingWidth) }
        else { mesh.tube(rim, radius: radius, sides: detailed ? 16 : 10) }
        if mounted {
            mesh.tube(fine.map { world($0 * 0.77, -depth * 0.36) }, radius: radius * 0.64, sides: 10)
            // Four actual prongs connect the gallery to the upper girdle. They are
            // separate solids and cast shadows / reflect in the gemstone.
            for t in [0.10, 0.36, 0.64, 0.90] {
                let p = fine[Int(t * Double(fine.count))]
                let curve = (0...16).map { i -> SIMD3<Float> in
                    let u = Float(i) / 16
                    let factor: Float = 0.83 + 0.24 * sin(u * .pi * 0.8)
                    let z = -depth * 0.34 + (crown * 0.48 + depth * 0.34) * u
                    return world(p * factor, z)
                }
                mesh.tube(curve, radius: radius * 0.78, closed: false, sides: 10)
                mesh.sphere(center: curve.last!, radius: radius * 0.90, material: 1, segments: 12, rings: 8)
            }
        }
        if detailed {
            for i in stride(from: 0, to: fine.count, by: 4) {
                mesh.sphere(center: world(fine[i] * 1.055, 0.011), radius: radius * 0.30,
                            material: 1, segments: 10, rings: 6)
            }
        }
    }

    static func study() -> GemstoneMeshSceneData {
        var body = GemstoneMesh(), hand = GemstoneMesh()
        jewel(&body, center: SIMD3(0, -0.025, 0.035), scale: SIMD2(0.32, 0.29), angle: -0.23, material: 4, detailed: true)
        // A distant triangle lets the exact same binding layout serve both the
        // material study and the single-hand dial without allocating per frame.
        hand.triangle(SIMD3(20, 20, -20), SIMD3(21, 20, -20), SIMD3(20, 21, -20), material: 1)
        return GemstoneMeshSceneData(body: body, hand: hand)
    }

    static func localLightStudy(enabled:Bool=true,blocked:Bool=false)->GemstoneMeshSceneData {
        var body=GemstoneMesh(),hand=GemstoneMesh()
        jewel(&body,center:SIMD3(-0.12,0,0.025),scale:SIMD2(0.10,0.12),angle:0,material:3,mounted:false)
        let parent=(body.opticalBodies[0]<<8)|3
        jewel(&body,center:SIMD3(0.12,0,0.025),scale:SIMD2(0.10,0.12),angle:0,material:5,mounted:false)
        if enabled {
            lightInclusion(&body,center:SIMD3(-0.12,0,0.025),axisU:SIMD3(0.012,0,0),
                axisV:SIMD3(0,0.016,0),thickness:0.004,material:14,medium:parent)
        }
        if blocked {
            let a=SIMD3<Float>(0,-0.3,-0.15),b=SIMD3<Float>(0,0.3,-0.15)
            let c=SIMD3<Float>(0,0.3,0.3),d=SIMD3<Float>(0,-0.3,0.3)
            body.triangle(a,b,c,material:17);body.triangle(a,c,d,material:17)
        }
        hand.triangle(SIMD3(20,20,-20),SIMD3(21,20,-20),SIMD3(20,21,-20),material:1)
        return GemstoneMeshSceneData(body:body,hand:hand,pigmentDensity:4.8)
    }

    /// A closed parametric solid. Front and rear surfaces share the same
    /// perimeter, so refraction always has a matching entry and exit boundary.
    static func patch(_ mesh: inout GemstoneMesh, uSteps: Int, vSteps: Int,
                      material: UInt32, surface: (Float, Float, Bool) -> SIMD3<Float>) {
        let firstTriangle = mesh.materials.count
        func normal(_ u: Float, _ v: Float, _ front: Bool) -> SIMD3<Float> {
            let du = surface(min(1, u + 0.001), v, front) - surface(max(0, u - 0.001), v, front)
            let dv = surface(u, min(1, v + 0.001), front) - surface(u, max(0, v - 0.001), front)
            let n = simd_normalize(simd_cross(dv, du))
            return front ? n : -n
        }
        for front in [true, false] {
            for row in 0..<vSteps {
                for column in 0..<uSteps {
                    let u = Float(column) / Float(uSteps), v = Float(row) / Float(vSteps)
                    let nextU = Float(column + 1) / Float(uSteps), nextV = Float(row + 1) / Float(vSteps)
                    let a = surface(u, v, front), b = surface(u, nextV, front)
                    let c = surface(nextU, nextV, front), d = surface(nextU, v, front)
                    let na = normal(u, v, front), nb = normal(u, nextV, front)
                    let nc = normal(nextU, nextV, front), nd = normal(nextU, v, front)
                    if front {
                        mesh.triangle(a, b, c, material: material, normals: (na, nb, nc))
                        mesh.triangle(a, c, d, material: material, normals: (na, nc, nd))
                    } else {
                        mesh.triangle(a, c, b, material: material, normals: (na, nc, nb))
                        mesh.triangle(a, d, c, material: material, normals: (na, nd, nc))
                    }
                }
            }
        }
        let edge = (0..<uSteps).map { SIMD2(Float($0) / Float(uSteps), 0) }
            + (0..<vSteps).map { SIMD2(1, Float($0) / Float(vSteps)) }
            + (0..<uSteps).map { SIMD2(Float(uSteps - $0) / Float(uSteps), 1) }
            + (0..<vSteps).map { SIMD2(0, Float(vSteps - $0) / Float(vSteps)) }
        for i in edge.indices {
            let p = edge[i], q = edge[(i + 1) % edge.count]
            let a = surface(p.x, p.y, true), b = surface(q.x, q.y, true)
            let c = surface(q.x, q.y, false), d = surface(p.x, p.y, false)
            mesh.triangle(a, b, c, material: material)
            mesh.triangle(a, c, d, material: material)
        }
        mesh.sealOpticalBody(startingAt: firstTriangle)
    }

    /// A small closed emitter sits inside a transparent stone. The remaining
    /// stone keeps its original absorption and interfaces, including shadows.
    static func lightVein(_ mesh: inout GemstoneMesh,points:[SIMD3<Float>],radius:Float,material:UInt32) {
        guard points.count>2 else { return }
        let first=mesh.materials.count,sides=8
        mesh.tube(points,radius:radius,closed:false,sides:sides,material:material)
        // Match the closed caps' outward winding while retaining the sweep's
        // outward shading normals at the corresponding vertex positions.
        for triangle in first..<mesh.materials.count {
            mesh.vertices.swapAt(triangle*3+1,triangle*3+2)
        }
        for end in [0,points.count-1] {
            let before=points[max(0,end-1)],after=points[min(points.count-1,end+1)]
            let tangent=simd_normalize(after-before)
            let reference=abs(tangent.z)<0.90 ? SIMD3<Float>(0,0,1) : SIMD3<Float>(0,1,0)
            let u=simd_normalize(simd_cross(tangent,reference)),v=simd_cross(tangent,u)
            let ring=(0..<sides).map { side -> SIMD3<Float> in
                let angle=Float(side)*2 * .pi/Float(sides)
                return points[end]+(cos(angle)*u+sin(angle)*v)*radius
            }
            for side in 0..<sides {
                mesh.triangle(points[end],ring[side],ring[(side+1)%sides],material:material,
                    interior:points[end==0 ? 1 : points.count-2])
            }
        }
        mesh.markEmissive(startingAt:first)
    }

    static func lightInclusion(_ mesh: inout GemstoneMesh,center:SIMD3<Float>,axisU:SIMD3<Float>,axisV:SIMD3<Float>,
                               thickness:Float,material:UInt32,medium:UInt32) {
        let first=mesh.materials.count,segments=16,rings=8
        let u=simd_normalize(axisU),v=simd_normalize(axisV-u*simd_dot(axisV,u)),n=simd_cross(u,v)
        let a=simd_length(axisU),b=simd_length(axisV)
        func sample(_ x:Int,_ y:Int)->(SIMD3<Float>,SIMD3<Float>) {
            let angle=Float(x)*2 * .pi/Float(segments),phi=Float(y) * .pi/Float(rings)
            let s=sin(phi),c=cos(phi),lobe=1+0.16*sin(angle*3+0.7)*s*s
            let p=SIMD3<Float>(cos(angle)*s,sin(angle)*s,c)
            return (center+(u*p.x*a+v*p.y*b)*lobe+n*p.z*thickness,
                simd_normalize(u*p.x/a+v*p.y/b+n*p.z/thickness))
        }
        for y in 0..<rings {
            for x in 0..<segments {
                let p=sample(x,y),q=sample(x+1,y),r=sample(x+1,y+1),s=sample(x,y+1)
                mesh.triangle(p.0,q.0,r.0,material:material,interior:center,normals:(p.1,q.1,r.1))
                mesh.triangle(p.0,r.0,s.0,material:material,interior:center,normals:(p.1,r.1,s.1))
            }
        }
        mesh.markEmissive(startingAt:first,inside:medium)
    }

    static func flowingStone(_ mesh: inout GemstoneMesh, index: Int, count: Int, material: UInt32) {
        let span = 2 * Float.pi / Float(count)
        func surface(_ u: Float, _ v: Float, _ front: Bool) -> SIMD3<Float> {
            func boundary(_ number: Int) -> Float {
                let shape = Float(number % count)
                let strength = 0.34 + 0.11 * sin(shape * 1.9)
                let bend = strength * sin(v * .pi) - (0.20 + 0.07 * cos(shape * 2.3)) * cos(v * .pi)
                return (Float(number) - 0.5 + bend) * span
            }
            let a = boundary(index) * (1 - u) + boundary(index + 1) * u
            let inner: Float = 0.347 + 0.003 * cos(a * 12)
            let outer: Float = 0.482 + 0.010 * cos(a * 12 + 0.35) + 0.003 * sin(a * 24)
            let r = inner + (outer - inner) * v
            let dome = pow(max(0, sin(u * .pi) * sin(v * .pi)), 0.65)
            let z: Float = front ? 0.017 + 0.039 * dome : -0.006 - 0.013 * dome
            return SIMD3(sin(a) * r, -cos(a) * r, z)
        }
        patch(&mesh, uSteps: 24, vSteps: 32, material: material, surface: surface)
        var edge: [SIMD3<Float>] = []
        for i in 0..<32 { edge.append(surface(Float(i) / 32, 0, true)) }
        for i in 0..<48 { edge.append(surface(1, Float(i) / 48, true)) }
        for i in 0..<32 { edge.append(surface(1 - Float(i) / 32, 1, true)) }
        for i in 0..<48 { edge.append(surface(0, 1 - Float(i) / 48, true)) }
        mesh.tube(edge.map { $0 + SIMD3(0, 0, 0.0015) }, radius: 0.0021, sides: 12)
        // Fine swept wires lie on the curved crystal and share its movement.
        for strand in [Float(0.24), 0.52, 0.77] {
            let wire = (0...48).map { i -> SIMD3<Float> in
                let v = Float(i) / 48
                let u = strand + sin(v * .pi * 1.4) * 0.060
                return surface(u, v, true) + SIMD3(0, 0, 0.0004)
            }
            mesh.tube(wire, radius: 0.00030, closed: false, sides: 6)
        }
        for band in [Float(0.24), 0.49, 0.73] {
            let branch = (0...40).map { i -> SIMD3<Float> in
                let u = Float(i) / 40
                let v = band + sin(u * .pi) * 0.10
                return surface(u, v, true) + SIMD3(0, 0, 0.0003)
            }
            mesh.tube(branch, radius: 0.00022, closed: false, sides: 6)
        }
    }

    private static func dialHeight(_ point: SIMD2<Float>) -> Float {
        let radial = min(1, simd_length(point) / 0.350)
        let angle = atan2(point.y, point.x)
        let envelope = pow(sin(radial * .pi), 2)
        return 0.009 + 0.0035 * (1 - radial * radial) + envelope * cos(angle * 6) * 0.0006
    }

    private static func dialBackHeight(_ point: SIMD2<Float>) -> Float {
        let radial = min(1, simd_length(point) / 0.350)
        // A continuous backing with a smooth radial thickness gradient avoids
        // multiplying the panes' small-scale refraction into a wrinkled image.
        return dialHeight(point) - 0.009 - 0.007 * (1 - radial * radial)
    }

    /// One opaque arm supports a raised, closed gemstone inlay and gold rim.
    static func singleHand() -> GemstoneMesh {
        // Moving and fixed acceleration structures share a medium stack.
        // Reserve a separate optical identity range for the transparent inlay.
        var mesh = GemstoneMesh(opticalBodyBase:0x0040_0001)
        func center(_ t: Float) -> SIMD2<Float> {
            SIMD2(sin(t * 2 * .pi) * 0.006, -0.012 - t * 0.339)
        }
        func width(_ t: Float) -> Float {
            let blade = exp(-pow((t - 0.72) / 0.15, 2)) * 0.014
            let shaft = 0.004 + sin(t * .pi) * 0.003
            return 0.00035 + (shaft + blade) * min(1, (1 - t) * 17)
        }
        func surface(_ u: Float, _ v: Float, _ front: Bool) -> SIMD3<Float> {
            let p = center(v), across = u * 2 - 1
            return SIMD3(p.x + across * width(v), p.y,
                front ? 0.100 + 0.006 * (1 - across * across) : 0.087)
        }
        patch(&mesh, uSteps: 16, vSteps: 96, material: 9, surface: surface)
        var outline = (0...120).map { surface(0, Float($0) / 120, true) }
        outline += (0...120).reversed().map { surface(1, Float($0) / 120, true) }
        let rimStart=mesh.materials.count
        mesh.tube(outline.map { $0 + SIMD3(0, 0, 0.0010) }, radius: 0.0028, sides: 12,material:20)
        mesh.markEmissive(startingAt:rimStart)
        // A wider transparent crown leaves a dark enamel border. A small
        // closed source beneath its crown is refracted by the actual stone.
        func inlay(_ u: Float, _ v: Float, _ front: Bool) -> SIMD3<Float> {
            let t = 0.51 + v * 0.42
            let p = center(t), across = u * 2 - 1
            let taper = 0.03 + 0.97 * sin(v * .pi)
            return SIMD3(p.x + across * width(t) * 0.70 * taper, p.y,
                front ? 0.108 + 0.0035 * (1 - 0.85*abs(across)) : 0.1065)
        }
        let inlayStart=mesh.materials.count
        patch(&mesh, uSteps: 12, vSteps: 32, material: 5, surface: inlay)
        let medium=(mesh.opticalBodies[inlayStart]<<8)|5
        let coreStart=mesh.materials.count
        patch(&mesh,uSteps:4,vSteps:24,material:19) { u,v,front in
            let along=0.10+v*0.80,t=0.51+along*0.42
            let p=center(t),taper=0.03+0.97*sin(along * .pi)
            let widthScale=(0.05+0.95*sin(v * .pi))*0.72
            return SIMD3(p.x+(u*2-1)*width(t)*0.70*taper*widthScale,p.y,front ? 0.1074 : 0.1070)
        }
        mesh.markEmissive(startingAt:coreStart,inside:medium)
        let ridge = (0...112).map { i -> SIMD3<Float> in
            let t = 0.06 + Float(i) / 112 * 0.91
            let p = center(t)
            let start = min(1, max(0, (t - 0.49) / 0.04))
            let end = min(1, max(0, (0.95 - t) / 0.04))
            let lift = start * start * (3 - 2 * start) * end * end * (3 - 2 * end)
            return SIMD3(p.x, p.y, 0.1065 + lift * 0.0065)
        }
        let ridgeStart = mesh.materials.count
        mesh.tube(ridge, radius: 0.0007, closed: false, sides: 8,material:20)
        mesh.markEmissive(startingAt: ridgeStart)
        return mesh
    }

    static func dial() -> GemstoneMeshSceneData {
        var body = GemstoneMesh()
        referenceOuterRing(&body)
        glassDial(&body)
        crystalPetalLayer(&body)
        referenceHourMarkers(&body)
        for i in 0..<12 {
            let a = Float(i) * .pi / 6
            radialSettingBrace(&body, index: i)
            let center=SIMD2(sin(a)*0.266,-cos(a)*0.266)
            body.tube([SIMD3(center.x,center.y,0.030),SIMD3(center.x,center.y,0.046),SIMD3(center.x,center.y,0.060)],
                radius:0.0018,closed:false,sides:10)
            body.sphere(center: SIMD3(center.x,center.y,0.060), radius: 0.0066, material: 1, segments: 16, rings: 10)
        }
        let centerColors: [UInt32] = [4,5,4,5,4,5,4,5,4,5,4,5]
        for i in centerColors.indices {
            let a = Float(i) * .pi / 6
            jewel(&body, center: SIMD3(sin(a) * 0.068, -cos(a) * 0.068, 0.062),
                scale: SIMD2(0.052, 0.020), angle: a + .pi / 2, material: centerColors[i], mounted: false, settingWidth: 0.0016)
        }
        for i in 0..<60 where i % 5 != 0 {
            let a = Float(i) * .pi / 30
            let tick = (0...2).map { step -> SIMD3<Float> in
                let r = 0.319 + Float(step) / 2 * 0.029
                let p=SIMD2(sin(a)*r,-cos(a)*r)
                return SIMD3(p.x,p.y,0.0348)
            }
            body.tube(tick, radius: 0.00115, closed: false, sides: 8)
            body.sphere(center: tick.last!, radius: 0.0034, material: 1, segments: 10, rings: 6)
        }
        body.tube([SIMD3(0,0,0.023),SIMD3(0,0,0.065),SIMD3(0,0,0.105)],
            radius:0.013,closed:false,sides:20)
        body.sphere(center: SIMD3(0, 0, 0.125), radius: 0.027, material: 8, segments: 48, rings: 24)
        let hub = (0..<96).map { i -> SIMD3<Float> in
            let a = Float(i) * 2 * .pi / 96
            return SIMD3(cos(a) * 0.029, sin(a) * 0.029, 0.119)
        }
        let hubStart=body.materials.count
        body.tube(hub, radius: 0.0036, sides: 12)
        body.markEmissive(startingAt: hubStart)
        return GemstoneMeshSceneData(body: body, hand: singleHand(), pigmentDensity: 1.6)
    }

    private static func glassDial(_ mesh: inout GemstoneMesh) {
        let firstTriangle = mesh.materials.count
        let steps = 128, rings = 24
        func point(_ row: Int, _ index: Int, front: Bool) -> SIMD3<Float> {
            let r = Float(row) / Float(rings) * 0.350
            let a = Float(index) / Float(steps) * 2 * .pi
            let xy = SIMD2(cos(a) * r, sin(a) * r)
            return SIMD3(xy.x, xy.y, front ? dialHeight(xy) : dialBackHeight(xy))
        }
        // Dense smooth geometry, not a normal decal. Normals are analytic finite
        // derivatives of the mesh profile and stay consistent with the surface.
        func normal(_ row: Int, _ index: Int, front: Bool) -> SIMD3<Float> {
            if row == 0 { return SIMD3(0, 0, front ? 1 : -1) }
            let dr = point(min(rings, row + 1), index, front: front) - point(max(0, row - 1), index, front: front)
            let da = point(row, index + 1, front: front) - point(row, index - 1, front: front)
            let n = simd_normalize(simd_cross(dr, da))
            return front ? (n.z > 0 ? n : -n) : (n.z < 0 ? n : -n)
        }
        for front in [true, false] {
            for row in 0..<rings {
                for i in 0..<steps {
                    let a = point(row, i, front: front), b = point(row + 1, i, front: front)
                    let c = point(row + 1, i + 1, front: front), d = point(row, i + 1, front: front)
                    let na = normal(row, i, front: front), nb = normal(row + 1, i, front: front)
                    let nc = normal(row + 1, i + 1, front: front), nd = normal(row, i + 1, front: front)
                    mesh.triangle(a, b, c, material: 2, interior: SIMD3(0, 0, -0.002), normals: (na, nb, nc))
                    mesh.triangle(a, c, d, material: 2, interior: SIMD3(0, 0, -0.002), normals: (na, nc, nd))
                }
            }
        }
        for i in 0..<steps {
            mesh.triangle(point(rings, i, front: true), point(rings, i, front: false), point(rings, i + 1, front: false), material: 2, interior: .zero)
            mesh.triangle(point(rings, i, front: true), point(rings, i + 1, front: false), point(rings, i + 1, front: true), material: 2, interior: .zero)
        }
        mesh.sealOpticalBody(startingAt: firstTriangle)
        let rail = (0..<192).map { i -> SIMD3<Float> in
            let a = Float(i) * 2 * .pi / 192
            return SIMD3(cos(a) * 0.351, sin(a) * 0.351, 0.028)
        }
        rolledSetting(&mesh,outline:rail,width:0.0038,depthScale:2.1)
    }
}
