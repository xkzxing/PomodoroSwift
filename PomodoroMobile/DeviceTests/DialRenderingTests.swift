import CoreGraphics
import Metal
import SwiftUI
import UIKit
import XCTest
@testable import PomodoroMobile

@MainActor
final class DialRenderingTests: XCTestCase {
    private func device() throws -> MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Metal device is required")
    }

    private func attach(_ data: Data, width: Int, name: String) throws {
        let image = try XCTUnwrap(CGImage(width: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 256)).image { context in
            UIColor(red: 0.6, green: 0.73, blue: 0.86, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 256))
            UIColor(red: 0.92, green: 0.72, blue: 0.42, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 128, width: 128, height: 128))
            UIColor(white: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 32, y: 0, width: 6, height: 256))
        }
    }

    func testDigitalGlyphsFitAndFallbackToAvailableFont() {
        for name in ["HelveticaNeue", "Courier", "font-that-does-not-exist"] {
            for text in ["25:00", "120:00", "00:01"] {
                let rect = CGRect(x: 0, y: 0, width: 260, height: 110)
                let path = DigitalTimerPath.make(text: text, fontName: name, fontSize: 160, in: rect)
                XCTAssertFalse(path.isEmpty)
                XCTAssertTrue(rect.insetBy(dx: -0.1, dy: -0.1).contains(path.boundingRect))
                XCTAssertEqual(path.boundingRect.midX, rect.midX, accuracy: 0.1)
                XCTAssertEqual(path.boundingRect.midY, rect.midY, accuracy: 0.1)
            }
        }
    }

    func testDigitalGlassRendersOnPhone() async throws {
        let suite = "DialRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let style = CanvasStyle(defaults: defaults, directory: FileManager.default.temporaryDirectory)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView:
            ZStack {
                CanvasBackdrop()
                MobileDigitalDial(time: "25:00").frame(width: 320, height: 160)
            }.environmentObject(style))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(1))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "digital-glass-on-phone"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testBackdropCropMatchesPhoneSelection() {
        let size = CGSize(width: 1000, height: 500)
        let viewport = CGSize(width: 300, height: 600)
        let dial = CGRect(x: 30, y: 80, width: 240, height: 240)
        let left = GemstoneBackdropMapping(imageSize: size, viewportSize: viewport, dialFrame: dial, horizontalPosition: 0)
        let right = GemstoneBackdropMapping(imageSize: size, viewportSize: viewport, dialFrame: dial, horizontalPosition: 1)
        XCTAssertGreaterThan(right.origin.x, left.origin.x)
        XCTAssertEqual(left.step, right.step)
        XCTAssertEqual(right.origin.y, left.origin.y)
    }

    func testGemstoneNativeSurfaceCompositesOnPhone() async throws {
        if GemstoneRayResources.supported { _ = try await GemstoneRayResources.dial.value }
        let suite = "GemstoneNativeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let style = CanvasStyle(defaults: defaults, directory: FileManager.default.temporaryDirectory)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView:
            ZStack {
                CanvasBackdrop(tracksFrame: true)
                MobileGemstoneDial(timer: FocusTimer(), diameter: 300)
            }.environmentObject(style))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(4))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "gemstone-native-phone"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(style.backdropFrame.width, 0)
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testLegacyGeometryAndLightingResourcesLoadOnPhone() async throws {
        let maps = await GemstoneSculpture.maps.value
        XCTAssertEqual(maps.normals.width, 1536)
        XCTAssertEqual(maps.surfaces.height, 3072)
        let device = try device()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let lighting = try GemstoneLightingTexture.make(device: device, queue: queue)
        XCTAssertEqual(lighting.width, 1024)
        XCTAssertEqual(lighting.height, 512)
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        XCTAssertNotNil(library.makeFunction(name: "gemstoneFragment"))
        XCTAssertNotNil(library.makeFunction(name: "gemstoneVertex"))
    }

    func testRayTracingDrawsColoredCrystalsAndMovesHandOnPhone() async throws {
        let device = try device()
        guard device.supportsRaytracingFromRender else { throw XCTSkip("Hardware ray tracing unavailable; the app uses its legacy renderer.") }
        let resources = try await GemstoneRayResources.dial.value
        XCTAssertGreaterThan(resources.body.triangleCount, 0)
        XCTAssertGreaterThan(resources.hand.triangleCount, 0)
        let texture = try GemstoneBackgroundTexture.make(image: photo().cgImage!, device: device, queue: resources.queue)
        let first = try await render(resources, background: texture, degrees: 0)
        let second = try await render(resources, background: texture, degrees: 90)
        XCTAssertNotEqual(first, second, "The rendered hand must move")
        let bytes = [UInt8](first)
        let covered = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 20 }.count
        let colorful = stride(from: 0, to: bytes.count, by: 4).filter {
            max(bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) - min(bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) > 15
        }.count
        XCTAssertGreaterThan(covered, 1000)
        XCTAssertGreaterThan(colorful, 500)
        try attach(first, width: 192, name: "gemstone-ray-phone-zero")
        try attach(second, width: 192, name: "gemstone-ray-phone-quarter")
    }

    private func render(_ resources: GemstoneRayResources, background: MTLTexture, degrees: Double) async throws -> Data {
        let side = 192
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: side, height: side, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
        let target = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        var uniforms = GemstoneRayUniforms()
        uniforms.sizeAndAngle = SIMD4(Float(side), Float(side), Float(degrees * .pi / 180), resources.pigmentDensity)
        uniforms.mapping = SIMD4(0.1, 0.15, 1 / 300.0, 1 / 600.0)
        uniforms.scene = SIMD4(30, 80, 300, 600)
        uniforms.cache = SIMD4(0, GemstoneRayUniforms.handMask(degrees: degrees), UInt32(side), UInt32(side))
        uniforms.visibility = GemstoneRayUniforms.handVisibility(degrees: degrees)
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GemstoneRayUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(resources.body.vertices, offset: 0, index: 1)
        encoder.setFragmentBuffer(resources.body.materials, offset: 0, index: 2)
        encoder.setFragmentBuffer(resources.hand.vertices, offset: 0, index: 3)
        encoder.setFragmentBuffer(resources.hand.materials, offset: 0, index: 4)
        encoder.setFragmentAccelerationStructure(resources.body.acceleration, bufferIndex: 5)
        encoder.setFragmentAccelerationStructure(resources.hand.acceleration, bufferIndex: 6)
        encoder.setFragmentTexture(background, index: 0)
        encoder.setFragmentTexture(resources.illumination, index: 3)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding(); command.commit()
        await command.completed()
        if let error = command.error { throw error }
        var result = Data(count: side * side * 4)
        result.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        }
        return result
    }
}
