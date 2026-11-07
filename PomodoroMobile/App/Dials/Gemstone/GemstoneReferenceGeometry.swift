import Foundation
import simd

/// Two cubic boundaries describe a complete, individually fitted crystal.
/// Coordinates are geometry measurements, not a photograph or a highlight map.
nonisolated struct GemstoneCrystalOutline: Sendable {
    let name: String
    let material: UInt32
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let left1: SIMD2<Float>
    let left2: SIMD2<Float>
    let right1: SIMD2<Float>
    let right2: SIMD2<Float>
    var breadth: Float = 1

    static func pixels(_ p: [Float], material: UInt32, name: String) -> Self {
        func point(_ i: Int) -> SIMD2<Float> {
            (SIMD2(p[i], p[i + 1]) - SIMD2(627, 600)) / 1200 * 0.97
        }
        return Self(name: name, material: material, start: point(0), end: point(2),
            left1: point(4), left2: point(6), right1: point(8), right2: point(10), breadth: 1.18)
    }

    private func cubic(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ d: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
        let s = 1 - t
        return a * (s * s * s) + b * (3 * s * s * t) + c * (3 * s * t * t) + d * (t * t * t)
    }
    func point(_ across: Float, _ along: Float) -> SIMD2<Float> {
        let a = cubic(start, left1, left2, end, along)
        let b = cubic(start, right1, right2, end, along)
        let center = (a + b) * 0.5
        return center + (a * (1 - across) + b * across - center) * breadth
    }
    var reversesAcross: Bool {
        let direction = point(0.5, 0.51) - point(0.5, 0.49)
        let width = point(1, 0.5) - point(0, 0.5)
        return direction.x * width.y - direction.y * width.x < 0
    }
    func rotated(_ angle: Float) -> Self {
        func rotate(_ p: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y)
        }
        return Self(name: name, material: material, start: rotate(start), end: rotate(end),
            left1: rotate(left1), left2: rotate(left2), right1: rotate(right1), right2: rotate(right2), breadth: breadth)
    }
}

extension GemstoneMeshBuilder {
    nonisolated static func embeddedLightInclusion(_ mesh: inout GemstoneMesh,material:UInt32,medium:UInt32,
        surface:(Float,Float,Bool)->SIMD3<Float>) {
        func middle(_ u:Float,_ v:Float)->SIMD3<Float> { (surface(u,v,true)+surface(u,v,false))*0.5 }
        // Keep the small source beneath the rolled setting. The crystal can
        // receive its light without presenting a luminous panel in its crown.
        lightInclusion(&mesh,center:middle(0.95,0.56),
            axisU:(middle(0.98,0.56)-middle(0.91,0.56))*0.35,
            axisV:(middle(0.95,0.80)-middle(0.95,0.15))*0.065,
            thickness:simd_length(surface(0.95,0.56,true)-surface(0.95,0.56,false))*0.055,
            material:material,medium:medium)
    }

    /// A closed gold setting with a rolled lip, recessed inner wall and rear
    /// flange. Its section is swept around the stone rather than drawn as wire.
    nonisolated static func rolledSetting(_ mesh: inout GemstoneMesh, outline: [SIMD3<Float>], width: Float,
                                         depthScale: Float = 1, warmCrest: Bool = false) {
        guard outline.count > 3, width > 0 else { return }
        let area = outline.indices.reduce(Float(0)) { sum, i in
            let a = outline[i], b = outline[(i + 1) % outline.count]
            return sum + a.x * b.y - a.y * b.x
        }
        let points = area > 0 ? outline : Array(outline.reversed())
        let profile: [SIMD2<Float>] = [
            SIMD2(1.25,-2.4),SIMD2(1.50,-1.2),SIMD2(1.55,-0.25),
            SIMD2(1.50,0.30),SIMD2(1.28,0.80),SIMD2(1.00,1.12),
            SIMD2(0.78,1.20),SIMD2(0.50,1.17),SIMD2(0.25,1.00),
            SIMD2(0.10,0.68),SIMD2(-0.05,0.55),SIMD2(-0.17,0.65),
            SIMD2(-0.28,0.95),SIMD2(-0.45,1.00),SIMD2(-0.62,0.78),
            SIMD2(-0.65,0.46),SIMD2(-0.48,0.20),SIMD2(-0.21,0.08),
            SIMD2(-0.08,-0.20),SIMD2(0.10,-0.69),
            SIMD2(0.02,-1.35),SIMD2(-0.16,-2.15),SIMD2(0.30,-2.44)
        ]
        var vertices: [[SIMD3<Float>]] = [], normals: [[SIMD3<Float>]] = []
        for i in points.indices {
            let previous=points[(i+points.count-1)%points.count]
            let next=points[(i+1)%points.count]
            let tangent=simd_normalize(next-previous)
            let outward=simd_normalize(SIMD3(tangent.y,-tangent.x,0))
            let shoulder=width*(0.91+0.09*cos(Float(i)/Float(points.count)*4 * .pi))
            var row: [SIMD3<Float>] = [], ns: [SIMD3<Float>] = []
            for j in profile.indices {
                let p=profile[j]
                let before=profile[(j+profile.count-1)%profile.count]
                let after=profile[(j+1)%profile.count]
                func height(_ p: SIMD2<Float>) -> Float { p.y*(p.y<0 ? depthScale : 1) }
                let d=SIMD2(after.x-before.x,height(after)-height(before))
                row.append(points[i]+outward*(p.x*shoulder)+SIMD3(0,0,height(p)*width))
                ns.append(simd_normalize(outward*d.y-SIMD3(0,0,d.x)))
            }
            vertices.append(row); normals.append(ns)
        }
        for i in points.indices {
            let next=(i+1)%points.count
            for j in profile.indices {
                let k=(j+1)%profile.count
                // The raised lip is one continuous luminous band around the
                // complete setting. Its walls and groove remain ordinary gold.
                let luminous=warmCrest && (5...6).contains(j)
                let material: UInt32 = luminous ? 18 : j < 2 || j > 19 || (8...10).contains(j) ? 11 : 1
                let firstTriangle=mesh.materials.count
                mesh.triangle(vertices[i][j],vertices[next][j],vertices[next][k],material:material,
                    normals:(normals[i][j],normals[next][j],normals[next][k]))
                mesh.triangle(vertices[i][j],vertices[next][k],vertices[i][k],material:material,
                    normals:(normals[i][j],normals[next][k],normals[i][k]))
                if luminous { mesh.markEmissive(startingAt:firstTriangle) }
            }
        }
    }

    /// The two long cardinal crystals remain separate from the paired curls.
    nonisolated static let referenceOutlines: [GemstoneCrystalOutline] = [
        .pixels([628,12,629,187,540,43,578,135,716,38,679,128], material:4, name:"twelve sapphire"),
        .pixels([628,992,628,1193,563,1053,572,1152,707,1056,684,1163], material:3, name:"six clear pendant")
    ]

    nonisolated static func crystalSurface(_ shape: GemstoneCrystalOutline, u: Float, v: Float,
                               front: Bool, base: Float, crown: Float, depth: Float, reversed: Bool? = nil) -> SIMD3<Float> {
        // A very small, closed end cap avoids collapsed parametric vertices.
        let t = 0.003 + v * 0.994
        let across = (reversed ?? shape.reversesAcross) ? 1 - u : u
        let p = shape.point(across, t)
        let dome = pow(max(0, sin(u * .pi) * sin(t * .pi)), 0.66)
        let relief: Float
        if shape.material==4 {
            relief=depth*dome*0.40*pavilionKites(u:u,v:v)
        } else if shape.material==13 {
            relief=0.0012*dome*sin(t * .pi * 3+u * .pi * 1.4)*sin(u * .pi * 2.5+t * .pi * 1.2)
        } else { relief=0 }
        return SIMD3(p.x, p.y, front ? base + crown * dome : base - 0.003 - depth * dome + relief)
    }

    nonisolated static func curvedCrystal(_ mesh: inout GemstoneMesh, shape: GemstoneCrystalOutline,
                              base: Float = 0.023, crown: Float = 0.031, depth: Float = 0.010,
                              rim: Float = 0.0023, openwork: Bool = false, withLightCore: Bool = false,
                              warmSetting: Bool = false) {
        let reversed = shape.reversesAcross
        func surface(_ u: Float, _ v: Float, _ front: Bool) -> SIMD3<Float> {
            crystalSurface(shape, u: u, v: v, front: front, base: base, crown: crown, depth: depth, reversed: reversed)
        }
        let crystalStart=mesh.materials.count
        patch(&mesh,uSteps:shape.material==4 ? 32 : 14,vSteps:shape.material==4 ? 48 : 40,
              material:shape.material,surface:surface)
        if withLightCore {
            embeddedLightInclusion(&mesh,material:shape.material==4 ? 15 : shape.material==7 ? 16 : 14,
                medium:(mesh.opticalBodies[crystalStart]<<8)|shape.material,surface:surface)
        }
        var perimeter: [SIMD3<Float>] = []
        for i in 0..<8 { perimeter.append(surface(Float(i) / 8, 0, true)) }
        for i in 0..<64 { perimeter.append(surface(1, Float(i) / 64, true)) }
        for i in 0..<8 { perimeter.append(surface(Float(8 - i) / 8, 1, true)) }
        for i in 0..<64 { perimeter.append(surface(0, Float(64 - i) / 64, true)) }
        if rim > 0.001 { rolledSetting(&mesh,outline:perimeter,width:rim,warmCrest:warmSetting) }
        else { mesh.tube(perimeter.map{$0+SIMD3(0,0,0.0004)},radius:rim,sides:8) }
        if openwork {
            for strand in [Float(0.22), 0.50, 0.78] {
                let wire = (0...40).map { i -> SIMD3<Float> in
                    let v = Float(i) / 40
                    let u = strand + sin(v * .pi * 1.5) * 0.06
                    return surface(u, v, true) + SIMD3(0, 0, 0.0002)
                }
                mesh.tube(wire, radius: 0.00029, closed: false, sides: 6)
            }
            for band in [Float(0.24), 0.49, 0.74] {
                let wire = (0...24).map { i -> SIMD3<Float> in
                    let u = Float(i) / 24
                    return surface(u, band + sin(u * .pi) * 0.07, true) + SIMD3(0, 0, 0.0002)
                }
                mesh.tube(wire, radius: 0.00021, closed: false, sides: 6)
            }
        }
    }

    nonisolated static let mosaicEdges: [Float] = [-13,11,36,64,92,120,147,173,198,221,243,267,294,321,347]
    nonisolated static let mosaicInnerMaterials: [UInt32] = [4,3,3,5,3,5,6,3,5,3,6,3,5,4]
    nonisolated static let mosaicOuterMaterials: [UInt32] = [3,5,5,3,4,3,5,3,3,4,5,5,4,3]

    /// Shallow, staggered concave cuts in the actual rear interface. Each row
    /// fades with zero slope at its ends, so the offset cannot introduce a
    /// discontinuity. The front stays polished; the returning rays see many
    /// small curved mirrors instead of one broad sinusoidal reflection.
    nonisolated static func scallopedCut(u: Float, v: Float, columns: Float, rows: Float) -> Float {
        let row = floor(v * rows)
        let along = v * rows - row
        let offset: Float = Int(row) % 2 == 0 ? 0 : 0.5
        let across = u * columns + offset + 0.12 * sin(along * .pi)
        let a = sin(across * .pi), b = sin(along * .pi)
        return a * a * b * b
    }

    /// The upright sapphire uses staggered kite faces rather than a regular
    /// grid of rounded pits. A narrow bevel keeps their row joins smooth.
    nonisolated static func pavilionKites(u: Float, v: Float) -> Float {
        let row = floor(v*4), along = v*4-row
        let offset: Float = Int(row)%2==0 ? 0 : 0.5
        let across = u*3+offset
        let x = (across-floor(across))*2-1, y = along*2-1
        let diamond = max(0,1-abs(x)-abs(y))
        func bevel(_ value: Float) -> Float {
            let t = min(1,max(0,value/0.12))
            return t*t*(3-2*t)
        }
        return diamond*bevel(diamond)*bevel(along)*bevel(1-along)
    }

    /// Both the production mesh and the optical study use this same solid.
    nonisolated static func pairedCrystalSurface(index: Int, outer: Bool, u inputU: Float,
                                                 v localV: Float, front: Bool) -> SIMD3<Float> {
        func boundary(_ number: Int, _ v: Float) -> Float {
            let i = number % mosaicInnerMaterials.count
            let strength = 0.24 + 0.16 * sin(Float(i) * 1.7)
            let curl = strength * sin(v * .pi) - (0.16 + 0.08 * cos(Float(i) * 2.3)) * cos(v * .pi)
            return mosaicEdges[number] * .pi / 180 + curl * .pi / 7
        }
        let material=outer ? mosaicOuterMaterials[index] : mosaicInnerMaterials[index]
        let u = 0.002 + inputU * 0.996
        let seam = 0.045 + 0.91 * pow(u,0.72 + 0.42 * (0.5 + 0.5*sin(Float(index)*1.4)))
        let v = outer ? seam + (1-seam)*localV : seam*localV
        let a = boundary(index,v)*(1-u) + boundary(index+1,v)*u
        let inner: Float = 0.347 + 0.002 * cos(a*12)
        let rim: Float = 0.482 + 0.008*cos(a*12+0.25) + 0.002*sin(a*24)
        let r = inner + (rim-inner)*v
        let width = outer ? 1-seam : seam
        let envelope: Float = inputU == 0 || inputU == 1 || localV == 0 || localV == 1
            ? 0 : max(0,sin(inputU * .pi)*sin(localV * .pi))
        let crown=(0.72*pow(envelope,0.46)+0.28*envelope)*sqrt(width)
        let ridge=0.0005*pow(envelope,1.2)*sin(inputU * .pi * 0.7+localV * .pi * 0.4+Float(index)*0.41)
        let pavilion: Float
        if material==4 || material==5 {
            let keel: Float = material==4 ? 0.032 : 0.026
            pavilion=pow(envelope,0.68)*sqrt(width)*keel
        } else {
            let flute=sin(inputU * .pi * 4.3 + 0.8*sin(localV * .pi * 2) + Float(index)*0.63)
                + 0.42*sin(localV * .pi * 5.2 + inputU * .pi * 1.7)
            pavilion=pow(envelope,0.75)*sqrt(width) *
                (0.019+0.0035*cos(inputU * 2 * .pi+localV * .pi+Float(index)*0.8))
                + 0.0028*envelope*flute
        }
        // Keep the broad pavilion. Repeated concave pits turn reflected room
        // detail into stamped hook shapes rather than useful gemstone facets.
        return SIMD3(sin(a)*r,-cos(a)*r,front ? 0.018+0.036*crown+ridge : -0.005-pavilion)
    }

    /// Each unequal sector contains two complementary curved crystals. The
    /// shared diagonal curls from the inner rim to the outer rim, producing
    /// hooked ends without gaps between separately fitted oval outlines.
    nonisolated static func pairedMosaic(_ mesh: inout GemstoneMesh, index: Int, outer: Bool) {
        let material=outer ? mosaicOuterMaterials[index] : mosaicInnerMaterials[index]
        func surface(_ inputU: Float, _ localV: Float, _ front: Bool) -> SIMD3<Float> {
            pairedCrystalSurface(index:index,outer:outer,u:inputU,v:localV,front:front)
        }
        // Shared samples keep the curled seam closed and resolve the crown
        // and broad rear curvature without adding repeating optical recesses.
        let crystalStart=mesh.materials.count
        patch(&mesh,uSteps:48,vSteps:36,material:material,surface:surface)
        if material==5 && index.isMultiple(of:3) {
            embeddedLightInclusion(&mesh,material:14,medium:(mesh.opticalBodies[crystalStart]<<8)|material,surface:surface)
        }
        func perimeter(inset: Float) -> [SIMD3<Float>] {
            func point(_ u: Float, _ v: Float) -> SIMD3<Float> {
                surface(inset+u*(1-inset*2),inset+v*(1-inset*2),true)
            }
            var points: [SIMD3<Float>] = []
            for i in 0..<48 { points.append(point(Float(i)/48,0)) }
            for i in 0..<32 { points.append(point(1,Float(i)/32)) }
            for i in 0..<48 { points.append(point(Float(48-i)/48,1)) }
            for i in 0..<32 { points.append(point(0,Float(32-i)/32)) }
            return points
        }
        let edge = perimeter(inset: 0)
        let settingWidth: Float=material==4 ? (outer ? 0.0082 : 0.0071) : (outer ? 0.0064 : 0.0055)
        rolledSetting(&mesh,outline:edge,width:settingWidth,warmCrest:true)
        for strand in [Float(0.31),0.70] {
            let wire = (0...40).map { i -> SIMD3<Float> in
                let u=Float(i)/40
                return surface(u,strand + sin(u * .pi * 1.6)*0.055,true)-SIMD3(0,0,0.0028)
            }
            mesh.tube(wire,radius:0.00055,closed:false,sides:8)
        }
        for band in [Float(0.28),0.66] {
            let wire = (0...22).map { i -> SIMD3<Float> in
                let v=Float(i)/22
                return surface(band+sin(v * .pi)*0.055,v,true)-SIMD3(0,0,0.0038)
            }
            mesh.tube(wire,radius:0.00038,closed:false,sides:8)
        }
        for u in [Float(0.28),0.66] {
            for v in [Float(0.31),0.70] {
                let point=surface(u+sin(v * .pi)*0.055,v+sin(u * .pi * 1.6)*0.055,true)-SIMD3(0,0,0.0038)
                mesh.sphere(center: point, radius: 0.00085, material: 1, segments: 8, rings: 6)
            }
        }
    }

    nonisolated static func referenceOuterRing(_ mesh: inout GemstoneMesh) {
        for i in 0..<14 {
            pairedMosaic(&mesh,index:i,outer:false)
            pairedMosaic(&mesh,index:i,outer:true)
        }
        for outline in referenceOutlines {
            let blue=outline.material==4
            curvedCrystal(&mesh,shape:outline,base:0.071,crown:blue ? 0.019 : 0.014,
                depth:blue ? 0.023 : 0.005,rim:blue ? 0.0040 : 0.0030,openwork:true,withLightCore:blue,warmSetting:true)
        }
        let rim = (0..<384).map { i -> SIMD3<Float> in
            let a = Float(i) * 2 * .pi / 384
            let r = 0.482 + cos(a * 12) * 0.006 + sin(a * 24) * 0.002
            return SIMD3(sin(a) * r, -cos(a) * r, 0.006)
        }
        mesh.tube(rim, radius: 0.0024, sides: 12)
        let accents: [(Float,Float,Float,UInt32)] = [
            (1005,192,-0.4,7),(1167,596,-0.5,7),(557,1165,0.5,7),
            (591,1057,1.1,7),(166,757,1.1,6),(248,199,0.8,3)
        ]
        for (x,y,angle,material) in accents {
            let center = (SIMD2(x,y) - SIMD2<Float>(627,600)) / 1200 * 0.97
            jewel(&mesh, center: SIMD3(center.x, center.y, 0.067), scale: SIMD2(0.017,0.011),
                angle: angle, material: material, mounted: false)
        }
        // These open gold loops join mounts in the spaces between the curls.
        for i in 0..<12 {
            let a = Float(i) * .pi / 6 + .pi / 18
            let points = (0..<48).map { j -> SIMD3<Float> in
                let t = Float(j) * 2 * .pi / 48
                let radial = 0.456 + cos(t) * 0.018
                let angular = a + sin(t) * 0.034
                return SIMD3(sin(angular) * radial, -cos(angular) * radial, 0.015)
            }
            mesh.tube(points, radius: 0.0010, sides: 8)
        }
    }

    nonisolated static func referenceHourMarkers(_ mesh: inout GemstoneMesh) {
        let colors:[UInt32]=[5,4,5,5,5,4,5,5,5,7,4,5]
        for i in 0..<12 {
            let leaf=GemstoneCrystalOutline(name:"marquise hour leaf",material:colors[i],
                start:SIMD2(0,-0.265),end:SIMD2(0,-0.368),
                left1:SIMD2(-0.028,-0.298),left2:SIMD2(-0.023,-0.345),
                right1:SIMD2(0.023,-0.307),right2:SIMD2(0.028,-0.348))
            curvedCrystal(&mesh,shape:leaf.rotated(Float(i) * .pi / 6),
                base:0.062,crown:0.009,depth:0.002,rim:0.0021)
        }
    }

    /// A closed, tapered gold strut connects the central setting to its hour
    /// node. A broad polished crown and dark underside give it a real section.
    nonisolated static func radialSettingBrace(_ mesh: inout GemstoneMesh, index: Int) {
        let angle = Float(index) * .pi / 6
        let points = (0...32).map { i -> SIMD3<Float> in
            let t = Float(i) / 32
            let r = 0.115 + 0.151 * t
            let offset = 0.003 * sin(t * 2 * .pi) * sin(t * .pi)
            let p = SIMD2(offset, -r)
            return SIMD3(cos(angle)*p.x-sin(angle)*p.y, sin(angle)*p.x+cos(angle)*p.y,
                0.068-0.008*t+0.003*sin(t * .pi))
        }
        let profile: [SIMD2<Float>] = [SIMD2(1,-0.55),SIMD2(1,0.10),SIMD2(0.65,0.55),SIMD2(0,0.70),
            SIMD2(-0.65,0.55),SIMD2(-1,0.10),SIMD2(-1,-0.55),SIMD2(0,-0.70)]
        var rows: [[SIMD3<Float>]] = [], normals: [[SIMD3<Float>]] = []
        for i in points.indices {
            let tangent = simd_normalize(points[min(i+1,32)]-points[max(i-1,0)])
            let side = simd_normalize(SIMD3(tangent.y,-tangent.x,0))
            let width = 0.0013 + 0.0011 * pow(1-Float(i)/32,1.5)
            rows.append(profile.map { points[i]+side*($0.x*width)+SIMD3(0,0,$0.y*width) })
            normals.append(profile.indices.map { j in
                let d = profile[(j+1)%8]-profile[(j+7)%8]
                return simd_normalize(side*d.y-SIMD3(0,0,d.x))
            })
        }
        for i in 0..<32 {
            let interior = (points[i]+points[i+1])*0.5
            for j in 0..<8 {
                let k = (j+1)%8, material: UInt32 = j>=5 ? 11 : 1
                mesh.triangle(rows[i][j],rows[i+1][j],rows[i+1][k],material:material,interior:interior,
                    normals:(normals[i][j],normals[i+1][j],normals[i+1][k]))
                mesh.triangle(rows[i][j],rows[i+1][k],rows[i][k],material:material,interior:interior,
                    normals:(normals[i][j],normals[i+1][k],normals[i][k]))
            }
        }
        for j in 0..<8 {
            let k = (j+1)%8
            mesh.triangle(points[0],rows[0][j],rows[0][k],material:11,interior:points[1])
            mesh.triangle(points[32],rows[32][j],rows[32][k],material:11,interior:points[31])
        }
    }

    nonisolated static func crystalLobeSurface(index: Int, u inputU: Float, v inputV: Float, front: Bool) -> SIMD3<Float> {
        let u=0.0015+inputU*0.997, v=0.002+inputV*0.996
        let edges: [Float]=[-30,31,91,151,212,270,330]
        func boundary(_ i: Int) -> Float {
            let strength: Float=0.14+0.018*sin(Float(i%6)*1.6)
            let curl=strength*sin(v * 2 * .pi)*sin(v * .pi)-0.025*sin(v * .pi)
            return edges[i] * .pi/180+curl
        }
        let angle=boundary(index)*(1-u)+boundary(index+1)*u
        let outer: Float=0.319-0.006*cos(u * 2 * .pi)
        let radius: Float=0.037+(outer-0.037)*v
        let envelope: Float = inputU == 0 || inputU == 1 || inputV == 0 || inputV == 1
            ? 0 : max(0,sin(inputU * .pi)*sin(inputV * .pi))
        let dome=pow(envelope,0.72)
        // The wide panes are gently bent sheets, not six biconvex lenses.
        // Sharing the camber keeps their entry/exit normals almost parallel,
        // so a detailed background remains coherent across the broad face.
        let camber=(0.0100+0.0008*sin(Float(index)*1.7))*dome
        let cut=scallopedCut(u:inputU,v:inputV,columns:5,rows:7)
        let z=front ? 0.029+camber+0.00035*envelope*sin(v * .pi * 1.1)
            : 0.023+camber*0.75-0.0008*envelope+0.00045*envelope*cut
        return SIMD3(sin(angle)*radius,-cos(angle)*radius,z)
    }

    nonisolated static func crystalPetalLayer(_ mesh: inout GemstoneMesh) {
        // Six broad curved lenses fill the inner face. Their curled side walls
        // meet at narrow gold seams instead of floating as isolated leaf shapes.
        for i in 0..<6 {
            func surface(_ u: Float, _ v: Float, _ front: Bool) -> SIMD3<Float> {
                crystalLobeSurface(index:i,u:u,v:v,front:front)
            }
            let crystalStart=mesh.materials.count
            patch(&mesh,uSteps:50,vSteps:56,material:13,surface:surface)
            let medium=(mesh.opticalBodies[crystalStart]<<8)|13
            var outline: [SIMD3<Float>] = []
            for j in 0..<32 { outline.append(surface(Float(j)/32,0,true)) }
            for j in 0..<48 { outline.append(surface(1,Float(j)/48,true)) }
            for j in 0..<32 { outline.append(surface(Float(32-j)/32,1,true)) }
            for j in 0..<48 { outline.append(surface(0,Float(48-j)/48,true)) }
            rolledSetting(&mesh,outline:outline,width:0.00125)
            for band in [Float(0.24),0.44,0.64,0.84] {
                let wire=(0...32).map { j -> SIMD3<Float> in
                    let u=Float(j)/32
                    return surface(u,band+sin(u * .pi)*0.025,false)+SIMD3(0,0,0.00065)
                }
                let wireStart=mesh.materials.count
                mesh.tube(wire,radius:0.00047,closed:false,sides:8)
                if band == 0.44 { mesh.markEmissive(startingAt:wireStart,inside:medium) }
            }
            for lane in [Float(0.32),0.68] {
                let wire=(0...32).map { j -> SIMD3<Float> in
                    let v=Float(j)/32
                    return surface(lane+sin(v * .pi)*0.04,v,false)+SIMD3(0,0,0.00065)
                }
                let wireStart=mesh.materials.count
                mesh.tube(wire,radius:0.00032,closed:false,sides:8)
                if lane == 0.32 { mesh.markEmissive(startingAt:wireStart,inside:medium) }
            }
        }
    }
}
