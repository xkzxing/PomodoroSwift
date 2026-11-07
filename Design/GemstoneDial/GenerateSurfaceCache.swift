import Foundation

/// Compile this utility with Models/GemstoneSculpture.swift and run from the
/// repository root after changing its contours or surface construction.
@main struct GenerateSurfaceCache {
    static func main() async throws {
        let maps = await GemstoneSculpture.maps.value
        if CommandLine.arguments.contains("--raw") {
            var raw = Data()
            raw.append(maps.normals.dataProvider!.data! as Data)
            raw.append(maps.surfaces.dataProvider!.data! as Data)
            try raw.write(to: URL(fileURLWithPath: "build/GemstoneSurface.raw"))
        }
        let bytes = try maps.compressedCache()
        try bytes.write(to: URL(fileURLWithPath: "PomodoroSwift/Resources/GemstoneSurface-v1.bin"), options: .atomic)
        print("Cached unlit geometry bytes:", bytes.count)
    }
}
