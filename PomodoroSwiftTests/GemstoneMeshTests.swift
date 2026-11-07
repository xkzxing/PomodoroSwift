import XCTest
import simd
@testable import PomodoroSwift

@MainActor
final class GemstoneMeshTests: XCTestCase {
    private struct Point: Hashable, Comparable {
        let x: Int, y: Int, z: Int
        init(_ p: SIMD3<Float>) {
            x = Int((p.x * 1_000_000).rounded())
            y = Int((p.y * 1_000_000).rounded())
            z = Int((p.z * 1_000_000).rounded())
        }
        static func < (a: Self, b: Self) -> Bool {
            if a.x != b.x { return a.x < b.x }
            if a.y != b.y { return a.y < b.y }
            return a.z < b.z
        }
    }
    private struct Edge: Hashable {
        let a: Point, b: Point
        init(_ first: SIMD3<Float>, _ second: SIMD3<Float>) {
            let p = Point(first), q = Point(second)
            a = min(p, q); b = max(p, q)
        }
    }

    func testGemIsClosedWithConsistentOutwardWinding() {
        var mesh = GemstoneMesh()
        GemstoneMeshBuilder.jewel(&mesh, center: .zero, scale: SIMD2(0.32, 0.29), angle: 0.27, material: 4)
        var edges: [Edge: Int] = [:]
        for triangle in mesh.materials.indices where mesh.materials[triangle] == 4 {
            let v = Array(mesh.vertices[(triangle * 3)..<(triangle * 3 + 3)])
            let n = simd_cross(v[1].position - v[0].position, v[2].position - v[0].position)
            XCTAssertGreaterThan(simd_dot(n, (v[0].position + v[1].position + v[2].position) / 3), 0)
            for i in 0..<3 { edges[Edge(v[i].position, v[(i + 1) % 3].position), default: 0] += 1 }
        }
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.values.allSatisfy { $0 == 2 }, "Every optical boundary edge must have two adjacent faces")
        XCTAssertEqual(MemoryLayout<GemstoneVertex>.stride, 32)
    }

    func testFlowingStoneHasAClosedConsistentlyOrientedBoundary() {
        var mesh = GemstoneMesh()
        GemstoneMeshBuilder.flowingStone(&mesh, index: 5, count: 16, material: 4)
        var edges: [Edge: Int] = [:], winding: [Edge: Int] = [:]
        for triangle in mesh.materials.indices where mesh.materials[triangle] == 4 {
            let v = Array(mesh.vertices[(triangle * 3)..<(triangle * 3 + 3)])
            for i in 0..<3 {
                let p = v[i].position, q = v[(i + 1) % 3].position
                edges[Edge(p, q), default: 0] += 1
                winding[Edge(p, q), default: 0] += Point(p) < Point(q) ? 1 : -1
                XCTAssertTrue(v[i].normal.x.isFinite && v[i].normal.y.isFinite && v[i].normal.z.isFinite)
                XCTAssertEqual(simd_length(v[i].normal), 1, accuracy: 0.0001)
            }
        }
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.values.allSatisfy { $0 == 2 })
        XCTAssertTrue(winding.values.allSatisfy { $0 == 0 }, "Adjacent faces must traverse their shared edge in opposite directions")
    }

    private func opticalEdges(_ mesh: GemstoneMesh) -> [Edge: Int] {
        var edges: [Edge:Int]=[:]
        for triangle in mesh.materials.indices where ![UInt32(1),11,18].contains(mesh.materials[triangle]) {
            for i in 0..<3 {
                let vertex=mesh.vertices[triangle*3+i]
                XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
                XCTAssertTrue(vertex.normal.x.isFinite && vertex.normal.y.isFinite && vertex.normal.z.isFinite)
                XCTAssertEqual(simd_length(vertex.normal),1,accuracy:0.001)
                let q=mesh.vertices[triangle*3+(i+1)%3].position
                edges[Edge(vertex.position,q),default:0] += 1
            }
        }
        return edges
    }

    func testPairedCurvesShareTheirSeamAndStayClosed() {
        for index in [0,5,13] {
            var inner=GemstoneMesh(), outer=GemstoneMesh()
            GemstoneMeshBuilder.pairedMosaic(&inner,index:index,outer:false)
            GemstoneMeshBuilder.pairedMosaic(&outer,index:index,outer:true)
            XCTAssertTrue(opticalEdges(inner).values.allSatisfy{$0 == 2},"Open inner crystal in sector \(index)")
            XCTAssertTrue(opticalEdges(outer).values.allSatisfy{$0 == 2},"Open outer crystal in sector \(index)")
            func points(_ mesh:GemstoneMesh) -> Set<Point> {
                Set(mesh.vertices.enumerated().filter{![UInt32(1),11,18].contains(mesh.materials[$0.offset/3])}.map{Point($0.element.position)})
            }
            XCTAssertGreaterThanOrEqual(points(inner).intersection(points(outer)).count,50,
                "The two crystals must meet along both sides of their common seam")
        }
    }

    func testCardinalCrystalsAndMarquiseMarkersHaveClosedTips() {
        for outline in GemstoneMeshBuilder.referenceOutlines {
            var mesh=GemstoneMesh()
            GemstoneMeshBuilder.curvedCrystal(&mesh,shape:outline)
            XCTAssertTrue(opticalEdges(mesh).values.allSatisfy{$0 == 2},outline.name)
        }
        var markers=GemstoneMesh()
        GemstoneMeshBuilder.referenceHourMarkers(&markers)
        XCTAssertTrue(opticalEdges(markers).values.allSatisfy{$0 == 2})
    }

    func testBluePavilionsHaveClosedOutwardInterfacesAndPositiveThickness() {
        for (index,outer) in [(0,false),(13,false),(4,true),(9,true),(12,true)] {
            var mesh=GemstoneMesh()
            GemstoneMeshBuilder.pairedMosaic(&mesh,index:index,outer:outer)
            XCTAssertTrue(opticalEdges(mesh).values.allSatisfy{$0==2})
            var winding: [Edge:Int]=[:]
            for triangle in mesh.materials.indices where mesh.materials[triangle]==4 {
                let v=Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
                let geometric=simd_normalize(simd_cross(v[1].position-v[0].position,v[2].position-v[0].position))
                XCTAssertGreaterThan(simd_dot(geometric,v[0].normal+v[1].normal+v[2].normal),0)
                for i in 0..<3 {
                    let p=v[i].position,q=v[(i+1)%3].position
                    winding[Edge(p,q),default:0] += Point(p)<Point(q) ? 1 : -1
                }
            }
            XCTAssertFalse(winding.isEmpty)
            XCTAssertTrue(winding.values.allSatisfy{$0==0})
            for row in 0...20 {
                for column in 0...20 {
                    let u=Float(column)/20,v=Float(row)/20
                    let front=GemstoneMeshBuilder.pairedCrystalSurface(index:index,outer:outer,u:u,v:v,front:true)
                    let rear=GemstoneMeshBuilder.pairedCrystalSurface(index:index,outer:outer,u:u,v:v,front:false)
                    XCTAssertGreaterThan(front.z,rear.z)
                    XCTAssertEqual(front.x,rear.x); XCTAssertEqual(front.y,rear.y)
                }
            }
        }
    }

    func testRolledSettingHasClosedWallsAndOutwardNormals() {
        let outline=(0..<64).map { i -> SIMD3<Float> in
            let angle=Float(i)*2 * .pi/64
            return SIMD3(cos(angle)*0.2,sin(angle)*0.2,0.01)
        }
        for depthScale in [Float(1),2.1] {
            var mesh=GemstoneMesh()
            GemstoneMeshBuilder.rolledSetting(&mesh,outline:outline,width:0.004,depthScale:depthScale)
            var edges: [Edge:Int]=[:], winding: [Edge:Int]=[:]
            for triangle in mesh.materials.indices {
                let v=Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
                let geometric=simd_normalize(simd_cross(v[1].position-v[0].position,v[2].position-v[0].position))
                XCTAssertGreaterThan(simd_dot(geometric,v[0].normal+v[1].normal+v[2].normal),0)
                for i in 0..<3 {
                    let p=v[i].position,q=v[(i+1)%3].position
                    edges[Edge(p,q),default:0] += 1
                    winding[Edge(p,q),default:0] += Point(p)<Point(q) ? 1 : -1
                    XCTAssertEqual(simd_length(v[i].normal),1,accuracy:0.001)
                }
            }
            XCTAssertTrue(edges.values.allSatisfy{$0==2})
            XCTAssertTrue(winding.values.allSatisfy{$0==0})
            XCTAssertGreaterThan(mesh.vertices.map(\.position.z).max()!,0.013)
            XCTAssertLessThan(mesh.vertices.map(\.position.z).min()!,0.002)
        }
    }

    func testRadialSettingBracesAreClosedAndStayBelowTheHand() {
        for index in 0..<12 {
            var mesh = GemstoneMesh()
            GemstoneMeshBuilder.radialSettingBrace(&mesh, index: index)
            var edges: [Edge: Int] = [:], winding: [Edge: Int] = [:]
            for triangle in mesh.materials.indices {
                let v = Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
                let geometric = simd_normalize(simd_cross(v[1].position-v[0].position,v[2].position-v[0].position))
                XCTAssertGreaterThan(simd_dot(geometric,v[0].normal+v[1].normal+v[2].normal),0)
                for i in 0..<3 {
                    let p = v[i].position, q = v[(i+1)%3].position
                    edges[Edge(p,q),default:0] += 1
                    winding[Edge(p,q),default:0] += Point(p)<Point(q) ? 1 : -1
                    XCTAssertEqual(simd_length(v[i].normal),1,accuracy:0.001)
                    XCTAssertLessThan(p.z,0.083)
                }
            }
            XCTAssertTrue(edges.values.allSatisfy { $0==2 })
            XCTAssertTrue(winding.values.allSatisfy { $0==0 })
            let radii = mesh.vertices.map { simd_length(SIMD2($0.position.x,$0.position.y)) }
            XCTAssertLessThan(radii.min()!,0.117)
            XCTAssertGreaterThan(radii.max()!,0.265)
            XCTAssertLessThan(radii.max()!,0.273)
        }
    }

    func testMosaicKeepsPositiveThicknessAndSmoothRearSurface() {
        for index in 0..<GemstoneMeshBuilder.mosaicInnerMaterials.count {
            for outer in [false,true] {
                func rear(_ u: Float, _ v: Float) -> SIMD3<Float> {
                    GemstoneMeshBuilder.pairedCrystalSurface(index:index,outer:outer,u:u,v:v,front:false)
                }
                for row in 0...48 {
                    for column in 0...48 {
                        let u=Float(column)/48,v=Float(row)/48
                        let front=GemstoneMeshBuilder.pairedCrystalSurface(index:index,outer:outer,u:u,v:v,front:true)
                        XCTAssertGreaterThan(front.z-rear(u,v).z,0.020)
                    }
                }
                // Interior surface normals must stay continuous across the
                // old cut rows as well as the rest of the broad pavilion.
                let epsilon: Float=0.0001
                for v in [Float(1)/3,Float(2)/3] {
                    for column in 1..<24 {
                        let u=Float(column)/24
                        let before=(rear(u,v).z-rear(u,v-epsilon).z)/epsilon
                        let after=(rear(u,v+epsilon).z-rear(u,v).z)/epsilon
                        XCTAssertEqual(before,after,accuracy:0.003)
                    }
                }
            }
        }
    }

    func testColoredMosaicPavilionsDoNotRepeatConcaveRecesses() {
        for index in 0..<GemstoneMeshBuilder.mosaicInnerMaterials.count {
            for outer in [false,true] {
                let material=outer ? GemstoneMeshBuilder.mosaicOuterMaterials[index] : GemstoneMeshBuilder.mosaicInnerMaterials[index]
                guard material==4 || material==5 else { continue }
                for v in [Float(0.25),0.5,0.75] {
                    let heights=(0...96).map { step in
                        GemstoneMeshBuilder.pairedCrystalSurface(index:index,outer:outer,u:Float(step)/96,v:v,front:false).z
                    }
                    let trough=heights.indices.min{heights[$0]<heights[$1]}!
                    XCTAssertGreaterThan(trough,0);XCTAssertLessThan(trough,96)
                    for i in 1...trough { XCTAssertLessThanOrEqual(heights[i],heights[i-1]+0.000001) }
                    if trough<96 {
                        for i in (trough+1)...96 { XCTAssertGreaterThanOrEqual(heights[i],heights[i-1]-0.000001) }
                    }
                }
            }
        }
    }

    func testInnerCrystalLobesAreClosedAndFaceOutward() {
        for index in 0..<6 {
            var mesh=GemstoneMesh()
            GemstoneMeshBuilder.patch(&mesh,uSteps:24,vSteps:30,material:13) { u,v,front in
                GemstoneMeshBuilder.crystalLobeSurface(index:index,u:u,v:v,front:front)
            }
            XCTAssertTrue(opticalEdges(mesh).values.allSatisfy{$0==2})
            let frontFaceCount=24*30*2
            for triangle in mesh.materials.indices {
                let v=Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
                let n=simd_cross(v[1].position-v[0].position,v[2].position-v[0].position)
                XCTAssertGreaterThan(simd_dot(n,v[0].normal+v[1].normal+v[2].normal),0)
                if triangle<frontFaceCount { XCTAssertGreaterThan(n.z,0) }
                else if triangle<frontFaceCount*2 { XCTAssertLessThan(n.z,0) }
            }
        }
    }

    func testBroadInnerPanesKeepGentleParallelFacesAndPositiveThickness() {
        for index in 0..<6 {
            func point(_ u: Float,_ v: Float,_ front: Bool) -> SIMD3<Float> {
                GemstoneMeshBuilder.crystalLobeSurface(index:index,u:u,v:v,front:front)
            }
            for row in 0...32 {
                for column in 0...32 {
                    let u=Float(column)/32,v=Float(row)/32
                    let thickness=point(u,v,true).z-point(u,v,false).z
                    XCTAssertGreaterThan(thickness,0.004)
                    XCTAssertLessThan(thickness,0.012)
                }
            }
            for v in [Float(0.2),0.4,0.6,0.8] {
                for u in [Float(0.2),0.4,0.6,0.8] {
                    func normal(_ front: Bool) -> SIMD3<Float> {
                        let du=point(u+0.001,v,front)-point(u-0.001,v,front)
                        let dv=point(u,v+0.001,front)-point(u,v-0.001,front)
                        return simd_normalize(simd_cross(dv,du))
                    }
                    XCTAssertGreaterThan(simd_dot(normal(true),normal(false)),0.99,
                        "Broad panes should shift the background without adding a strong lens at each patch")
                }
            }
        }
    }

    func testCarvedBackingRemainsClosedWithSeparatedOpticalSurfaces() {
        let mesh=GemstoneMeshBuilder.dial().body
        var edges: [Edge:Int]=[:], winding: [Edge:Int]=[:]
        var heights: [Point:[Float]]=[:]
        for triangle in mesh.materials.indices where mesh.materials[triangle]==2 {
            let v=Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
            let geometric=simd_normalize(simd_cross(v[1].position-v[0].position,v[2].position-v[0].position))
            XCTAssertGreaterThan(simd_dot(geometric,v[0].normal+v[1].normal+v[2].normal),0)
            for i in 0..<3 {
                let p=v[i].position, q=v[(i+1)%3].position
                edges[Edge(p,q),default:0] += 1
                winding[Edge(p,q),default:0] += Point(p)<Point(q) ? 1 : -1
                heights[Point(SIMD3(p.x,p.y,0)),default:[]].append(p.z)
            }
        }
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.values.allSatisfy{$0==2})
        XCTAssertTrue(winding.values.allSatisfy{$0==0})
        let thicknesses=heights.values.map{$0.max()! - $0.min()!}
        XCTAssertTrue(thicknesses.allSatisfy{$0>0},"Front and rear interfaces must not cross or collapse")
        XCTAssertGreaterThan(thicknesses.max()!,thicknesses.min()! * 1.5,
            "The backing needs actual optical-depth variation, not a uniform slab")
    }

    func testPolishedNormalsAreFiniteAndFollowTheCrown() {
        var mesh = GemstoneMesh()
        GemstoneMeshBuilder.jewel(&mesh, center: .zero, scale: SIMD2(0.32, 0.29), angle: 0, material: 4)
        for triangle in mesh.materials.indices where mesh.materials[triangle] == 4 {
            let v = Array(mesh.vertices[(triangle * 3)..<(triangle * 3 + 3)])
            for vertex in v {
                XCTAssertTrue(vertex.normal.x.isFinite && vertex.normal.y.isFinite && vertex.normal.z.isFinite)
                XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.0001)
                if vertex.position.z > 0.02 { XCTAssertGreaterThan(vertex.normal.z, 0) }
                if vertex.position.z < -0.02 { XCTAssertLessThan(vertex.normal.z, 0) }
            }
        }
    }

    func testOpaqueHandHasAContinuousShaftAndClosedEnamelShell() {
        let mesh = GemstoneMeshBuilder.singleHand()
        var edges: [Edge: Int] = [:]
        let triangles = mesh.materials.indices.filter { mesh.materials[$0] == 9 }
        XCTAssertFalse(triangles.isEmpty)
        func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        func covers(_ point: SIMD2<Float>, triangle: Int) -> Bool {
            let v = (0..<3).map { mesh.vertices[triangle * 3 + $0].position }
            let a = SIMD2(v[0].x, v[0].y), b = SIMD2(v[1].x, v[1].y), c = SIMD2(v[2].x, v[2].y)
            let area = cross2(b - a, c - a)
            guard abs(area) > 1e-10 else { return false }
            let u = cross2(b - point, c - point) / area
            let vWeight = cross2(c - point, a - point) / area
            return u >= -0.0001 && vWeight >= -0.0001 && u + vWeight <= 1.0001
        }
        // Even between the hub and broad blade, a solid arm must remain visible.
        for step in 0..<27 {
            let p = SIMD2<Float>(0, -0.04 - Float(step) * 0.01)
            XCTAssertTrue(triangles.contains { covers(p, triangle: $0) }, "Missing opaque shaft at \(p.y)")
        }
        for triangle in triangles {
            for i in 0..<3 {
                let p = mesh.vertices[triangle * 3 + i].position
                let q = mesh.vertices[triangle * 3 + (i + 1) % 3].position
                edges[Edge(p, q), default: 0] += 1
            }
        }
        XCTAssertTrue(edges.values.allSatisfy { $0 == 2 })
    }

    func testSingleHandIsOneArmAboveTheDialAndBelowTheHub() {
        let scene = GemstoneMeshBuilder.dial()
        XCTAssertFalse(scene.hand.vertices.isEmpty)
        XCTAssertTrue(scene.hand.vertices.allSatisfy { $0.position.y < 0 })
        XCTAssertLessThan(scene.hand.vertices.map(\.position.y).min()!, -0.30)
        XCTAssertGreaterThan(scene.hand.vertices.map(\.position.z).min()!, 0.05)
        // The optical shader skips hand queries outside this conservative box.
        // Include every material, especially the gold rim around the blade.
        for vertex in scene.hand.vertices {
            let p = vertex.position
            XCTAssertTrue((-0.030...0.030).contains(p.x))
            XCTAssertTrue((-0.360...0.000).contains(p.y))
            XCTAssertTrue((0.083...0.116).contains(p.z))
        }
        let hubTop = scene.body.vertices.enumerated().filter { scene.body.materials[$0.offset / 3] == 8 }.map { $0.element.position.z }.max()!
        XCTAssertGreaterThan(hubTop, scene.hand.vertices.map(\.position.z).max()!)
    }

    func testHandGemIsClosedAndItsSourceKeepsTheHostMedium() {
        let mesh=GemstoneMeshBuilder.singleHand(),packed=mesh.packedBoundaries
        let gem=mesh.materials.indices.filter{mesh.materials[$0]==5}
        XCTAssertFalse(gem.isEmpty)
        let hosts=Set(gem.map{mesh.opticalBodies[$0]})
        XCTAssertEqual(hosts.count,1);XCTAssertFalse(hosts.contains(0))
        var edges:[Edge:Int]=[:]
        for triangle in gem {
            XCTAssertEqual(packed[triangle]&GemstoneMesh.emissionFlag,0,"Only the internal source should emit")
            for i in 0..<3 {
                edges[Edge(mesh.vertices[triangle*3+i].position,mesh.vertices[triangle*3+(i+1)%3].position),default:0] += 1
            }
        }
        XCTAssertTrue(edges.values.allSatisfy{$0==2})
        let source=mesh.materials.indices.filter{mesh.materials[$0]==19}
        XCTAssertFalse(source.isEmpty)
        XCTAssertTrue(source.allSatisfy{packed[$0]&GemstoneMesh.emissionFlag != 0})
        XCTAssertTrue(mesh.materials.indices.filter{mesh.materials[$0]==20}.allSatisfy{packed[$0]&GemstoneMesh.emissionFlag != 0})
        let (sources,power)=GemstonePhotonTriangle.sources(mesh)
        XCTAssertGreaterThan(power,0)
        let sourceMedia=Set(sources.filter{$0.c.w==19}.map{$0.medium.x})
        XCTAssertEqual(sourceMedia,Set(hosts.map{($0<<8)|5}))
        let points=source.flatMap{triangle in (0..<3).map{mesh.vertices[triangle*3+$0].position}}
        XCTAssertTrue(points.allSatisfy{$0.z>0.1065 && $0.z<0.108},"The light source must remain beneath the gemstone crown")
    }

    func testMovingHandAndStaticDialHaveDisjointOpticalIdentities() {
        let scene=GemstoneMeshBuilder.dial()
        let fixed=Set(scene.body.opticalBodies.filter{$0 != 0})
        let moving=Set(scene.hand.opticalBodies.filter{$0 != 0})
        XCTAssertFalse(fixed.isEmpty);XCTAssertFalse(moving.isEmpty)
        XCTAssertTrue(fixed.isDisjoint(with:moving),"Reflected rays must not mistake the hand gem for a fixed crystal")
        let boundaries=scene.hand.packedBoundaries
        for triangle in scene.hand.materials.indices {
            XCTAssertEqual((boundaries[triangle] & ~GemstoneMesh.emissionFlag)>>8,scene.hand.opticalBodies[triangle])
        }
    }

    func testEveryTransparentTriangleHasAnIndependentOpticalBoundary() {
        let mesh=GemstoneMeshBuilder.dial().body
        let boundaries=mesh.packedBoundaries
        XCTAssertEqual(mesh.opticalBodies.count,mesh.materials.count)
        XCTAssertEqual(boundaries.count,mesh.materials.count)
        var bodyMaterials:[UInt32:Set<UInt32>]=[:]
        var bodyEmission:[UInt32:Set<Bool>]=[:]
        var emittedMaterials=Set<UInt32>()
        var emittedCount=0
        for triangle in mesh.materials.indices {
            let material=mesh.materials[triangle],body=mesh.opticalBodies[triangle]
            XCTAssertEqual(boundaries[triangle]&255,material)
            XCTAssertEqual((boundaries[triangle] & ~GemstoneMesh.emissionFlag)>>8,body)
            let emits=boundaries[triangle] & GemstoneMesh.emissionFlag != 0
            if emits { emittedMaterials.insert(material);emittedCount += 1 }
            if (2...7).contains(material) || material==12 || material==13 {
                XCTAssertNotEqual(body,0,"Unlabelled transparent triangle")
                bodyMaterials[body,default:[]].insert(material)
                bodyEmission[body,default:[]].insert(emits)
            }
        }
        XCTAssertGreaterThan(bodyMaterials.count,40)
        XCTAssertTrue(bodyMaterials.values.allSatisfy{$0.count==1})
        XCTAssertTrue(bodyEmission.values.allSatisfy{$0.count==1},"Emission must cover complete optical solids")
        XCTAssertEqual(emittedMaterials,Set<UInt32>([1,14,15,18]))
        XCTAssertGreaterThan(emittedCount,1000)
        XCTAssertLessThan(emittedCount,mesh.materials.count/4,"Keep most of the dial reflective")
    }

    func testWarmGoldSourcesCoverRaisedRimsAndKeepRecessesUnlit() {
        let mesh=GemstoneMeshBuilder.dial().body
        let packed=mesh.packedBoundaries
        var goldArea:Float=0,sourceArea:Float=0,sourceCount=0
        for triangle in mesh.materials.indices where [UInt32(1),11,18].contains(mesh.materials[triangle]) {
            let a=mesh.vertices[triangle*3],b=mesh.vertices[triangle*3+1],c=mesh.vertices[triangle*3+2]
            let area=simd_length(simd_cross(b.position-a.position,c.position-a.position))*0.5
            goldArea += area
            if mesh.materials[triangle]==18 {
                sourceArea += area;sourceCount += 1
                XCTAssertNotEqual(packed[triangle]&GemstoneMesh.emissionFlag,0)
                XCTAssertGreaterThan(a.normal.z+b.normal.z+c.normal.z,2)
            }
            if mesh.materials[triangle]==11 { XCTAssertEqual(packed[triangle]&GemstoneMesh.emissionFlag,0) }
        }
        XCTAssertGreaterThan(sourceCount,1000)
        XCTAssertGreaterThan(sourceArea,goldArea*0.01,"Continuous rims must cover more than isolated glints")
        XCTAssertLessThan(sourceArea,goldArea*0.20,"Keep the gold's dark walls and most of its polished surface non-emissive")
    }

    func testWarmSettingSourceFormsAContinuousClosedBand() {
        let outline=(0..<48).map { i -> SIMD3<Float> in
            let angle=Float(i)*2 * .pi/48
            return SIMD3(cos(angle)*0.2,sin(angle)*0.15,0.01)
        }
        var mesh=GemstoneMesh()
        GemstoneMeshBuilder.rolledSetting(&mesh,outline:outline,width:0.004,warmCrest:true)
        var edges:[Edge:Int]=[:]
        for triangle in mesh.materials.indices where mesh.materials[triangle]==18 {
            for i in 0..<3 {
                edges[Edge(mesh.vertices[triangle*3+i].position,mesh.vertices[triangle*3+(i+1)%3].position),default:0] += 1
            }
        }
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.values.allSatisfy{$0==1 || $0==2})
        var boundary:[Point:Set<Point>]=[:]
        for (edge,count) in edges where count==1 {
            boundary[edge.a,default:[]].insert(edge.b)
            boundary[edge.b,default:[]].insert(edge.a)
        }
        XCTAssertTrue(boundary.values.allSatisfy{$0.count==2},"The source band must have no open ends")
        var remaining=Set(boundary.keys),loops=0
        while let start=remaining.first {
            loops += 1
            var pending=[start]
            while let point=pending.popLast() {
                guard remaining.remove(point) != nil else { continue }
                pending.append(contentsOf:boundary[point] ?? [])
            }
        }
        XCTAssertEqual(loops,2,"A continuous annular source has one inner and one outer closed boundary")
    }

    func testSameColoredStonesDoNotShareTheirMediumIdentity() {
        var mesh=GemstoneMesh()
        GemstoneMeshBuilder.jewel(&mesh,center:SIMD3(-0.1,0,0),scale:SIMD2(0.2,0.2),angle:0,material:4,withLightCore:true)
        let split=mesh.materials.count
        GemstoneMeshBuilder.jewel(&mesh,center:SIMD3(0.1,0,0),scale:SIMD2(0.2,0.2),angle:0,material:4)
        let first=Set((0..<split).filter{mesh.materials[$0]==4}.map{mesh.opticalBodies[$0]})
        let second=Set((split..<mesh.materials.count).filter{mesh.materials[$0]==4}.map{mesh.opticalBodies[$0]})
        XCTAssertEqual(first.count,1);XCTAssertEqual(second.count,1)
        XCTAssertFalse(first.contains(0));XCTAssertFalse(second.contains(0))
        XCTAssertTrue(first.isDisjoint(with:second))
        XCTAssertTrue(mesh.materials.indices.filter{mesh.materials[$0]==1}.allSatisfy{mesh.opticalBodies[$0]==0})
        let packed=mesh.packedBoundaries
        XCTAssertTrue((0..<split).filter{mesh.materials[$0]==4}.allSatisfy{packed[$0] & GemstoneMesh.emissionFlag == 0})
        let cores=(0..<split).filter{mesh.materials[$0]==15}
        XCTAssertFalse(cores.isEmpty)
        XCTAssertTrue(cores.allSatisfy{packed[$0] & GemstoneMesh.emissionFlag != 0})
        XCTAssertTrue((split..<packed.count).allSatisfy{packed[$0] & GemstoneMesh.emissionFlag == 0})
        XCTAssertTrue(mesh.materials.indices.filter{mesh.materials[$0]==1}.allSatisfy{packed[$0] & GemstoneMesh.emissionFlag == 0},"The setting must retain its original material")
    }

    func testInternalLightVeinHasClosedCapsAndConsistentWinding() {
        var mesh=GemstoneMesh()
        let points=(0...12).map { i -> SIMD3<Float> in
            let t=Float(i)/12
            return SIMD3(0.04*t,0.008*sin(t * .pi),0.002*cos(t * .pi))
        }
        GemstoneMeshBuilder.lightVein(&mesh,points:points,radius:0.001,material:14)
        XCTAssertTrue(opticalEdges(mesh).values.allSatisfy{$0==2})
        var winding:[Edge:Int]=[:]
        for triangle in mesh.materials.indices {
            let v=Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
            let n=simd_cross(v[1].position-v[0].position,v[2].position-v[0].position)
            XCTAssertGreaterThan(simd_dot(n,v[0].normal+v[1].normal+v[2].normal),0)
            for i in 0..<3 {
                let p=v[i].position,q=v[(i+1)%3].position
                winding[Edge(p,q),default:0] += Point(p)<Point(q) ? 1 : -1
            }
        }
        XCTAssertTrue(winding.values.allSatisfy{$0==0})
        XCTAssertTrue(mesh.packedBoundaries.allSatisfy{$0 & GemstoneMesh.emissionFlag != 0})
    }

    func testLightInclusionIsClosedAndPhotonSourcesKeepTheirHostMedium() {
        var mesh=GemstoneMesh()
        GemstoneMeshBuilder.jewel(&mesh,center:.zero,scale:SIMD2(0.10,0.08),angle:0.2,
            material:4,withLightCore:true)
        XCTAssertTrue(opticalEdges(mesh).values.allSatisfy{$0==2})
        XCTAssertEqual(mesh.emitterMedia.count,mesh.emissiveRanges.count)
        let (sources,power)=GemstonePhotonTriangle.sources(mesh)
        XCTAssertFalse(sources.isEmpty);XCTAssertGreaterThan(power,0)
        XCTAssertEqual(sources.last!.a.w,1,accuracy:0.000001)
        XCTAssertTrue(zip(sources,sources.dropFirst()).allSatisfy{$0.a.w <= $1.a.w})
        let parent=(mesh.opticalBodies[0]<<8)|4
        XCTAssertTrue(sources.allSatisfy{$0.medium.x==parent && $0.b.w>0})
        XCTAssertEqual(MemoryLayout<GemstonePhotonTriangle>.stride,80)
        for triangle in mesh.materials.indices where mesh.materials[triangle]==15 {
            let v=Array(mesh.vertices[(triangle*3)..<(triangle*3+3)])
            let n=simd_cross(v[1].position-v[0].position,v[2].position-v[0].position)
            XCTAssertGreaterThan(simd_dot(n,v[0].normal+v[1].normal+v[2].normal),0)
        }
    }
}
