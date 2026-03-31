import Foundation

struct AIPanelContext: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
}

protocol AIToDoClassificationService {
    func classifyTasks(
        apiKey: String,
        rawInput: String,
        panels: [AIPanelContext]
    ) async throws -> [UUID: [String]]
}
