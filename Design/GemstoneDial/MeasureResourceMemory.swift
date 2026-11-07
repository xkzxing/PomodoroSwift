import Darwin
import Foundation
import MetalKit

/// Run in separate fresh processes, with and without --retain-cpu-mesh.
/// This isolates the old mesh-task retention from otherwise identical GPU
/// resources; it measures allocated resources, not the full app's UI footprint.
@main struct MeasureResourceMemory {
    nonisolated static func load(retainingMesh: Bool) async throws -> GemstoneRayResources {
        let scene = retainingMesh ? await GemstoneMeshSceneData.dial.value : GemstoneMeshBuilder.dial()
        return try await GemstoneRayResources.make(scene: scene,
            libraryURL: URL(fileURLWithPath: "build/GemstoneRayTracing.metallib"))
    }

    nonisolated static func footprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw CocoaError(.featureUnsupported) }
        return info.phys_footprint
    }

    static func main() async throws {
        let retainingMesh = CommandLine.arguments.contains("--retain-cpu-mesh")
        let resources = try await load(retainingMesh: retainingMesh)
        // Allow completed command-buffer/autorelease cleanups before sampling.
        try await Task.sleep(for: .milliseconds(200))
        try withExtendedLifetime(resources) {
            var heap = malloc_statistics_t()
            malloc_zone_statistics(nil, &heap)
            let report: [String: Any] = [
                "retainedCPUMesh": retainingMesh,
                "physicalFootprintBytes": try footprint(),
                "heapInUseBytes": heap.size_in_use,
                "heapReservedBytes": heap.size_allocated,
                "gpuVertexAndBoundaryBytes": resources.body.vertices.length + resources.body.materials.length
                    + resources.hand.vertices.length + resources.hand.materials.length,
                "accelerationBytes": resources.body.acceleration.size + resources.hand.acceleration.size,
                "triangles": resources.body.triangleCount + resources.hand.triangleCount
            ]
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        }
    }
}
