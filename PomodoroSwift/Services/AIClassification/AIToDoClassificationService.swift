import Foundation

enum DashScopeConfiguration {
    static let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
    static let model = "qwen3.8-flash"
}

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
