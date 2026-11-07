import AppKit
import MetalKit

/// Full versus cached optical transport with real, detailed landscape and
/// portrait photographs. Run with MTL_DEBUG_LAYER=1 for API validation.
@main struct ValidatePhotoScenes {
    @MainActor static func main() async throws {
        let allPhotos=PreviewBackdrops.photographs
        guard allPhotos.count==8 else { throw CocoaError(.fileReadNoSuchFile) }
        let quick=CommandLine.arguments.contains("--quick")
        let photos=quick ? Array(allPhotos.prefix(1)) : allPhotos
        let arguments=CommandLine.arguments
        let allowAppearanceChange=arguments.contains("--allow-appearance-change")
        func argument(_ flag:String) -> String? {
            arguments.firstIndex(of:flag).flatMap { $0+1<arguments.count ? arguments[$0+1] : nil }
        }
        let resources=try await GemstoneRayResources.make(scene:await GemstoneMeshSceneData.dial.value,
            libraryURL:URL(fileURLWithPath:argument("--library") ?? "build/GemstoneRayTracing.metallib"))
        // Use the same geometry, textures and command queue for the old and new
        // shaders. Alternating their order reduces clock/load bias in timings.
        let baselineLibrary=try argument("--baseline-library").map {
            try resources.device.makeLibrary(URL:URL(fileURLWithPath:$0))
        }
        let baselineMaskFormat: MTLPixelFormat = argument("--baseline-mask-words")=="4" ? .rgba32Uint : .r32Uint
        func baselinePipeline(_ name:String,bake:Bool=false) throws -> MTLRenderPipelineState? {
            guard let library=baselineLibrary else { return nil }
            let descriptor=MTLRenderPipelineDescriptor()
            descriptor.vertexFunction=library.makeFunction(name:"gemstoneRayVertex")
            descriptor.fragmentFunction=library.makeFunction(name:name)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            if bake { descriptor.colorAttachments[1].pixelFormat = baselineMaskFormat }
            let color=descriptor.colorAttachments[0]!
            color.isBlendingEnabled = !bake
            color.sourceRGBBlendFactor = .one;color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one;color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try resources.device.makeRenderPipelineState(descriptor:descriptor)
        }
        let baselineFull=try baselinePipeline("gemstoneRayFragment")
        let baselineBake=try baselinePipeline("gemstoneRayCacheFragment",bake:true)
        let baselineComposite=try baselinePipeline("gemstoneRayCompositeFragment")
        let repetitions=max(1,min(20,Int(argument("--repeat") ?? "1") ?? 1))
        let size=880
        func texture(_ format: MTLPixelFormat) -> MTLTexture {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:size,height:size,mipmapped:false)
            d.usage=[.renderTarget,.shaderRead];d.storageMode = .shared
            return resources.device.makeTexture(descriptor:d)!
        }
        let cached=texture(.bgra8Unorm_srgb),mask=texture(.rgba32Uint)
        let full=texture(.bgra8Unorm_srgb),composed=texture(.bgra8Unorm_srgb)
        let oldCached=texture(.bgra8Unorm_srgb),oldMask=texture(baselineMaskFormat)
        let oldFull=texture(.bgra8Unorm_srgb),oldComposed=texture(.bgra8Unorm_srgb)
        func draw(_ pipeline: MTLRenderPipelineState,_ color: MTLTexture,_ photo: MTLTexture,
                  _ uniforms: GemstoneRayUniforms,bake: Bool=false,composite: Bool=false,baseline:Bool=false) async throws -> Double {
            let pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=color
            pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            if bake {
                pass.colorAttachments[1].texture=baseline ? oldMask : mask
                pass.colorAttachments[1].loadAction = .clear;pass.colorAttachments[1].storeAction = .store
                pass.colorAttachments[1].clearColor=MTLClearColorMake(0,0,0,0)
            }
            let command=resources.queue.makeCommandBuffer()!
            let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            var u=uniforms
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&u,length:MemoryLayout<GemstoneRayUniforms>.stride,index:0)
            encoder.setFragmentBuffer(resources.body.vertices,offset:0,index:1)
            encoder.setFragmentBuffer(resources.body.materials,offset:0,index:2)
            encoder.setFragmentBuffer(resources.hand.vertices,offset:0,index:3)
            encoder.setFragmentBuffer(resources.hand.materials,offset:0,index:4)
            encoder.setFragmentAccelerationStructure(resources.body.acceleration,bufferIndex:5)
            encoder.setFragmentAccelerationStructure(resources.hand.acceleration,bufferIndex:6)
            encoder.setFragmentTexture(photo,index:0)
            encoder.setFragmentTexture(resources.illumination,index:3)
            if composite {
                encoder.setFragmentTexture(baseline ? oldCached : cached,index:1)
                encoder.setFragmentTexture(baseline ? oldMask : mask,index:2)
            }
            encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
            encoder.endEncoding();command.commit();await command.completed()
            if let error=command.error { throw error }
            return (command.gpuEndTime-command.gpuStartTime)*1000
        }
        func bytes(_ texture: MTLTexture) -> [UInt8] {
            var bytes=[UInt8](repeating:0,count:size*size*4)
            texture.getBytes(&bytes,bytesPerRow:size*4,from:MTLRegionMake2D(0,0,size,size),mipmapLevel:0)
            return bytes
        }
        var cases=0,failures=0,maximum=0,baselineMaximum=0
        var fullTimes: [Double]=[],cachedTimes: [Double]=[],baselineTimes:[Double]=[],bakeTimes:[Double]=[]
        var adaptation: [[String: Any]] = []
        for photo in photos {
            var rect=CGRect(origin:.zero,size:photo.image.size)
            guard let image=photo.image.cgImage(forProposedRect:&rect,context:nil,hints:nil),
                  min(image.width,image.height)>=1600 else { throw CocoaError(.fileReadCorruptFile) }
            let backdrop=try GemstoneBackgroundTexture.make(image:image,device:resources.device,queue:resources.queue)
            let brightness = try GemstoneBackdropBrightness(image: image)
            for view in 0..<2 {
                let frame=view==0 ? CGRect(x:110,y:60,width:440,height:440) : CGRect(x:25,y:145,width:440,height:440)
                let mapping=GemstoneBackdropMapping(imageSize:photo.image.size,viewportSize:CGSize(width:660,height:660),dialFrame:frame)
                var u=GemstoneRayUniforms()
                u.sizeAndAngle=SIMD4(440,440,0,resources.pigmentDensity)
                u.mapping=SIMD4(Float(mapping.origin.x),Float(mapping.origin.y),Float(mapping.step.width),Float(mapping.step.height))
                u.scene=SIMD4(Float(frame.minX),Float(frame.minY),660,660)
                u.camera=view==0 ? .zero : SIMD4(0.6,-0.45,0,0)
                let mean = brightness.mean(mapping: mapping, dialSize: frame.size)
                u.lighting.x = GemstoneBackdropBrightness.emissionGain(luminance: mean)
                adaptation.append(["photo": photo.id, "view": view, "luminance": mean, "gain": u.lighting.x])
                u.cache=SIMD4(1,0,UInt32(size),UInt32(size))
                bakeTimes.append(try await draw(resources.cachePipeline,cached,backdrop,u,bake:true))
                if let baselineBake { _=try await draw(baselineBake,oldCached,backdrop,u,bake:true,baseline:true) }
                u.cache.x=2
                for angle in quick ? [0.0,67.5] : [0.0,0.15,67.5,359.9] {
                    u.sizeAndAngle.z=Float(angle * .pi/180)
                    u.cache.y=GemstoneRayUniforms.handMask(degrees:angle)
                    u.visibility=GemstoneRayUniforms.handVisibility(degrees:angle)
                    fullTimes.append(try await draw(resources.pipeline,full,backdrop,u))
                    if cases==0 {
                        _=try await draw(resources.compositePipeline,composed,backdrop,u,composite:true)
                        if let baselineComposite {
                            _=try await draw(baselineComposite,oldComposed,backdrop,u,composite:true,baseline:true)
                        }
                    }
                    for repetition in 0..<repetitions {
                        let oldFirst=(cases+repetition).isMultiple(of:2)
                        if oldFirst,let baselineComposite {
                            baselineTimes.append(try await draw(baselineComposite,oldComposed,backdrop,u,composite:true,baseline:true))
                        }
                        cachedTimes.append(try await draw(resources.compositePipeline,composed,backdrop,u,composite:true))
                        if !oldFirst,let baselineComposite {
                            baselineTimes.append(try await draw(baselineComposite,oldComposed,backdrop,u,composite:true,baseline:true))
                        }
                    }
                    let a=bytes(full),b=bytes(composed)
                    var differing=0
                    for i in a.indices {
                        let error=abs(Int(a[i])-Int(b[i]))
                        maximum=max(maximum,error)
                        if error>1 { differing += 1 }
                    }
                    var baselineDiffering=0
                    if let baselineFull {
                        _=try await draw(baselineFull,oldFull,backdrop,u,baseline:true)
                        let original=bytes(oldFull)
                        for i in a.indices {
                            let error=abs(Int(a[i])-Int(original[i]))
                            baselineMaximum=max(baselineMaximum,error)
                            if error>1 { baselineDiffering += 1 }
                        }
                    }
                    cases += 1
                    if differing>0 || (baselineDiffering>0 && !allowAppearanceChange) {
                        failures += 1
                        print("差异：\(photo.name)，视角 \(view)，针位 \(angle)，缓存超差通道 \(differing)，旧版超差通道 \(baselineDiffering)")
                    }
                }
            }
            print("已检查：\(photo.name)，\(image.width) × \(image.height)")
        }
        print("场景数 / 失败数 / 最大色阶误差：",cases,failures,maximum)
        print("完整绘制 / 缓存绘制中位耗时：",fullTimes.sorted()[fullTimes.count/2],cachedTimes.sorted()[cachedTimes.count/2])
        print("静态缓存构建中位耗时：",bakeTimes.sorted()[bakeTimes.count/2])
        let triangles=resources.body.triangleCount+resources.hand.triangleCount
        print("几何三角形数：",triangles)
        print("局部照明缓存字节／建立毫秒：",resources.illumination.allocatedSize,resources.illuminationBakeMilliseconds)
        if !baselineTimes.isEmpty {
            let before=baselineTimes.sorted()[baselineTimes.count/2],after=cachedTimes.sorted()[cachedTimes.count/2]
            print("旧版 / 新版缓存交替测量中位耗时：",before,after)
            print("缓存绘制耗时降低：",(1-after/before)*100,"%，每场景重复：",repetitions)
            print("与旧版完整画面的最大色阶误差：",baselineMaximum)
        }
        if let path=argument("--report") {
            let report:[String:Any]=["cases":cases,"failures":failures,"maximumCacheError":maximum,
                "maximumBaselineError":baselineMaximum,"appearanceChangeAllowed":allowAppearanceChange,"repetitions":repetitions,"fullMilliseconds":fullTimes,
                "cachedMilliseconds":cachedTimes,"baselineCachedMilliseconds":baselineTimes,"bakeMilliseconds":bakeTimes,
                "triangles":triangles,"illuminationBytes":resources.illumination.allocatedSize,
                "illuminationBakeMilliseconds":resources.illuminationBakeMilliseconds,"adaptation":adaptation]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                .write(to:URL(fileURLWithPath:path),options:.atomic)
        }
        if failures>0 { exit(1) }
    }
}
