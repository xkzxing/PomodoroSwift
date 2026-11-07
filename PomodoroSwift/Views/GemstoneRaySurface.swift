import AppKit
import MetalKit
import SwiftUI
import OSLog

nonisolated enum GemstoneBackgroundTexture {
    /// Normalize camera/JPEG pixel layouts and colour profiles explicitly.
    /// The shader always receives RGBA sRGB bytes; the texture converts them
    /// to linear light on sampling. Numeric geometry textures stay untouched.
    static func make(image: CGImage, device: MTLDevice, queue: MTLCommandQueue) throws -> MTLTexture {
        let width=image.width,height=image.height
        guard let space=CGColorSpace(name:CGColorSpace.sRGB),
              let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:space,bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes=context.data else { throw CocoaError(.fileReadCorruptFile) }
        context.setBlendMode(.copy)
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,
            width:width,height:height,mipmapped:true)
        descriptor.storageMode = .shared;descriptor.usage = .shaderRead
        guard let texture=device.makeTexture(descriptor:descriptor),let command=queue.makeCommandBuffer(),
              let blit=command.makeBlitCommandEncoder() else { throw CocoaError(.fileReadCorruptFile) }
        texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:bytes,bytesPerRow:width*4)
        blit.generateMipmaps(for:texture);blit.endEncoding();command.commit()
        // Later draws use this same queue and therefore see complete mipmaps.
        return texture
    }
}

nonisolated struct GemstoneRayGeometry: @unchecked Sendable {
    let vertices: MTLBuffer
    let materials: MTLBuffer
    let acceleration: MTLAccelerationStructure
    let triangleCount: Int

    init(mesh: GemstoneMesh, device: MTLDevice, command: MTLCommandBuffer) throws {
        let boundaries = mesh.packedBoundaries
        guard !mesh.vertices.isEmpty, mesh.materials.count * 3 == mesh.vertices.count,
              mesh.opticalBodies.count == mesh.materials.count,
              let vertices = mesh.vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
              let materials = boundaries.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.vertices = vertices; self.materials = materials
        triangleCount = mesh.materials.count
        let triangles = MTLAccelerationStructureTriangleGeometryDescriptor()
        triangles.vertexBuffer = vertices
        triangles.vertexStride = MemoryLayout<GemstoneVertex>.stride
        triangles.vertexFormat = .float3
        triangles.triangleCount = triangleCount
        triangles.opaque = true
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [triangles]
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let acceleration = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate),
              let encoder = command.makeAccelerationStructureCommandEncoder() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        encoder.build(accelerationStructure: acceleration, descriptor: descriptor, scratchBuffer: scratch, scratchBufferOffset: 0)
        encoder.endEncoding()
        self.acceleration = acceleration
    }
}

nonisolated struct GemstonePhotonTriangle {
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var c: SIMD4<Float>
    var normal: SIMD4<Float>
    var medium: SIMD4<UInt32>

    static func radiance(_ material:UInt32,at point:SIMD3<Float> = .zero)->SIMD3<Float> {
        switch material {
        case 14: return SIMD3(2.0,26,34)*320
        case 15: return SIMD3(1.2,6,32)*320
        case 16: return SIMD3(32,0.08,0.6)*32
        case 18: return SIMD3(4.2,2.15,0.55)*(1+0.34*min(1,max(-1,-1.35*point.x-point.y)))
        case 19: return SIMD3(0.12,1.65,2.4)
        case 20: return SIMD3(2.4,1.45,0.48)
        default: return SIMD3(1,0.38,0.055)
        }
    }
    static func sources(_ mesh:GemstoneMesh)->([Self],Float) {
        var result:[Self]=[],total:Float=0
        for (group,range) in mesh.emissiveRanges.enumerated() {
            for triangle in range {
                let p=mesh.vertices[triangle*3],q=mesh.vertices[triangle*3+1],r=mesh.vertices[triangle*3+2]
                let area=simd_length(simd_cross(q.position-p.position,r.position-p.position))*0.5
                let material=mesh.materials[triangle],color=radiance(material,at:(p.position+q.position+r.position)/3)
                let luminance=simd_dot(color,SIMD3(0.2126,0.7152,0.0722))
                guard area>0,luminance>0 else { continue }
                total += area * .pi * luminance
                let n=simd_normalize(p.normal+q.normal+r.normal)
                result.append(Self(a:SIMD4(p.position,total),b:SIMD4(q.position,luminance),
                    c:SIMD4(r.position,Float(material)),normal:SIMD4(n,0),medium:SIMD4(mesh.emitterMedia[group],0,0,0)))
            }
        }
        if total>0 { for index in result.indices { result[index].a.w /= total } }
        return (result,total)
    }
}

nonisolated struct GemstoneRayResources: @unchecked Sendable {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let cachePipeline: MTLRenderPipelineState
    let compositePipeline: MTLRenderPipelineState
    let body: GemstoneRayGeometry
    let hand: GemstoneRayGeometry
    let pigmentDensity: Float
    let illumination: MTLTexture
    let illuminationBakeMilliseconds: Double

    private static func bakeIllumination(mesh:GemstoneMesh,body:GemstoneRayGeometry,device:MTLDevice,
        queue:MTLCommandQueue,library:MTLLibrary,density:Float) async throws -> (MTLTexture,Double) {
        let (sources,power)=GemstonePhotonTriangle.sources(mesh)
        let d=MTLTextureDescriptor()
        d.textureType = .type3D;d.pixelFormat = .rgba16Float
        d.width=sources.isEmpty ? 1 : 128;d.height=d.width;d.depth=sources.isEmpty ? 1 : 32
        d.usage=[.shaderRead,.shaderWrite];d.storageMode = .shared
        guard let field=device.makeTexture(descriptor:d) else { throw CocoaError(.fileReadCorruptFile) }
        if sources.isEmpty {
            var zero=SIMD4<Float16>(repeating:0)
            field.replace(region:MTLRegionMake3D(0,0,0,1,1,1),mipmapLevel:0,slice:0,
                withBytes:&zero,bytesPerRow:8,bytesPerImage:8)
            return (field,0)
        }
        guard let shoot=library.makeFunction(name:"gemstonePhotonTrace"),
              let resolve=library.makeFunction(name:"gemstonePhotonResolve"),
              let sourceBuffer=sources.withUnsafeBytes({device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),
              let accumulation=device.makeBuffer(length:d.width*d.height*d.depth*3*4,options:.storageModePrivate),
              let command=queue.makeCommandBuffer(),let clear=command.makeBlitCommandEncoder()
        else { throw CocoaError(.featureUnsupported) }
        let shootPipeline=try await device.makeComputePipelineState(function:shoot)
        let resolvePipeline=try await device.makeComputePipelineState(function:resolve)
        clear.fill(buffer:accumulation,range:0..<accumulation.length,value:0);clear.endEncoding()
        let photonCount=1048576
        var parameters=SIMD4<Float>(Float(photonCount),Float(sources.count),power,density)
        let trace=command.makeComputeCommandEncoder()!
        trace.setComputePipelineState(shootPipeline)
        trace.setBytes(&parameters,length:MemoryLayout<SIMD4<Float>>.stride,index:0)
        trace.setBuffer(body.vertices,offset:0,index:1);trace.setBuffer(body.materials,offset:0,index:2)
        trace.setAccelerationStructure(body.acceleration,bufferIndex:5)
        trace.setBuffer(sourceBuffer,offset:0,index:7);trace.setBuffer(accumulation,offset:0,index:8)
        trace.dispatchThreads(MTLSize(width:photonCount,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:64,height:1,depth:1))
        trace.endEncoding()
        let output=command.makeComputeCommandEncoder()!
        output.setComputePipelineState(resolvePipeline)
        output.setBuffer(accumulation,offset:0,index:0);output.setTexture(field,index:0)
        output.dispatchThreads(MTLSize(width:d.width,height:d.height,depth:d.depth),threadsPerThreadgroup:MTLSize(width:4,height:4,depth:4))
        output.endEncoding();command.commit();await command.completed()
        if let error=command.error { throw error }
        return (field,(command.gpuEndTime-command.gpuStartTime)*1000)
    }

    static let supported: Bool = MTLCreateSystemDefaultDevice()?.supportsRaytracingFromRender ?? false
    // Retain the completed GPU resources only. Caching the mesh-building task
    // too would keep every CPU vertex/index/material array alive after upload.
    static let study = Task.detached(priority: .userInitiated) {
        try await make(scene: GemstoneMeshBuilder.study())
    }
    static let dial = Task.detached(priority: .userInitiated) {
        try await make(scene: GemstoneMeshBuilder.dial())
    }

    static func make(scene: GemstoneMeshSceneData, libraryURL: URL? = nil) async throws -> GemstoneRayResources {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsRaytracingFromRender,
              let queue = device.makeCommandQueue() else { throw CocoaError(.featureUnsupported) }
        let library: MTLLibrary
        if let libraryURL { library = try device.makeLibrary(URL: libraryURL) }
        else if let bundled = device.makeDefaultLibrary() { library = bundled }
        else { throw CocoaError(.fileNoSuchFile) }
        guard let vertex = library.makeFunction(name: "gemstoneRayVertex"),
              let fragment = library.makeFunction(name: "gemstoneRayFragment"),
              let cacheFragment = library.makeFunction(name: "gemstoneRayCacheFragment"),
              let compositeFragment = library.makeFunction(name: "gemstoneRayCompositeFragment") else { throw CocoaError(.featureUnsupported) }
        func descriptor(_ function: MTLFunction, cache: Bool = false) -> MTLRenderPipelineDescriptor {
            let result = MTLRenderPipelineDescriptor()
            result.vertexFunction = vertex; result.fragmentFunction = function
            result.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            if cache { result.colorAttachments[1].pixelFormat = .rgba32Uint }
            let attachment = result.colorAttachments[0]!
            attachment.isBlendingEnabled = !cache
            attachment.sourceRGBBlendFactor = .one; attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one; attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return result
        }
        let pipeline = try await device.makeRenderPipelineState(descriptor: descriptor(fragment))
        let cachePipeline = try await device.makeRenderPipelineState(descriptor: descriptor(cacheFragment, cache: true))
        let compositePipeline = try await device.makeRenderPipelineState(descriptor: descriptor(compositeFragment))
        guard let command = queue.makeCommandBuffer() else { throw CocoaError(.fileReadCorruptFile) }
        let body = try GemstoneRayGeometry(mesh: scene.body, device: device, command: command)
        let hand = try GemstoneRayGeometry(mesh: scene.hand, device: device, command: command)
        command.commit()
        await command.completed()
        if let error = command.error { throw error }
        let (illumination,bakeTime)=try await bakeIllumination(mesh:scene.body,body:body,device:device,
            queue:queue,library:library,density:scene.pigmentDensity)
        return GemstoneRayResources(device: device, queue: queue, pipeline: pipeline, cachePipeline: cachePipeline,
            compositePipeline: compositePipeline, body: body, hand: hand, pigmentDensity: scene.pigmentDensity,
            illumination:illumination,illuminationBakeMilliseconds:bakeTime)
    }
}

nonisolated struct GemstoneRayUniforms: Equatable, Sendable {
    var sizeAndAngle = SIMD4<Float>(repeating: 0)
    var mapping = SIMD4<Float>(repeating: 0)
    var scene = SIMD4<Float>(repeating: 0)
    var camera = SIMD4<Float>(repeating: 0)
    // Local emitter gain and photographic transmission lift are independent.
    var lighting = SIMD4<Float>(1, 1, 0, 0)
    var cache = SIMD4<UInt32>(repeating: 0)
    var visibility = SIMD4<UInt32>(repeating: 0)

    func hasSameScene(as other: Self) -> Bool {
        sizeAndAngle.x == other.sizeAndAngle.x && sizeAndAngle.y == other.sizeAndAngle.y
            && sizeAndAngle.w == other.sizeAndAngle.w && mapping == other.mapping
            && scene == other.scene && camera == other.camera && lighting == other.lighting
    }

    static func handMask(degrees: Double) -> UInt32 {
        guard degrees.isFinite else { return .max }
        let angle = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return 1 << min(31, Int(angle / 360 * 32))
    }

    static func handVisibility(degrees: Double) -> SIMD4<UInt32> {
        guard degrees.isFinite else { return SIMD4(repeating: .max) }
        let angle = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let bin = min(127, Int(angle / 360 * 128))
        var result = SIMD4<UInt32>(repeating: 0)
        result[bin / 32] = 1 << (bin % 32)
        return result
    }
}

/// The mesh, acceleration structures and pipeline are built off the main thread
/// once. A drag submits only a new camera/background parameter block.
struct Gemstone3DView: View {
    var scene: GemstoneMeshScene = .dial
    let background: NSImage
    let viewportSize: CGSize
    var handDegrees: Double = 0
    var cameraTilt: SIMD2<Float> = .zero
    @State private var resources: GemstoneRayResources?
    @State private var dialFrame = CGRect.zero

    var body: some View {
        GeometryReader { geometry in
            let viewport = viewportSize == .zero ? geometry.size : viewportSize
            ZStack {
                if let resources {
                    GemstoneRayNativeSurface(resources: resources, background: background, viewportSize: viewport,
                        dialFrame: dialFrame, handDegrees: handDegrees, cameraTilt: cameraTilt)
                        .id(ObjectIdentifier(resources.body.acceleration))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("gemstoneBackdrop")) } action: { frame in
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { dialFrame = frame }
            }
        }
        .task(id: scene) {
            do { resources = try await (scene == .study ? GemstoneRayResources.study : GemstoneRayResources.dial).value }
            catch { Logger(subsystem: "xkzxing.PomodoroSwift", category: "Gemstone").error("Cannot build 3D jewel: \(error.localizedDescription)") }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GemstoneRayNativeSurface: NSViewRepresentable {
    let resources: GemstoneRayResources
    let background: NSImage
    let viewportSize: CGSize
    let dialFrame: CGRect
    let handDegrees: Double
    let cameraTilt: SIMD2<Float>
    func makeNSView(context: Context) -> GemstoneRayView { GemstoneRayView(resources: resources) }
    func updateNSView(_ view: GemstoneRayView, context: Context) {
        view.update(background: background, viewport: viewportSize, frame: dialFrame,
                    handDegrees: handDegrees, cameraTilt: cameraTilt)
    }
}

@MainActor
private final class GemstoneRayView: MTKView {
    let renderer: GemstoneRayRenderer
    private var cacheTask: Task<Void, Never>?
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(resources: GemstoneRayResources) {
        renderer = GemstoneRayRenderer(resources: resources)
        super.init(frame: .zero, device: resources.device)
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true; isPaused = true; enableSetNeedsDisplay = true
        autoResizeDrawable = false
        layer?.isOpaque = false; delegate = renderer
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { cacheTask?.cancel() }

    func scheduleCacheBuild() {
        renderer.wantsCacheBuild = false
        cacheTask?.cancel()
        cacheTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard let self else { return }
            renderer.wantsCacheBuild = true
            needsDisplay = true
        }
    }

    func update(background: NSImage, viewport: CGSize, frame: CGRect, handDegrees: Double, cameraTilt: SIMD2<Float>) {
        let change = renderer.update(background: background, viewport: viewport, frame: frame, handDegrees: handDegrees, cameraTilt: cameraTilt)
        guard change != .none else { return }
        if change == .scene { scheduleCacheBuild() }
        needsDisplay = true
    }
}

private enum GemstoneRayChange { case none, hand, scene }

@MainActor
private final class GemstoneRayRenderer: NSObject, MTKViewDelegate {
    let resources: GemstoneRayResources
    var uniforms = GemstoneRayUniforms()
    var backdrop: MTLTexture?
    var backgroundIdentity: ObjectIdentifier?
    private var backgroundBrightness: GemstoneBackdropBrightness?
    var cachedColor: MTLTexture?
    var cachedInfluence: MTLTexture?
    var cacheReady = false
    var wantsCacheBuild = false
    private var frameInFlight = false
    private var redrawPending = false
    private var adjustingDrawableSize = false
    init(resources: GemstoneRayResources) { self.resources = resources }

    func update(background: NSImage, viewport: CGSize, frame: CGRect, handDegrees: Double, cameraTilt: SIMD2<Float>) -> GemstoneRayChange {
        let backgroundChanged = backgroundIdentity != ObjectIdentifier(background)
        if backgroundChanged {
            var rect = CGRect(origin: .zero, size: background.size)
            if let image = background.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                do {
                    let brightness = try GemstoneBackdropBrightness(image: image)
                    let texture = try GemstoneBackgroundTexture.make(image:image,device:resources.device,queue:resources.queue)
                    backgroundBrightness = brightness
                    backdrop = texture
                    backgroundIdentity = ObjectIdentifier(background)
                } catch { Logger(subsystem: "xkzxing.PomodoroSwift", category: "Gemstone").error("Cannot load jewel background: \(error.localizedDescription)") }
            }
        }
        let previous = uniforms
        let map = GemstoneBackdropMapping(imageSize: background.size, viewportSize: viewport, dialFrame: frame)
        uniforms.sizeAndAngle = SIMD4(Float(frame.width), Float(frame.height), Float(handDegrees * .pi / 180), resources.pigmentDensity)
        uniforms.mapping = SIMD4(Float(map.origin.x), Float(map.origin.y), Float(map.step.width), Float(map.step.height))
        uniforms.scene = SIMD4(Float(frame.minX), Float(frame.minY), Float(viewport.width), Float(viewport.height))
        uniforms.camera = SIMD4(cameraTilt.x, cameraTilt.y, 0, 0)
        if backgroundChanged || previous.mapping != uniforms.mapping || previous.sizeAndAngle.x != uniforms.sizeAndAngle.x
            || previous.sizeAndAngle.y != uniforms.sizeAndAngle.y {
            uniforms.lighting.x = backgroundBrightness?.emissionGain(mapping: map, dialSize: frame.size) ?? 1
        }
        uniforms.cache = SIMD4(0, GemstoneRayUniforms.handMask(degrees: handDegrees), 0, 0)
        uniforms.visibility = GemstoneRayUniforms.handVisibility(degrees: handDegrees)
        if backgroundChanged || !previous.hasSameScene(as: uniforms) {
            cacheReady = false
            return .scene
        }
        return previous.sizeAndAngle.z == uniforms.sizeAndAngle.z ? .none : .hand
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard !adjustingDrawableSize else { return }
        cacheReady = false
        (view as? GemstoneRayView)?.scheduleCacheBuild()
    }

    private func prepareCache(width: Int, height: Int) -> Bool {
        if cachedColor?.width == width && cachedColor?.height == height
            && cachedInfluence?.width == width && cachedInfluence?.height == height { return true }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        cachedColor = resources.device.makeTexture(descriptor: descriptor)
        descriptor.pixelFormat = .rgba32Uint
        cachedInfluence = resources.device.makeTexture(descriptor: descriptor)
        return cachedColor != nil && cachedInfluence != nil
    }

    private func encode(_ command: MTLCommandBuffer, pass: MTLRenderPassDescriptor,
                        pipeline: MTLRenderPipelineState, uniforms: GemstoneRayUniforms, composite: Bool = false) -> Bool {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        var parameters = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<GemstoneRayUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(resources.body.vertices, offset: 0, index: 1)
        encoder.setFragmentBuffer(resources.body.materials, offset: 0, index: 2)
        encoder.setFragmentBuffer(resources.hand.vertices, offset: 0, index: 3)
        encoder.setFragmentBuffer(resources.hand.materials, offset: 0, index: 4)
        encoder.setFragmentAccelerationStructure(resources.body.acceleration, bufferIndex: 5)
        encoder.setFragmentAccelerationStructure(resources.hand.acceleration, bufferIndex: 6)
        encoder.setFragmentTexture(backdrop, index: 0)
        encoder.setFragmentTexture(resources.illumination,index:3)
        if composite {
            encoder.setFragmentTexture(cachedColor, index: 1)
            encoder.setFragmentTexture(cachedInfluence, index: 2)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    func draw(in view: MTKView) {
        // Do not accumulate old drag positions behind expensive optical work.
        // The completion schedules one redraw using the latest parameters.
        if frameInFlight { redrawPending = true; return }
        guard view.bounds.width>0,view.bounds.height>0 else { return }
        let backing=view.convertToBacking(view.bounds).size
        let settled=cacheReady || wantsCacheBuild
        // On a Retina display, move at 1.5 pixels per point and settle at the
        // full backing resolution. Never drop below one pixel per point.
        let size=CGSize(width:max(view.bounds.width,(backing.width*(settled ? 1 : 0.75)).rounded(.up)),
                        height:max(view.bounds.height,(backing.height*(settled ? 1 : 0.75)).rounded(.up)))
        if view.drawableSize != size {
            if cacheReady { cacheReady = false; wantsCacheBuild = true }
            adjustingDrawableSize = true
            view.drawableSize = size
            adjustingDrawableSize = false
        }
        guard uniforms.sizeAndAngle.x > 0, backdrop != nil,
              let drawable = view.currentDrawable,
              let command = resources.queue.makeCommandBuffer() else { return }
        // Build the pass from the very drawable whose dimensions drive the
        // rays. MetalKit can still expose a pass for the previous size while
        // switching the Retina interaction resolution in this draw callback.
        let pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
        if cacheReady && (cachedColor?.width != drawable.texture.width || cachedColor?.height != drawable.texture.height) {
            cacheReady = false; wantsCacheBuild = true
        }
        uniforms.cache.z = UInt32(drawable.texture.width)
        uniforms.cache.w = UInt32(drawable.texture.height)
        if wantsCacheBuild && prepareCache(width: drawable.texture.width, height: drawable.texture.height) {
            let bake = MTLRenderPassDescriptor()
            bake.colorAttachments[0].texture = cachedColor
            bake.colorAttachments[1].texture = cachedInfluence
            for index in 0...1 {
                bake.colorAttachments[index].loadAction = .clear
                bake.colorAttachments[index].storeAction = .store
                bake.colorAttachments[index].clearColor = MTLClearColorMake(0, 0, 0, 0)
            }
            var parameters = uniforms
            parameters.cache.x = 1
            cacheReady = encode(command, pass: bake, pipeline: resources.cachePipeline, uniforms: parameters)
            wantsCacheBuild = false
        }
        var parameters = uniforms
        parameters.cache.x = cacheReady ? 2 : 0
        guard encode(command, pass: pass, pipeline: cacheReady ? resources.compositePipeline : resources.pipeline,
                     uniforms: parameters, composite: cacheReady) else { return }
        frameInFlight = true
        redrawPending = false
        command.addCompletedHandler { [weak self, weak view] _ in
            Task { @MainActor in
                guard let self else { return }
                self.frameInFlight = false
                if self.redrawPending { view?.needsDisplay = true }
            }
        }
        command.present(drawable); command.commit()
    }
}
