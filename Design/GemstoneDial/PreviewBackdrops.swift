import AppKit
import ImageIO

/// Stable image identities let the renderer reuse its background texture between timer updates.
@MainActor enum PreviewBackdrops {
    struct Backdrop: Identifiable {
        let id: String
        let name: String
        let detail: String
        let image: NSImage
        var source: URL? = nil
    }

    private struct Photograph: Decodable {
        let id: String, name: String, detail: String, file: String, source: URL
    }

    static let photographs: [Backdrop] = {
        let arguments=CommandLine.arguments
        let explicit=arguments.firstIndex(of:"--photo-directory").flatMap { index -> URL? in
            index+1<arguments.count ? URL(fileURLWithPath:arguments[index+1]) : nil
        }
        let candidates=[explicit,Bundle.main.resourceURL?.appendingPathComponent("Photos"),
            URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Photos")]
        guard let directory=candidates.compactMap({$0}).first(where:{
            FileManager.default.fileExists(atPath:$0.appendingPathComponent("manifest.json").path)
        }), let data=try? Data(contentsOf:directory.appendingPathComponent("manifest.json")),
              let records=try? JSONDecoder().decode([Photograph].self,from:data) else { return [] }
        return records.compactMap { record in
            guard let image=loadPhotograph(directory.appendingPathComponent(record.file)) else { return nil }
            return Backdrop(id:record.id,name:record.name,detail:record.detail,image:image,source:record.source)
        }
    }()

    static let diagnostics: [Backdrop] = [
        .init(id: "cathedral", name: "教堂柔光", detail: "暖色石墙与彩窗", image: cathedral()),
        .init(id: "pearl", name: "珍珠白", detail: "浅色背景下的透光与金边", image: make(.pearl)),
        .init(id: "graphite", name: "石墨黑", detail: "暗背景下的反射与内部亮部", image: make(.graphite)),
        .init(id: "neutral", name: "中性灰", detail: "减少背景色对材质的干扰", image: make(.neutral)),
        .init(id: "warm", name: "琥珀暮光", detail: "暖光与深色阴影", image: make(.warm)),
        .init(id: "cool", name: "冰蓝晨光", detail: "冷色渐变与明亮天光", image: make(.cool)),
        .init(id: "forest", name: "林间光影", detail: "绿色环境与疏密光斑", image: make(.forest)),
        .init(id: "stone", name: "暖砂岩", detail: "低饱和暖色与细密纹理", image: make(.stone)),
        .init(id: "city", name: "城市夜色", detail: "冷色暗部与点状灯光", image: make(.city)),
        .init(id: "window", name: "日光窗边", detail: "明暗交界与窗框折射", image: make(.window)),
        .init(id: "rose", name: "玫瑰暮色", detail: "粉紫环境下的蓝绿彩晶", image: make(.rose)),
        .init(id: "contrast", name: "黑白光栅", detail: "观察折射位移与边缘变形", image: make(.contrast))
    ]

    static let all = photographs + diagnostics

    /// Preserve photographic detail and orientation, while bounding memory for
    /// user-selected camera originals. A background is decoded once, not per tick.
    static func loadPhotograph(_ url: URL) -> NSImage? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceShouldCacheImmediately:true,
                kCGImageSourceThumbnailMaxPixelSize:2560
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage:image,size:CGSize(width:image.width,height:image.height))
    }

    private enum Style { case pearl, graphite, neutral, warm, cool, forest, stone, city, window, rose, contrast }

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    private static func gradient(_ ctx: CGContext, _ colors: [UInt32], from: CGPoint, to: CGPoint) {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: colors.map { color($0) } as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func glow(_ ctx: CGContext, at point: CGPoint, radius: CGFloat, tint: UInt32, opacity: CGFloat) {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [color(tint, opacity), color(tint, opacity * 0.40), color(tint, 0)] as CFArray,
                                  locations: [0, 0.38, 1])!
        ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                               endCenter: point, endRadius: radius, options: [])
    }

    private static func fill(_ ctx: CGContext, _ rect: CGRect, _ tint: UInt32, _ opacity: CGFloat = 1) {
        ctx.setFillColor(color(tint, opacity)); ctx.fill(rect)
    }

    private struct Random {
        var state: UInt64 = 0x9e3779b97f4a7c15
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 40) / CGFloat(1 << 24)
        }
    }

    private static func make(_ style: Style) -> NSImage {
        let pixels = 1320
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(pixels) / 1000, y: CGFloat(pixels) / 1000)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        var rng = Random()
        switch style {
        case .pearl:
            gradient(ctx, [0xe5e3df, 0xfdfcf9, 0xe7eaf0], from: .init(x: 0, y: 0), to: .init(x: 850, y: 1000))
            glow(ctx, at: .init(x: 170, y: 820), radius: 620, tint: 0xffffff, opacity: 0.85)
            glow(ctx, at: .init(x: 950, y: 150), radius: 550, tint: 0xbac6d4, opacity: 0.22)
        case .graphite:
            gradient(ctx, [0x101217, 0x363a42, 0x17191d], from: .init(x: 50, y: 50), to: .init(x: 1000, y: 1000))
            glow(ctx, at: .init(x: 60, y: 780), radius: 520, tint: 0xa2b6d1, opacity: 0.20)
            glow(ctx, at: .init(x: 970, y: 200), radius: 450, tint: 0xc69a65, opacity: 0.12)
        case .neutral:
            gradient(ctx, [0x73777c, 0xaaaeb3], from: .init(x: 0, y: 0), to: .init(x: 0, y: 1000))
            glow(ctx, at: .init(x: 230, y: 840), radius: 750, tint: 0xffffff, opacity: 0.12)
        case .warm:
            gradient(ctx, [0x231d27, 0x815743, 0xe4ac72], from: .init(x: 200, y: 0), to: .init(x: 800, y: 1000))
            glow(ctx, at: .init(x: 170, y: 720), radius: 500, tint: 0xffd4a1, opacity: 0.65)
            glow(ctx, at: .init(x: 890, y: 300), radius: 380, tint: 0xa5a3bb, opacity: 0.28)
        case .cool:
            gradient(ctx, [0x315b7c, 0xa9d3df, 0xf1f5f0], from: .init(x: 0, y: 0), to: .init(x: 750, y: 1000))
            for i in 0..<9 {
                glow(ctx, at: .init(x: CGFloat(i) * 150 - 100, y: 700 + sin(CGFloat(i)) * 130), radius: 240,
                     tint: 0xffffff, opacity: 0.36)
            }
        case .forest:
            gradient(ctx, [0x102f2a, 0x446455, 0x91a78c], from: .init(x: 0, y: 0), to: .init(x: 650, y: 1000))
            for i in 0..<80 {
                let p = CGPoint(x: rng.next() * 1200 - 100, y: rng.next() * 1200 - 100)
                let tint: UInt32 = i % 3 == 0 ? 0xcdddac : i % 3 == 1 ? 0x163c32 : 0x6f9970
                glow(ctx, at: p, radius: 40 + rng.next() * 180, tint: tint, opacity: 0.12 + rng.next() * 0.22)
            }
            glow(ctx, at: .init(x: 160, y: 860), radius: 250, tint: 0xf8edc2, opacity: 0.65)
        case .stone:
            gradient(ctx, [0xa78b71, 0xe5d4ba, 0xc9b69e], from: .init(x: 900, y: 0), to: .init(x: 80, y: 1000))
            for _ in 0..<7000 {
                let x = rng.next() * 1000, y = rng.next() * 1000, w = 0.3 + rng.next() * 2.8
                fill(ctx, .init(x: x, y: y, width: w, height: w * 0.6), rng.next() > 0.5 ? 0x725941 : 0xfff2da, 0.05 + rng.next() * 0.08)
            }
            for y in [CGFloat(180), 510, 840] {
                fill(ctx, .init(x: 0, y: y, width: 1000, height: 2), 0x6b594a, 0.15)
                fill(ctx, .init(x: 0, y: y + 2, width: 1000, height: 2), 0xfff3dc, 0.36)
            }
        case .city:
            gradient(ctx, [0x101b2e, 0x344b6c, 0x7386a0], from: .init(x: 0, y: 0), to: .init(x: 0, y: 1000))
            for i in 0..<17 {
                let x = CGFloat(i) * 68 - 40, h = 190 + rng.next() * 460
                fill(ctx, .init(x: x, y: 0, width: 61, height: h), i % 2 == 0 ? 0x16263b : 0x23364d)
                for row in 0..<Int(h / 23) {
                    for col in 0..<3 where rng.next() > 0.45 {
                        let p = CGPoint(x: x + 11 + CGFloat(col) * 17, y: CGFloat(row) * 23 + 14)
                        let tint: UInt32 = rng.next() > 0.3 ? 0xffd4a0 : 0xb3e6ef
                        glow(ctx, at: p, radius: 12, tint: tint, opacity: 0.35)
                        fill(ctx, .init(x: p.x - 2, y: p.y - 3, width: 4, height: 6), tint, 0.75)
                    }
                }
            }
            for _ in 0..<24 {
                glow(ctx, at: .init(x: rng.next() * 1000, y: rng.next() * 340), radius: 18 + rng.next() * 28,
                     tint: rng.next() > 0.5 ? 0xffbe7e : 0x9adbe9, opacity: 0.4)
            }
        case .window:
            gradient(ctx, [0x777a76, 0xc9c7ba], from: .init(x: 0, y: 0), to: .init(x: 1000, y: 1000))
            fill(ctx, .init(x: 60, y: 370, width: 610, height: 680), 0xe9f2ee)
            glow(ctx, at: .init(x: 350, y: 760), radius: 450, tint: 0xffffff, opacity: 0.95)
            for x in [CGFloat(60), 350, 640] { fill(ctx, .init(x: x, y: 370, width: 23, height: 680), 0x343f3e) }
            fill(ctx, .init(x: 60, y: 650, width: 610, height: 23), 0x343f3e)
            fill(ctx, .init(x: 60, y: 370, width: 610, height: 20), 0x343f3e)
            glow(ctx, at: .init(x: 780, y: 140), radius: 380, tint: 0xe4b886, opacity: 0.25)
        case .rose:
            gradient(ctx, [0x3e3a59, 0xad859b, 0xf0c3ad], from: .init(x: 0, y: 0), to: .init(x: 800, y: 1000))
            glow(ctx, at: .init(x: 180, y: 730), radius: 430, tint: 0xffe4d1, opacity: 0.65)
            glow(ctx, at: .init(x: 850, y: 260), radius: 550, tint: 0x7c93bb, opacity: 0.35)
        case .contrast:
            fill(ctx, bounds, 0xeae9e6)
            for i in 0..<10 where i % 2 == 0 {
                fill(ctx, .init(x: CGFloat(i) * 100, y: 0, width: 100, height: 1000), 0x23272b)
            }
            fill(ctx, .init(x: 0, y: 450, width: 1000, height: 100), 0x969b9d)
        }
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 1000, height: 1000))
    }

    private static func cathedral() -> NSImage {
        let arguments=CommandLine.arguments
        let reference=arguments.firstIndex(of:"--reference").flatMap { index -> URL? in
            guard index+1<arguments.count else { return nil }
            return URL(fileURLWithPath:arguments[index+1])
        }
        guard let url = reference ?? Bundle.main.url(forResource: "PreviewBackdrop", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return make(.warm) }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let crop = cg.cropping(to: CGRect(x: 1080, y: 0, width: 174, height: 190)) else { return make(.warm) }
        return NSImage(cgImage: crop, size: NSSize(width: 1000, height: 1092))
    }
}
