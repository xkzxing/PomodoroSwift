import XCTest
import CoreGraphics
@testable import PomodoroSwift

@MainActor
final class GemstoneSculptureTests: XCTestCase {
    func testDistanceFromSingleOutsidePixelIncludesDiagonals() {
        var mask = [UInt8](repeating: 255, count: 49)
        mask[0] = 0
        let distance = GemstoneDistanceField.inside(mask, width: 7, height: 7)
        XCTAssertEqual(distance[3 * 7 + 4], 5, accuracy: 0.0001)
        XCTAssertEqual(distance[6 * 7 + 6], sqrt(72), accuracy: 0.0001)
    }

    func testNarrowBezelAndBroadBodyHaveCorrectThickness() {
        var mask = [UInt8](repeating: 0, count: 49)
        for y in 1...5 { for x in 1...5 { mask[y * 7 + x] = 255 } }
        let distance = GemstoneDistanceField.inside(mask, width: 7, height: 7)
        XCTAssertEqual(distance[3 * 7 + 3], 3)
        XCTAssertEqual(distance[1 * 7 + 3], 1)
        XCTAssertEqual(distance[0], 0)
        XCTAssertEqual(GemstoneDistanceField.inside([0, 255, 0], width: 3, height: 1), [0, 1, 0])
    }

    func testEmptyAndOutsideMasksStayFinite() {
        XCTAssertTrue(GemstoneDistanceField.inside([], width: 0, height: 0).isEmpty)
        let empty = GemstoneDistanceField.inside([0, 0, 0, 0], width: 2, height: 2)
        XCTAssertEqual(empty, [0, 0, 0, 0])
    }

    func testHubOccludesTheSingleHandAndMapHasTransparentCorners() async throws {
        let maps = await GemstoneSculpture.maps.value
        let side = GemstoneSculpture.resolution
        XCTAssertEqual(maps.surfaces.width, side)
        XCTAssertEqual(maps.surfaces.height, side * 2)
        XCTAssertEqual(maps.normals.bitsPerComponent, 16)
        let data = try XCTUnwrap(maps.surfaces.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        func pixel(x: Int, y: Int, layer: Int) -> [Float] {
            let offset = ((layer * side + y) * side + x) * 8
            return (0..<4).map { channel in
                let i = offset + channel * 2
                return Float(Float16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))
            }
        }
        let hub = pixel(x: side / 2, y: side / 2, layer: 0)
        let hand = pixel(x: side / 2, y: side / 2, layer: 1)
        XCTAssertGreaterThan(hub[0], hand[0])
        XCTAssertEqual(hub[1] * 16, 8, accuracy: 0.01)
        XCTAssertEqual(pixel(x: 0, y: 0, layer: 0)[3], 0)
        // The hand atlas has one long arm above the hub, with no second arm.
        XCTAssertGreaterThan(pixel(x: side / 2, y: Int(Double(side) * 0.20), layer: 1)[3], 0.9)
        XCTAssertEqual(pixel(x: side / 2, y: Int(Double(side) * 0.80), layer: 1)[3], 0)
    }
}
