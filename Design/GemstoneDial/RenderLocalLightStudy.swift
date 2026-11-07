import AppKit
import MetalKit
import UniformTypeIdentifiers

@main struct RenderLocalLightStudy {
    @MainActor static func main() async throws {
        let libraryURL=URL(fileURLWithPath:"build/GemstoneRayTracing.metallib")
        let board=CGContext(data:nil,width:1920,height:790,bitsPerComponent:8,bytesPerRow:1920*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        board.setFillColor(CGColor(gray:0.025,alpha:1));board.fill(CGRect(x:0,y:0,width:1920,height:790))
        for state in 0..<3 {
            let resources=try await GemstoneRayResources.make(scene:GemstoneMeshBuilder.localLightStudy(enabled:state != 0,blocked:state==2),libraryURL:libraryURL)
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm_srgb,width:1024,height:1024,mipmapped:false)
            d.usage=[.renderTarget,.shaderRead];d.storageMode = .shared
            let target=resources.device.makeTexture(descriptor:d)!
            let p=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,width:1,height:1,mipmapped:false)
            p.storageMode = .shared
            let photo=resources.device.makeTexture(descriptor:p)!
            var black:UInt32=0xff000000
            photo.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&black,bytesPerRow:4)
            var u=GemstoneRayUniforms()
            u.sizeAndAngle=SIMD4(440,440,0,resources.pigmentDensity)
            u.mapping=SIMD4(0,0,1.0/440,1.0/440);u.scene=SIMD4(0,0,440,440)
            u.cache=SIMD4(2,0,1024,1024)
            let pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=target
            pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            let command=resources.queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            encoder.setRenderPipelineState(resources.pipeline)
            encoder.setFragmentBytes(&u,length:MemoryLayout<GemstoneRayUniforms>.stride,index:0)
            encoder.setFragmentBuffer(resources.body.vertices,offset:0,index:1);encoder.setFragmentBuffer(resources.body.materials,offset:0,index:2)
            encoder.setFragmentBuffer(resources.hand.vertices,offset:0,index:3);encoder.setFragmentBuffer(resources.hand.materials,offset:0,index:4)
            encoder.setFragmentAccelerationStructure(resources.body.acceleration,bufferIndex:5)
            encoder.setFragmentAccelerationStructure(resources.hand.acceleration,bufferIndex:6)
            encoder.setFragmentTexture(photo,index:0);encoder.setFragmentTexture(resources.illumination,index:3)
            encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
            encoder.endEncoding();command.commit();await command.completed()
            if let error=command.error { throw error }
            var bytes=[UInt8](repeating:0,count:1024*1024*4)
            target.getBytes(&bytes,bytesPerRow:1024*4,from:MTLRegionMake2D(0,0,1024,1024),mipmapLevel:0)
            let image=CGImage(width:1024,height:1024,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:1024*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue)),
                provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
            let crop=image.cropping(to:CGRect(x:250,y:250,width:524,height:524))!
            board.draw(crop,in:CGRect(x:state*640+20,y:115,width:600,height:600))
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:board,flipped:false)
            (["光源关闭","光源开启","两颗宝石之间加入遮挡"][state] as NSString).draw(at:CGPoint(x:state*640+24,y:745),withAttributes:[
                .font:NSFont.systemFont(ofSize:25,weight:.medium),.foregroundColor:NSColor.white])
            ("右侧宝石没有发光材质" as NSString).draw(at:CGPoint(x:state*640+24,y:54),withAttributes:[
                .font:NSFont.systemFont(ofSize:23),.foregroundColor:NSColor(white:0.75,alpha:1)])
            NSGraphicsContext.restoreGraphicsState()
            print("状态／照明建立毫秒：",state,resources.illuminationBakeMilliseconds)
        }
        let url=URL(fileURLWithPath:"build/gemstone-illumination-study.png")
        let output=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(output,board.makeImage()!,nil)
        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
        print(url.path)
    }
}
