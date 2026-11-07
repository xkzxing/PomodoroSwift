import AppKit
import MetalKit

@main struct ValidateOpticalTransport {
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        let url=URL(fileURLWithPath:"build/GemstoneOpticalValidation.metallib")
        var body=GemstoneMesh(),hand=GemstoneMesh()
        GemstoneMeshBuilder.curvedCrystal(&body,shape:GemstoneMeshBuilder.referenceOutlines[0],
            base:0.071,crown:0.019,depth:0.023,rim:0)
        hand.triangle(SIMD3(20,20,-20),SIMD3(21,20,-20),SIMD3(20,21,-20),material:1)
        let resources=try await GemstoneRayResources.make(scene:.init(body:body,hand:hand),libraryURL:url)
        let library=try resources.device.makeLibrary(URL:url)
        func execute(_ name:String,count:Int,withScene:Bool,scene:GemstoneRayResources?=nil,threads:Int=64,photo:MTLTexture?=nil,field:MTLTexture?=nil,gain:Float=1,density:Float=4.8,lift:Float=0) async throws -> [SIMD4<Float>] {
            let active=scene ?? resources
            let pipeline=try await active.device.makeComputePipelineState(function:library.makeFunction(name:name)!)
            let output=active.device.makeBuffer(length:MemoryLayout<SIMD4<Float>>.stride*count,options:.storageModeShared)!
            let command=active.queue.makeCommandBuffer()!,encoder=command.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(field ?? active.illumination,index:3)
            if withScene {
                var u=GemstoneRayUniforms();u.sizeAndAngle=SIMD4(440,440,0,density)
                u.lighting.x = gain
                u.lighting.y = lift
                encoder.setBytes(&u,length:MemoryLayout<GemstoneRayUniforms>.stride,index:0)
                encoder.setBuffer(active.body.vertices,offset:0,index:1);encoder.setBuffer(active.body.materials,offset:0,index:2)
                encoder.setBuffer(active.hand.vertices,offset:0,index:3);encoder.setBuffer(active.hand.materials,offset:0,index:4)
                encoder.setAccelerationStructure(active.body.acceleration,bufferIndex:5)
                encoder.setAccelerationStructure(active.hand.acceleration,bufferIndex:6)
            }
            if let photo {
                if !withScene {
                    var u=GemstoneRayUniforms()
                    u.sizeAndAngle=SIMD4(440,440,0,4.8);u.scene=SIMD4(0,0,800,600)
                    u.mapping=SIMD4(-0.2,0.1,1.0/800,1.0/600)
                    encoder.setBytes(&u,length:MemoryLayout<GemstoneRayUniforms>.stride,index:1)
                }
                encoder.setTexture(photo,index:0)
            }
            encoder.setBuffer(output,offset:0,index:withScene ? 7 : 0)
            encoder.dispatchThreads(MTLSize(width:withScene || photo != nil ? threads : 1,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:1,height:1,depth:1))
            encoder.endEncoding();command.commit();await command.completed()
            if let error=command.error { throw error }
            return Array(UnsafeBufferPointer(start:output.contents().assumingMemoryBound(to:SIMD4<Float>.self),count:count))
        }
        let cases=try await execute("gemstoneBoundaryCases",count:14,withScene:false)
        var checks=0
        func close(_ value:Float,_ expected:Float,tolerance:Float=0.00002) {
            precondition(value.isFinite && abs(value-expected)<tolerance,"\(value) != \(expected)");checks += 1
        }
        for (i,ior) in [Float(1.62),1.76,1.62,1].enumerated() {
            let x:Float=0.5/ior
            close(cases[i].x,x);close(cases[i].y,0);close(cases[i].z,-sqrt(1-x*x));close(cases[i].w,ior)
        }
        let absorption=SIMD3<Float>(0.2,0.09,0.05)*0.03+SIMD3<Float>(18,6.5,2.4)*(0.04*4.8)
        for i in 0..<3 { close(cases[4][i],exp(-absorption[i])) }
        close(cases[4].w,0)
        let expectedCases:[SIMD4<Float>]=[
            SIMD4(0,1.76,2,12),SIMD4(1,0,1,-sqrt(Float(0.19))),
            SIMD4(1.76,1,12,0),SIMD4(0,pow((Float(1)-1.76)/(1+1.76),2),0,4)
        ]
        for (i,expected) in expectedCases.enumerated() {
            for channel in 0..<4 { close(cases[i+5][channel],expected[channel]) }
        }
        let tealAbsorption=SIMD3<Float>(15,2.5,2.25)
        for channel in 0..<3 {
            close(cases[9][channel],exp(-tealAbsorption[channel]*0.02*4.8))
            close(cases[10][channel],exp(-tealAbsorption[channel]*0.16*4.8))
            precondition(cases[10][channel]<cases[9][channel],"Thicker crystal must absorb more light")
        }
        for (channel,expected) in [Float(1),1,88,0].enumerated() { close(cases[11][channel],expected) }
        close(cases[12].x,sqrt(0.99));close(cases[12].y,-sqrt(1-pow(0.1/1.76,2)))
        close(cases[12].z,1.76);close(cases[12].w,1)
        for (channel,expected) in [Float(2),1,Float(0x00400002),0].enumerated() { close(cases[13][channel],expected) }
        let paths=try await execute("gemstoneSingleStoneCases",count:128,withScene:true)
        var matched=0,trapped=0,maxError:Float=0
        for i in 0..<64 {
            let reference=paths[i*2],actual=paths[i*2+1]
            close(actual.w,reference.w)
            if actual.w==1 {
                let error=simd_length(SIMD3(actual.x-reference.x,actual.y-reference.y,actual.z-reference.z))
                precondition(error<0.0001,"Escape path mismatch: \(i), \(error)")
                maxError=max(maxError,error);matched += 1
            } else if actual.w<0 { trapped += 1 }
        }
        precondition(matched>=20,"Too few rays hit the study crystal")
        print("Boundary/scattering checks:",checks)
        print("Single-stone rays / matched escapes / trapped:",64,matched,trapped)
        print("Maximum escape-direction error:",maxError)
        func reflectionPhoto(_ color:(Int,Int)->SIMD4<Float16>) -> MTLTexture {
            let size=64
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:size,height:size,mipmapped:true)
            descriptor.storageMode = .shared;descriptor.usage = .shaderRead
            let photo=resources.device.makeTexture(descriptor:descriptor)!
            let pixels=(0..<size).flatMap { y in (0..<size).map { x in color(x,y) } }
            pixels.withUnsafeBytes { photo.replace(region:MTLRegionMake2D(0,0,size,size),mipmapLevel:0,
                withBytes:$0.baseAddress!,bytesPerRow:size*MemoryLayout<SIMD4<Float16>>.stride) }
            let command=resources.queue.makeCommandBuffer()!,blit=command.makeBlitCommandEncoder()!
            blit.generateMipmaps(for:photo);blit.endEncoding();command.commit()
            return photo
        }
        let photoColors:[SIMD4<Float16>]=[
            SIMD4(0,0,0,1),SIMD4(0.25,0,0,1),SIMD4(0.0625,0.25,0.5,1),SIMD4(0.00625,0.025,0.05,1)
        ]
        var reflections:[[SIMD4<Float>]]=[]
        for color in photoColors {
            let photo=reflectionPhoto { _,_ in color }
            let values=try await execute("gemstonePhotoReflectionCases",count:512,withScene:false,threads:256,photo:photo)
            for value in values {
                precondition((0..<3).allSatisfy { value[$0].isFinite && value[$0]>=0 && value[$0]<=6 },"Invalid photo reflection")
            }
            reflections.append(values)
        }
        for i in 0..<512 {
            for channel in 0..<3 { close(reflections[0][i][channel],0) }
            close(reflections[1][i].y,0);close(reflections[1][i].z,0)
            close(reflections[2][i].x*4,reflections[2][i].y,tolerance:0.002)
            close(reflections[2][i].y*2,reflections[2][i].z,tolerance:0.002)
            for channel in 0..<3 {
                let bright=reflections[2][i][channel],dark=reflections[3][i][channel]
                precondition(dark>=bright*0.099 && dark<=bright*0.401,"Dark-photo compensation must remain bounded")
            }
        }
        let gradient=reflectionPhoto { x,y in SIMD4(Float16(Float(x)/63),Float16(Float(y)/63),0.05,1) }
        let warped=try await execute("gemstonePhotoReflectionCases",count:512,withScene:false,threads:256,photo:gradient)
        precondition(warped.allSatisfy { value in (0..<3).allSatisfy { value[$0].isFinite && value[$0]>=0 && value[$0]<=12 } })
        let movement:[Float]=(0..<256).map { i in
            let difference=warped[i*2+1]-warped[i*2]
            return simd_length(SIMD3<Float>(difference.x,difference.y,difference.z))
        }
        precondition(movement.filter { $0>0.02 }.count>128,"Reflection must follow translated photographic detail")
        print("照片反射检查：五种合成背景，各 512 个方向与位置；黑色无自发光、色相比率、暗图亮度和移动响应通过")
        var litBody=GemstoneMesh()
        GemstoneMeshBuilder.jewel(&litBody,center:.zero,scale:SIMD2(0.20,0.16),angle:0,material:5,withLightCore:true)
        var bareCore=GemstoneMesh()
        for triangle in litBody.materials.indices where litBody.materials[triangle]==14 {
            let v=Array(litBody.vertices[(triangle*3)..<(triangle*3+3)])
            bareCore.triangle(v[0].position,v[1].position,v[2].position,material:14,normals:(v[0].normal,v[1].normal,v[2].normal))
        }
        bareCore.markEmissive(startingAt:0)
        let inside=try await GemstoneRayResources.make(scene:.init(body:litBody,hand:hand),libraryURL:url)
        let outside=try await GemstoneRayResources.make(scene:.init(body:bareCore,hand:hand),libraryURL:url)
        let black=reflectionPhoto { _,_ in SIMD4(0,0,0,1) }
        let white=reflectionPhoto { _,_ in SIMD4(1,1,1,1) }
        let gray=reflectionPhoto { _,_ in SIMD4(0.18,0.18,0.18,1) }
        let goldBlack=try await execute("gemstoneGoldHighlightCases",count:3072,withScene:false,threads:1024,photo:black)
        let goldGray=try await execute("gemstoneGoldHighlightCases",count:3072,withScene:false,threads:1024,photo:gray)
        let goldWhite=try await execute("gemstoneGoldHighlightCases",count:3072,withScene:false,threads:1024,photo:white)
        print("金边诊断最高线性辐射：",goldWhite.map{max($0.x,max($0.y,$0.z))}.max()!)
        precondition(goldBlack.allSatisfy { abs($0.x)+abs($0.y)+abs($0.z)<0.00001 },"Gold reflections cannot emit light from a black photograph")
        // White-photo exposure is 2.2; even the sum of every lobe's peak is
        // below 224. Values are checked before the display highlight shoulder.
        precondition(goldWhite.allSatisfy { value in (0..<3).allSatisfy { value[$0].isFinite && value[$0]>=0 && value[$0]<224 } },"Gold highlight radiance must remain finite and bounded")
        let glints=(0..<1024).filter { goldGray[$0*3].x>goldGray[$0*3+1].x*2 }
        let shifted=(0..<1024).filter { abs(goldGray[$0*3].x-goldGray[$0*3+2].x)>0.15 }
        print("金边诊断强高光／视角响应数：",glints.count,shifted.count)
        precondition(glints.count>10 && glints.count<512,"Gold should have selected bright portions, not a uniformly luminous surface")
        precondition(shifted.count>40,"Gold glints must move with the viewing angle")
        for index in 0..<3072 {
            precondition(goldWhite[index].x>=goldGray[index].x,"Reflected gold light must respond to background brightness")
        }
        print("金边高光检查：1024 个曲面朝向，局部强高光数／视角变化数：",glints.count,shifted.count,"；黑图无新增发光、亮图增强、有界辐射通过")
        let goldSource=try await execute("gemstoneGoldSourceCases",count:32,withScene:true,threads:32)
        let goldDimmed=try await execute("gemstoneGoldSourceCases",count:32,withScene:true,threads:32,gain:0.1)
        let goldOff=try await execute("gemstoneGoldSourceCases",count:32,withScene:true,threads:32,gain:0)
        let goldRadiance=GemstonePhotonTriangle.radiance(18)
        for index in 0..<32 {
            close(goldSource[index].w,1)
            for channel in 0..<3 {
                close(goldDimmed[index][channel],goldSource[index][channel]*0.1)
                close(goldOff[index][channel],0)
                if index==31 { close(goldSource[index][channel],goldRadiance[channel]) }
                if index>0 { precondition(goldSource[index][channel]>=goldSource[index-1][channel],"Gold source must have a smooth angular falloff") }
            }
        }
        print("暖金光芯检查：金属分类、光子与可见辐射一致、连续角度衰减及十分之一／关闭亮度通过")
        let gradientCases=try await execute("gemstoneGoldGradientCases",count:65,withScene:true,threads:65)
        for index in 0...64 {
            let t=Float(index)/64,point=SIMD3<Float>(repeating:-0.35+0.70*t)
            let expected=GemstonePhotonTriangle.radiance(18,at:point)
            for channel in 0..<3 { close(gradientCases[index][channel],expected[channel]) }
            if index>0 {
                precondition(gradientCases[index].x<gradientCases[index-1].x,"The broad gold gradient must have no repeated bright bands")
                precondition(abs(gradientCases[index].x-gradientCases[index-1].x)<0.05,"Gold gradient must change smoothly")
            }
        }
        let handDay=try await execute("gemstoneHandPriorityCases",count:2,withScene:true,threads:2,gain:0.025)
        let handNight=try await execute("gemstoneHandPriorityCases",count:2,withScene:true,threads:2,gain:1)
        let handFloor=try await execute("gemstoneHandPriorityCases",count:2,withScene:true,threads:2,gain:0)
        precondition(handFloor[0].z>1 && handDay[0].z>1.5,"The hand gem needs a visible daylight floor")
        precondition(handFloor[1].x>1 && handDay[1].x>1.5,"The hand gold must remain luminous on bright backgrounds")
        for index in 0..<2 {
            precondition(handNight[index].x>handDay[index].x*2 && handNight[index].z>handDay[index].z*2,"The hand must strengthen further on dark backgrounds")
        }
        print("连续金边渐变：65 个位置无条带、与光子参数一致；指针宝石与金边的亮景下限、暗景增强通过")
        let lifted=try await execute("gemstoneTransmissionLiftCases",count:260,withScene:true,threads:260,lift:1)
        let original=try await execute("gemstoneTransmissionLiftCases",count:260,withScene:true,threads:260,lift:0)
        precondition(lifted[0].x==0 && abs(lifted[256].x-1)<0.00001,"Transmission lift must preserve black and white")
        for index in 1...256 {
            precondition(lifted[index].x>=lifted[index-1].x && lifted[index].x>=original[index].x,"Transmission tones must remain ordered")
            precondition(lifted[index].x/original[index].x<3.61,"Shadow gain must stay bounded")
        }
        precondition(lifted[257].x>0.45 && lifted[257].x<0.52,"Mid-dark photographic detail should become visibly luminous")
        for index in 258...259 {
            let a=lifted[index],b=original[index]
            precondition(abs(a.x/b.x-a.y/b.y)<0.0001 && abs(a.z/b.z-a.y/b.y)<0.0001,"Transmission lift must preserve colour ratios")
        }
        print("透光暗部提亮：百分之十八灰 →",lifted[257].x,"，黑白端点／明暗顺序／增益上限／颜色比例通过")
        let whiteTransmission=try await execute("gemstoneBackdropTransmissionCases",count:16,withScene:true,threads:16,photo:white,gain:0,density:1.6)
        let grayTransmission=try await execute("gemstoneBackdropTransmissionCases",count:16,withScene:true,threads:16,photo:gray,gain:0,density:1.6)
        let blackTransmission=try await execute("gemstoneBackdropTransmissionCases",count:16,withScene:true,threads:16,photo:black,gain:0,density:1.6)
        let litTransmission=try await execute("gemstoneBackdropTransmissionCases",count:16,withScene:true,threads:16,photo:white,gain:1,density:1.6)
        for index in 0..<16 {
            for channel in 0..<3 {
                precondition(whiteTransmission[index][channel].isFinite)
                // Clear/opal transmission is linear; coloured layers also
                // include a small environment term with adaptive exposure.
                let ratio=grayTransmission[index][channel]/whiteTransmission[index][channel]
                precondition(abs(ratio-0.18)<(index<8 ? 0.001 : 0.008),"Background light response changed at sample \(index), channel \(channel): \(ratio)")
                precondition(blackTransmission[index][channel]<0.0001,"An unlit black background must remain black")
                precondition(abs(litTransmission[index][channel]-whiteTransmission[index][channel])<0.0001,"Night-light dimming must not darken background transmission")
                if index<8 { precondition(whiteTransmission[index][channel]>0.98,"Clear and opal layers must not become a gray filter under uniform white light") }
            }
        }
        func luminance(_ value:SIMD4<Float>)->Float { value.x*0.2126+value.y*0.7152+value.z*0.0722 }
        precondition(luminance(whiteTransmission[10])>0.55 && luminance(whiteTransmission[14])>0.68,"A short path through a coloured gem must retain backlight")
        precondition(luminance(whiteTransmission[11])<luminance(whiteTransmission[10]) && luminance(whiteTransmission[15])<luminance(whiteTransmission[14]),"Longer gemstone paths must retain their deeper colour")
        print("背景透光检查：乳白／无色层最低通道：",whiteTransmission.prefix(8).map{min($0.x,min($0.y,$0.z))}.min()!,"，光程 0.03 的蓝晶／青晶线性亮度：",luminance(whiteTransmission[10]),luminance(whiteTransmission[14]))
        let covered=try await execute("gemstoneEmbeddedLightCases",count:1024,withScene:true,scene:inside,threads:1024,photo:black)
        let bare=try await execute("gemstoneEmbeddedLightCases",count:1024,withScene:true,scene:outside,threads:1024,photo:black)
        func peak(_ value:SIMD4<Float>) -> Float { max(value.x,max(value.y,value.z)) }
        let sourceSamples = bare.filter { peak($0) > 0.002 }
        let uniformSource = sourceSamples.first!
        precondition(sourceSamples.allSatisfy { value in
            (0..<3).allSatisfy { abs(value[$0]-uniformSource[$0])<0.001 }
        },"The bare light inclusion must not contain painted brightness stripes")
        precondition(covered.allSatisfy { value in (0..<3).allSatisfy { value[$0].isFinite && value[$0]>=0 } })
        let coveredLit=covered.filter { peak($0)>0.002 }.count,bareLit=bare.filter { peak($0)>0.002 }.count
        precondition(coveredLit>0 && bareLit>0 && bareLit<1024/3,"The source should occupy only a small part of the crystal")
        let changed=zip(covered,bare).filter { abs(peak($0.0)-peak($0.1))>0.01 }.count
        precondition(changed>2,"Optical interfaces must change the internal light's image")
        print("局部光脉检查：1024 条光线，包裹后／裸露光脉可见数：",coveredLit,bareLit,"，晶体改变的光线数：",changed)
        let enabled=try await GemstoneRayResources.make(scene:GemstoneMeshBuilder.localLightStudy(),libraryURL:url)
        let disabled=try await GemstoneRayResources.make(scene:GemstoneMeshBuilder.localLightStudy(enabled:false),libraryURL:url)
        let blocked=try await GemstoneRayResources.make(scene:GemstoneMeshBuilder.localLightStudy(blocked:true),libraryURL:url)
        let passive=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:black)
        let passiveDirect=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:black,field:disabled.illumination)
        let passiveOff=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:disabled,threads:1024,photo:black)
        let passiveBlocked=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:blocked,threads:1024,photo:black)
        func energy(_ values:[SIMD4<Float>])->Float { values.reduce(0){$0+$1.x+$1.y+$1.z} }
        let onEnergy=energy(passive),offEnergy=energy(passiveOff),blockedEnergy=energy(passiveBlocked),directEnergy=energy(passiveDirect)
        let liftOnly=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:gray,field:disabled.illumination,gain:0,lift:1)
        let rawOnly=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:gray,field:disabled.illumination,gain:0,lift:0)
        let combined=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:gray,gain:1,lift:1)
        precondition(energy(liftOnly)>energy(rawOnly)*1.5,"A dark photographic background must remain visible through the crystal")
        precondition(energy(combined)>energy(liftOnly)+0.01,"Local emitters must still contribute alongside lifted transmission")
        print("透光提亮与光源组合：原透光／提亮／提亮加局部受光：",energy(rawOnly),energy(liftOnly),energy(combined))
        let passiveDimmed=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:black,gain:0.1)
        let passiveMuted=try await execute("gemstonePassiveLightCases",count:1024,withScene:true,scene:enabled,threads:1024,photo:black,gain:0)
        precondition(abs(energy(passiveDimmed)/onEnergy-0.1)<0.0001,"Passive illumination must follow the source's dimming")
        precondition(energy(passiveMuted)<0.0001,"Disabling emission must also disable received light")
        let dimmedSource=try await execute("gemstoneEmbeddedLightCases",count:1024,withScene:true,scene:inside,threads:1024,photo:black,gain:0.1)
        precondition(abs(energy(dimmedSource)/energy(covered)-0.1)<0.0001,"Visible sources and reflected source images must follow the same dimming")
        print("亮度调节检查：光源与被动受光比例／关闭受光：", energy(dimmedSource)/energy(covered), energy(passiveDimmed)/onEnergy, energy(passiveMuted))
        print("被动宝石光照：开启／关闭／遮挡／仅视线追踪：",onEnergy,offEnergy,blockedEnergy,directEnergy)
        let fieldOn=try await execute("gemstoneFieldProbeCases",count:1024,withScene:false,scene:enabled,threads:1024,photo:black)
        let fieldBlocked=try await execute("gemstoneFieldProbeCases",count:1024,withScene:false,scene:blocked,threads:1024,photo:black)
        print("被动宝石空间内的照明缓存：",energy(fieldOn),energy(fieldBlocked))
        precondition(onEnergy>0.01 && offEnergy<0.0001,"A passive neighbour must receive light from the source")
        precondition(onEnergy>directEnergy+0.005,"Light transport must add illumination beyond visible emitter images")
        precondition(blockedEnergy<onEnergy*0.20,"An opaque barrier must block the propagated illumination")
        let handScene=try await GemstoneRayResources.make(scene:.init(body:body,hand:GemstoneMeshBuilder.singleHand()),libraryURL:url)
        let visibility=try await execute("gemstoneHandVisibilityCases",count:512*256,withScene:true,scene:handScene,threads:512*256)
        let missing=visibility.filter { $0.x != 0 },hits=visibility.filter { $0.y != 0 }.count
        precondition(missing.isEmpty,"Hand cache mask missed ray/angle pairs: \(missing.prefix(8))")
        precondition(hits>1000,"Too few visibility rays hit the real hand")
        print("指针边界检查 / 命中数 / 漏检数：",visibility.count,hits,missing.count)
    }
}
