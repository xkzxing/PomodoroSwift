import Compression
import Foundation

nonisolated enum GemstoneCompression {
    static func decode(_ data: Data, count: Int) throws -> Data {
        guard !data.isEmpty, count > 0, count <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        var result = Data(count: count)
        let written = result.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, count,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written == count else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
}
