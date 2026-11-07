import UIKit
import MetalKit
import SwiftUI
import OSLog

/// A small native Metal surface keeps numerical maps in RGBA16Float. Passing
/// them through SwiftUI's image shader arguments would apply image color-space
/// conversions, and prevents controlling their filtering and precision.
struct GemstoneMetalSurface: UIViewRepresentable {
    let maps: GemstoneSurfaceMaps
    let background: UIImage
    let viewportSize: CGSize
    var backgroundPosition: CGFloat = 0.5
    let dialFrame: CGRect
    let handDegrees: Double

    func makeUIView(context: Context) -> GemstoneMetalView {
        let view = GemstoneMetalView(frame: .zero)
        view.install(maps: maps)
        return view
    }

    func updateUIView(_ view: GemstoneMetalView, context: Context) {
        view.update(background: background, viewport: viewportSize, backgroundPosition: backgroundPosition, frame: dialFrame, handDegrees: handDegrees)
    }
}

@MainActor
final class GemstoneMetalView: MTKView {
    private var renderer: GemstoneMetalRenderer?

    init(frame: CGRect) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 60
        isOpaque = false; isUserInteractionEnabled = false; layer.isOpaque = false
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(maps: GemstoneSurfaceMaps) {
        do {
            renderer = try GemstoneMetalRenderer(view: self, maps: maps)
            delegate = renderer
        } catch {
            Logger(subsystem: "xkzxing.PomodoroSwift", category: "Gemstone").error("Cannot create gemstone renderer: \(error.localizedDescription)")
        }
    }

    func update(background: UIImage, viewport: CGSize, backgroundPosition: CGFloat = 0.5, frame: CGRect, handDegrees: Double) {
        renderer?.update(background: background, viewport: viewport, backgroundPosition: backgroundPosition, frame: frame, handDegrees: handDegrees)
        setNeedsDisplay()
    }
}

@MainActor
private final class GemstoneMetalRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var sizeAndAngle = SIMD4<Float>(repeating: 0)
        var mapping = SIMD4<Float>(repeating: 0)
        var scene = SIMD4<Float>(repeating: 0)
    }
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let normalMap: MTLTexture
    private let lighting: MTLTexture
    private let surfaceMap: MTLTexture
    private var backdrop: MTLTexture?
    private var backgroundIdentity: ObjectIdentifier?
    private var uniforms = Uniforms()

    init(view: MTKView, maps: GemstoneSurfaceMaps) throws {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "gemstoneVertex"),
              let fragment = library.makeFunction(name: "gemstoneFragment") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.device = device
        self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        normalMap = try Self.numericTexture(device: device, image: maps.normals)
        surfaceMap = try Self.numericTexture(device: device, image: maps.surfaces)
        lighting = try GemstoneLightingTexture.make(device: device, queue: queue)
        super.init()
    }

    private static func numericTexture(device: MTLDevice, image: CGImage) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
            width: image.width, height: image.height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
            withBytes: bytes, bytesPerRow: image.bytesPerRow)
        return texture
    }

    func update(background: UIImage, viewport: CGSize, backgroundPosition: CGFloat = 0.5, frame: CGRect, handDegrees: Double) {
        let identity = ObjectIdentifier(background)
        if identity != backgroundIdentity {
            if let image = background.cgImage {
                do {
                    backdrop = try GemstoneBackgroundTexture.make(image:image,device:device,queue:queue)
                    backgroundIdentity = identity
                } catch {
                    Logger(subsystem: "xkzxing.PomodoroSwift", category: "Gemstone").error("Cannot load gemstone background: \(error.localizedDescription)")
                }
            }
        }
        let mapping = GemstoneBackdropMapping(imageSize: background.size, viewportSize: viewport, dialFrame: frame, horizontalPosition: backgroundPosition)
        uniforms.sizeAndAngle = SIMD4(Float(frame.width), Float(frame.height), Float(handDegrees * .pi / 180), 0)
        uniforms.mapping = SIMD4(Float(mapping.origin.x), Float(mapping.origin.y), Float(mapping.step.width), Float(mapping.step.height))
        uniforms.scene = SIMD4(Float(frame.minX), Float(frame.minY), Float(viewport.width), Float(viewport.height))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard UIApplication.shared.applicationState == .active else { return }
        guard uniforms.sizeAndAngle.x > 0, let backdrop,
              let renderPass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(backdrop, index: 0)
        encoder.setFragmentTexture(normalMap, index: 1)
        encoder.setFragmentTexture(surfaceMap, index: 2)
        encoder.setFragmentTexture(lighting, index: 3)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}
