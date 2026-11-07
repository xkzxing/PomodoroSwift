import XCTest
import CoreGraphics
import Metal
@testable import PomodoroSwift

@MainActor
final class GemstoneBackdropMappingTests: XCTestCase {
    private func brightnessImage(_ draw: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data:nil,width:128,height:128,bitsPerComponent:8,bytesPerRow:512,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    func testBackgroundBrightnessMeasuresLinearLightInsteadOfEncodedGray() throws {
        let image = try brightnessImage { context in
            context.setFillColor(CGColor(srgbRed:0.5,green:0.5,blue:0.5,alpha:1))
            context.fill(CGRect(x:0,y:0,width:128,height:128))
        }
        let brightness = try GemstoneBackdropBrightness(image:image)
        let mapping = GemstoneBackdropMapping(imageSize:CGSize(width:128,height:128),
            viewportSize:CGSize(width:128,height:128),dialFrame:CGRect(x:32,y:32,width:64,height:64))
        XCTAssertEqual(brightness.mean(mapping:mapping,dialSize:CGSize(width:64,height:64)),0.214,accuracy:0.005)
    }

    func testNightGlowFollowsTheRegionBehindTheDialAndChangesContinuously() throws {
        let image = try brightnessImage { context in
            context.setFillColor(CGColor(gray:0,alpha:1));context.fill(CGRect(x:0,y:0,width:128,height:128))
            context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:64,y:0,width:64,height:128))
        }
        let brightness = try GemstoneBackdropBrightness(image:image)
        func gain(_ x:CGFloat) -> Float {
            let frame=CGRect(x:x,y:48,width:24,height:24)
            let mapping=GemstoneBackdropMapping(imageSize:CGSize(width:128,height:128),
                viewportSize:CGSize(width:128,height:128),dialFrame:frame)
            return brightness.emissionGain(mapping:mapping,dialSize:frame.size)
        }
        XCTAssertGreaterThan(gain(12),0.99)
        XCTAssertLessThan(gain(92),0.04)
        XCTAssertLessThan(abs(gain(52)-gain(52.01)),0.001)
        XCTAssertGreaterThan(gain(45),gain(57))
    }

    func testNightGlowUsesTheVisibleAspectFillCrop() throws {
        let image = try brightnessImage { context in
            context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:128,height:128))
            context.setFillColor(CGColor(gray:0,alpha:1));context.fill(CGRect(x:32,y:0,width:64,height:128))
        }
        let brightness = try GemstoneBackdropBrightness(image:image)
        let frame=CGRect(x:30,y:30,width:40,height:40)
        let mapping=GemstoneBackdropMapping(imageSize:CGSize(width:256,height:128),
            viewportSize:CGSize(width:100,height:100),dialFrame:frame)
        XCTAssertGreaterThan(brightness.emissionGain(mapping:mapping,dialSize:frame.size),0.99)
    }

    func testNightGlowDimmingIsBoundedAndMonotonic() {
        var previous:Float=1
        for index in 0...1000 {
            let gain=GemstoneBackdropBrightness.emissionGain(luminance:Float(index)/1000)
            XCTAssertGreaterThanOrEqual(gain,0.025)
            XCTAssertLessThanOrEqual(gain,previous)
            previous=gain
        }
        XCTAssertEqual(GemstoneBackdropBrightness.emissionGain(luminance:0),1)
        XCTAssertLessThan(GemstoneBackdropBrightness.emissionGain(luminance:0.18),0.11)
        XCTAssertGreaterThan(GemstoneBackdropBrightness.emissionGain(luminance:0.01),0.9)
    }

    func testMatchingAspectRatioMapsDialToWindowImage() {
        let mapping = GemstoneBackdropMapping(
            imageSize: CGSize(width: 1200, height: 800),
            viewportSize: CGSize(width: 600, height: 400),
            dialFrame: CGRect(x: 100, y: 50, width: 200, height: 200)
        )
        let center = mapping.imagePoint(for: CGPoint(x: 100, y: 100))
        XCTAssertEqual(center.x, 1.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(center.y, 0.375, accuracy: 0.00001)
    }

    func testWideBackgroundUsesTheVisibleCenteredCrop() {
        let mapping = GemstoneBackdropMapping(
            imageSize: CGSize(width: 2000, height: 1000),
            viewportSize: CGSize(width: 400, height: 400),
            dialFrame: CGRect(x: 0, y: 0, width: 400, height: 400)
        )
        XCTAssertEqual(mapping.origin.x, 0.25, accuracy: 0.00001)
        XCTAssertEqual(mapping.imagePoint(for: CGPoint(x: 400, y: 400)).x, 0.75, accuracy: 0.00001)
        XCTAssertEqual(mapping.imagePoint(for: CGPoint(x: 400, y: 400)).y, 1, accuracy: 0.00001)
    }

    func testPortraitBackgroundUsesTheVisibleCenteredCrop() {
        let mapping = GemstoneBackdropMapping(
            imageSize: CGSize(width: 1000, height: 2000),
            viewportSize: CGSize(width: 600, height: 400),
            dialFrame: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        XCTAssertEqual(mapping.origin.y, 1.0 / 3, accuracy: 0.00001)
        let center = mapping.imagePoint(for: CGPoint(x: 300, y: 200))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.00001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.00001)
    }

    func testDraggingKeepsTextureAnchoredToTheWindow() {
        let initial = GemstoneBackdropMapping(
            imageSize: CGSize(width: 1200, height: 800), viewportSize: CGSize(width: 600, height: 400),
            dialFrame: CGRect(x: 100, y: 50, width: 200, height: 200)
        )
        let moved = GemstoneBackdropMapping(
            imageSize: CGSize(width: 1200, height: 800), viewportSize: CGSize(width: 600, height: 400),
            dialFrame: CGRect(x: 160, y: 70, width: 200, height: 200)
        )
        let before = initial.imagePoint(for: CGPoint(x: 100, y: 100))
        let after = moved.imagePoint(for: CGPoint(x: 40, y: 80))
        XCTAssertEqual(before.x, after.x, accuracy: 0.00001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.00001)
        XCTAssertEqual(initial.step, moved.step)
    }

    func testEmptyInputHasFiniteNeutralSamplingCoordinates() {
        let mapping = GemstoneBackdropMapping(imageSize: .zero, viewportSize: .zero, dialFrame: .zero)
        XCTAssertEqual(mapping.origin, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(mapping.step, .zero)
    }

    func testPhotoDrawingPreservesAspectRatioAndCoversTheSameCenteredCrop() {
        let viewport=CGRect(x:120,y:40,width:600,height:600)
        for image in [CGSize(width:2560,height:1707),CGSize(width:1706,height:2560)] {
            let drawing=GemstoneBackdropMapping.aspectFillRect(imageSize:image,in:viewport)
            XCTAssertEqual(drawing.width/drawing.height,image.width/image.height,accuracy:0.000001)
            XCTAssertEqual(drawing.midX,viewport.midX,accuracy:0.000001)
            XCTAssertEqual(drawing.midY,viewport.midY,accuracy:0.000001)
            XCTAssertGreaterThanOrEqual(drawing.width,viewport.width-0.000001)
            XCTAssertGreaterThanOrEqual(drawing.height,viewport.height-0.000001)
            let map=GemstoneBackdropMapping(imageSize:image,viewportSize:viewport.size,
                dialFrame:CGRect(origin:.zero,size:viewport.size))
            XCTAssertEqual(map.origin.x,(viewport.minX-drawing.minX)/drawing.width,accuracy:0.000001)
            XCTAssertEqual(map.origin.y,(viewport.minY-drawing.minY)/drawing.height,accuracy:0.000001)
        }
    }

    func testPhotographUploadPreservesChannelsFor24BitRGBSources() throws {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {
            throw XCTSkip("A Metal device is required")
        }
        let rgb=Data([255,0,0, 0,255,0, 0,0,255, 128,128,128])
        let image=try XCTUnwrap(CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:24,bytesPerRow:6,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),
            provider:CGDataProvider(data:rgb as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let texture=try GemstoneBackgroundTexture.make(image:image,device:device,queue:queue)
        let completion=try XCTUnwrap(queue.makeCommandBuffer())
        completion.commit();completion.waitUntilCompleted()
        var actual=[UInt8](repeating:0,count:16)
        texture.getBytes(&actual,bytesPerRow:8,from:MTLRegionMake2D(0,0,2,2),mipmapLevel:0)
        XCTAssertEqual(texture.pixelFormat,.rgba8Unorm_srgb)
        let expected: [UInt8]=[255,0,0,255, 0,255,0,255, 0,0,255,255, 128,128,128,255]
        for i in expected.indices { XCTAssertLessThanOrEqual(abs(Int(actual[i])-Int(expected[i])),1,"Channel \(i)") }
    }
}
