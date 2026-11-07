import Foundation
import CoreImage
import CoreGraphics

@main struct GenerateLightingCache {
    static func main() throws {
        let source = URL(fileURLWithPath: "Design/GemstoneDial/Lighting/studio_small_09_1k.exr")
        let image = CIImage(contentsOf: source)!
        let width = Int(image.extent.width), height = Int(image.extent.height)
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let context = CIContext(options: [.workingColorSpace: space])
        var pixels = [Float16](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 8,
                           bounds: image.extent, format: .RGBAh, colorSpace: space)
        }
        var sum: Float = 0
        for index in pixels.indices where index % 4 != 3 { sum += Float(pixels[index]) }
        let scale = 0.35 / max(0.0001, sum / Float(width * height * 3))
        for index in pixels.indices where index % 4 != 3 { pixels[index] = Float16(Float(pixels[index]) * scale) }
        let raw = pixels.withUnsafeBytes { Data($0) }
        var output = Data("HDRLIT01".utf8)
        for dimension in [width, height] {
            var number = UInt32(dimension).littleEndian
            withUnsafeBytes(of: &number) { output.append(contentsOf: $0) }
        }
        output.append(try (raw as NSData).compressed(using: .lzfse) as Data)
        try output.write(to: URL(fileURLWithPath: "PomodoroSwift/Resources/GemstoneLighting-v1.bin"), options: .atomic)
        print("HDR environment:", width, height, "compressed bytes:", output.count)
    }
}
