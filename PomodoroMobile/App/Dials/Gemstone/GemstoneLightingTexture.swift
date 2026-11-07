import Foundation
import Metal

nonisolated enum GemstoneLightingTexture {
    static func make(device: MTLDevice, queue: MTLCommandQueue, sourceURL: URL? = nil) throws -> MTLTexture {
        guard let url = sourceURL ?? Bundle.main.url(forResource: "GemstoneLighting-v1", withExtension: "bin") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let packed = try Data(contentsOf: url)
        guard packed.count > 16, packed.prefix(8) == Data("HDRLIT01".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let width = packed.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self))) }
        let height = packed.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self))) }
        guard width == 1024, height == 512 else { throw CocoaError(.fileReadCorruptFile) }
        let raw = try GemstoneCompression.decode(Data(packed.dropFirst(16)), count: width * height * 8)
        guard raw.count == width * height * 8 else { throw CocoaError(.fileReadCorruptFile) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: true)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw CocoaError(.fileReadCorruptFile) }
        raw.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 8)
        }
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeBlitCommandEncoder()!
        encoder.generateMipmaps(for: texture)
        encoder.endEncoding()
        command.commit()
        return texture
    }

}
