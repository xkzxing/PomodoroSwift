import AppKit
import MetalKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the same mesh, optical shader, hand position and framing as the native preview.
/// This is an offscreen comparison, so it does not interrupt someone using the preview window.
@main struct RenderBackdropComparison {
    @MainActor static func main() async throws {
        func argument(_ name: String, default value: String) -> String {
            guard let index=CommandLine.arguments.firstIndex(of:name),index+1<CommandLine.arguments.count else { return value }
            return CommandLine.arguments[index+1]
        }
        let hero=CommandLine.arguments.contains("--hero")
        let photos=CommandLine.arguments.contains("--photos")
        let angles=CommandLine.arguments.contains("--angles")
        let handFocus=CommandLine.arguments.contains("--hand-focus")
        let rimFocus=CommandLine.arguments.contains("--rim-focus")
        let focus=CommandLine.arguments.contains("--focus") || angles || handFocus || rimFocus
        let resources = try await GemstoneRayResources.make(scene: await GemstoneMeshSceneData.dial.value,
            libraryURL: URL(fileURLWithPath: argument("--library",default:"build/GemstoneRayTracing.metallib")))
        if photos && PreviewBackdrops.photographs.count<8 {
            throw CocoaError(.fileReadNoSuchFile,userInfo:[NSLocalizedDescriptionKey:"实拍背景不完整；请检查照片资源目录。"])
        }
        let photoID=argument("--background",default:"photo-office")
        let identifiers=photos ? (hero ? [photoID] : PreviewBackdrops.photographs.map(\.id)) : hero ? ["cathedral"] : angles ? ["graphite","graphite","graphite"] : rimFocus ? ["photo-office","photo-night","photo-library"] : focus ? ["pearl","graphite","window"] : ["pearl","graphite","window","cool","forest","city"]
        let selected = identifiers.compactMap { id in PreviewBackdrops.all.first{$0.id==id} }
        guard selected.count==identifiers.count else { throw CocoaError(.fileReadNoSuchFile) }
        let pixels = hero ? 1120 : 880
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: pixels, height: pixels, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .shared
        let target = resources.device.makeTexture(descriptor: descriptor)!
        let boardWidth=hero ? 1320 : 1800, boardHeight=hero ? 1320 : photos ? 1950 : 1300
        let board = CGContext(data: nil, width: boardWidth, height: boardHeight, bitsPerComponent: 8, bytesPerRow: boardWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        board.setFillColor(CGColor(gray: 0.95, alpha: 1)); board.fill(CGRect(x: 0, y: 0, width: boardWidth, height: boardHeight))
        func drawBackground(_ image: CGImage,in rect: CGRect,on context: CGContext) {
            let drawing=GemstoneBackdropMapping.aspectFillRect(imageSize:CGSize(width:image.width,height:image.height),in:rect)
            context.saveGState();context.clip(to:rect)
            context.draw(image,in:drawing)
            context.restoreGState()
        }
        for (index, item) in selected.enumerated() {
            var rect = CGRect(origin: .zero, size: item.image.size)
            let image = item.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
            let backdrop = try GemstoneBackgroundTexture.make(image:image,device:resources.device,queue:resources.queue)
            let frame = hero && !CommandLine.arguments.contains("--native-frame")
                ? CGRect(x:50,y:50,width:560,height:560) : CGRect(x: 110, y: 60, width: 440, height: 440)
            let mapping = GemstoneBackdropMapping(imageSize: item.image.size, viewportSize: .init(width: 660, height: 660), dialFrame: frame)
            var uniforms = GemstoneRayUniforms()
            if CommandLine.arguments.contains("--raw-transmission") { uniforms.lighting.y=0 }
            uniforms.sizeAndAngle = SIMD4(Float(frame.width), Float(frame.height), Float.pi / 3, resources.pigmentDensity)
            uniforms.mapping = SIMD4(Float(mapping.origin.x), Float(mapping.origin.y), Float(mapping.step.width), Float(mapping.step.height))
            uniforms.scene = SIMD4(Float(frame.minX), Float(frame.minY), 660, 660)
            if CommandLine.arguments.contains("--background-reference") { uniforms.camera.w=4 }
            if CommandLine.arguments.contains("--transmission") { uniforms.camera.z=1 }
            if angles {
                let views:[SIMD2<Float>]=[SIMD2(-0.6,0.45),.zero,SIMD2(0.6,-0.45)]
                uniforms.camera=SIMD4(views[index].x,views[index].y,0,0)
            }
            let brightness = try GemstoneBackdropBrightness(image: image)
            let mean = brightness.mean(mapping: mapping, dialSize: frame.size)
            if !CommandLine.arguments.contains("--fixed-emission") {
                uniforms.lighting.x = GemstoneBackdropBrightness.emissionGain(luminance: mean)
            }
            print("背景线性亮度／夜光比例：", item.name, mean, uniforms.lighting.x)
            uniforms.cache = SIMD4(2, 0, UInt32(pixels), UInt32(pixels))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let command = resources.queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(resources.pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GemstoneRayUniforms>.stride, index: 0)
            encoder.setFragmentBuffer(resources.body.vertices, offset: 0, index: 1)
            encoder.setFragmentBuffer(resources.body.materials, offset: 0, index: 2)
            encoder.setFragmentBuffer(resources.hand.vertices, offset: 0, index: 3)
            encoder.setFragmentBuffer(resources.hand.materials, offset: 0, index: 4)
            encoder.setFragmentAccelerationStructure(resources.body.acceleration, bufferIndex: 5)
            encoder.setFragmentAccelerationStructure(resources.hand.acceleration, bufferIndex: 6)
            encoder.setFragmentTexture(backdrop, index: 0)
            encoder.setFragmentTexture(resources.illumination,index:3)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding(); command.commit(); await command.completed()
            if let error = command.error { throw error }
            var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
            target.getBytes(&bytes, bytesPerRow: pixels * 4, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
            let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
            let dial = CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info,
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
            if hero {
                drawBackground(image,in:CGRect(x:0,y:0,width:1320,height:1320),on:board)
                board.draw(dial,in:CGRect(x:frame.minX*2,y:(660-frame.maxY)*2,width:frame.width*2,height:frame.height*2))
                print("已绘制：\(item.name)")
                continue
            }
            let x = CGFloat(index % 3) * 600, y = CGFloat((photos ? 2 : 1) - index / 3) * 650
            drawBackground(image,in:CGRect(x:x,y:y,width:600,height:600),on:board)
            // The window's frame is measured from the top; the bitmap context's origin is at the bottom.
            board.draw(dial, in: CGRect(x: x + frame.minX * 600 / 660,
                y: y + (660 - frame.maxY) * 600 / 660, width: 400, height: 400))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: board, flipped: false)
            let title=angles ? ["左侧视角","正面视角","右侧视角"][index] : item.name
            (title as NSString).draw(at: CGPoint(x: x + 18, y: y + 615), withAttributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.labelColor
            ])
            NSGraphicsContext.restoreGraphicsState()
            if focus && !photos {
                let closeup=CGContext(data:nil,width:1320,height:1320,bitsPerComponent:8,bytesPerRow:1320*4,
                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                drawBackground(image,in:CGRect(x:0,y:0,width:1320,height:1320),on:closeup)
                closeup.draw(dial,in:CGRect(x:frame.minX*2,y:(660-frame.maxY)*2,width:880,height:880))
                let crop=closeup.makeImage()!.cropping(to:CGRect(x:rimFocus ? 700 : handFocus ? 580 : 220,y:rimFocus ? 105 : handFocus ? 320 : 88,width:484,height:385))!
                board.draw(crop,in:CGRect(x:x+24,y:75,width:552,height:439))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current=NSGraphicsContext(cgContext:board,flipped:false)
                ((rimFocus ? "外圈青晶与背面光路" : handFocus ? "指针宝石与金边" : "蓝晶与镶口局部") as NSString).draw(at:CGPoint(x:x+18,y:615),withAttributes:[
                    .font:NSFont.systemFont(ofSize:20,weight:.medium),.foregroundColor:NSColor.labelColor
                ])
                NSGraphicsContext.restoreGraphicsState()
            }
            print("已绘制：\(item.name)")
        }
        let url = URL(fileURLWithPath: argument("--output",default:focus ? "build/gemstone-sapphire-focus.png" : "build/gemstone-background-comparison.png"))
        var rendered=board.makeImage()!
        let beforePath=argument("--compare-before",default:"")
        if !beforePath.isEmpty {
            guard hero,let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:beforePath) as CFURL,nil),
                  let before=CGImageSourceCreateImageAtIndex(source,0,nil),
                  let pair=CGContext(data:nil,width:2640,height:1400,bitsPerComponent:8,bytesPerRow:2640*4,
                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw CocoaError(.fileReadCorruptFile) }
            pair.setFillColor(CGColor(gray:0.96,alpha:1));pair.fill(CGRect(x:0,y:0,width:2640,height:1400))
            pair.draw(before,in:CGRect(x:0,y:0,width:1320,height:1320))
            pair.draw(rendered,in:CGRect(x:1320,y:0,width:1320,height:1320))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(cgContext:pair,flipped:false)
            for (index,title) in ["调整前","本轮调整"].enumerated() {
                (title as NSString).draw(at:CGPoint(x:24+index*1320,y:1340),withAttributes:[
                    .font:NSFont.systemFont(ofSize:28,weight:.medium),.foregroundColor:NSColor.labelColor])
            }
            NSGraphicsContext.restoreGraphicsState()
            rendered=pair.makeImage()!
        }
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, rendered, nil)
        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
        print(url.path)
    }
}
