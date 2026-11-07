import XCTest
@testable import PomodoroSwift

final class GemstoneRayCacheTests: XCTestCase {
    func testHandRotationKeepsTheStaticScene() {
        var first = GemstoneRayUniforms()
        first.sizeAndAngle = SIMD4(440, 440, 0, 4.8)
        var rotated = first
        rotated.sizeAndAngle.z = .pi * 0.7
        rotated.cache.y = GemstoneRayUniforms.handMask(degrees: 126)
        rotated.visibility = GemstoneRayUniforms.handVisibility(degrees: 126)
        XCTAssertTrue(first.hasSameScene(as: rotated))
    }

    func testPositionSizeBackgroundMappingAndCameraInvalidateTheScene() {
        let first = GemstoneRayUniforms()
        let changes: [(inout GemstoneRayUniforms) -> Void] = [
            { $0.sizeAndAngle.x = 1 }, { $0.sizeAndAngle.y = 1 }, { $0.sizeAndAngle.w = 1 },
            { $0.mapping.x = 1 }, { $0.mapping.y = 1 }, { $0.mapping.z = 1 }, { $0.mapping.w = 1 },
            { $0.scene.x = 1 }, { $0.scene.y = 1 }, { $0.scene.z = 1 }, { $0.scene.w = 1 },
            { $0.camera.x = 1 }, { $0.camera.y = 1 }, { $0.lighting.x = 0.2 }, { $0.lighting.y = 0 }
        ]
        for change in changes {
            var updated = first
            change(&updated)
            XCTAssertFalse(first.hasSameScene(as: updated))
        }
    }

    func testAngularBinsWrapAtTwelveAndHandleReverseAngles() {
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: 0), 1)
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: 360), 1)
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: -360), 1)
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: 359.999), 1 << 31)
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: -0.001), 1 << 31)
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: 90), 1 << 8)
        XCTAssertEqual(GemstoneRayUniforms.handMask(degrees: .nan), .max)
    }

    func testCadenceMatchesSessionSpeedAndDisplayResolution() {
        let normal = GemstoneClockCadence.interval(duration: 1500, diameter: 440, displayScale: 2)
        let short = GemstoneClockCadence.interval(duration: 300, diameter: 440, displayScale: 2)
        XCTAssertEqual(normal, 0.25)
        XCTAssertLessThan(short, normal)
        XCTAssertGreaterThanOrEqual(short, 1.0 / 30)
        XCTAssertEqual(GemstoneClockCadence.interval(duration: 1, diameter: 440, displayScale: 2), 1.0 / 30)
        XCTAssertGreaterThanOrEqual(GemstoneClockCadence.interval(duration: 300, diameter: 160, displayScale: 2), short)
        XCTAssertGreaterThanOrEqual(GemstoneClockCadence.interval(duration: 300, diameter: 440, displayScale: 1), short)
    }

    func testFineVisibilityBinsWrapAcrossEveryWordBoundary() {
        for bin in 0..<128 {
            let degrees = (Double(bin) + 0.5) * 360 / 128
            var expected = SIMD4<UInt32>(repeating: 0)
            expected[bin / 32] = 1 << (bin % 32)
            XCTAssertEqual(GemstoneRayUniforms.handVisibility(degrees: degrees), expected)
            XCTAssertEqual(GemstoneRayUniforms.handVisibility(degrees: degrees + 360), expected)
            XCTAssertEqual(GemstoneRayUniforms.handVisibility(degrees: degrees - 360), expected)
        }
        XCTAssertEqual(GemstoneRayUniforms.handVisibility(degrees: 0), SIMD4(1,0,0,0))
        XCTAssertEqual(GemstoneRayUniforms.handVisibility(degrees: -0.001), SIMD4(0,0,0,1 << 31))
        XCTAssertEqual(GemstoneRayUniforms.handVisibility(degrees: .nan), SIMD4(repeating: .max))
        XCTAssertEqual(MemoryLayout<GemstoneRayUniforms>.stride, 112)
    }
}
