import Foundation

enum AIToDoClassifierError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidHTTPStatus(Int, String)
    case emptyModelResponse
    case invalidModelJSON
    case responseTooLarge(limitBytes: Int, actualBytes: Int)
    case degenerateOutputDetected
    case timedOut(seconds: TimeInterval)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "AI 分类失败：接口地址无效。"
        case .invalidHTTPStatus(let code, let body):
            let bodyText = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if bodyText.isEmpty {
                return "AI 分类失败：远端服务返回 HTTP \(code)。"
            }
            return "AI 分类失败：远端服务返回 HTTP \(code)：\(bodyText)"
        case .emptyModelResponse:
            return "AI 分类失败：模型返回了空内容。"
        case .invalidModelJSON:
            return "AI 分类失败：模型未返回合法 JSON。"
        case .responseTooLarge(let limit, let actual):
            return "AI 分类失败：模型输出过长（\(actual) 字节，超过上限 \(limit) 字节）。"
        case .degenerateOutputDetected:
            return "AI 分类失败：检测到异常重复输出，已自动终止。"
        case .timedOut(let seconds):
            return "AI 分类失败：请求超时（\(Int(seconds)) 秒）。"
        case .cancelled:
            return "AI 分类已取消。"
        }
    }
}

final class DashScopeAIToDoClassificationService: AIToDoClassificationService {
    private let endpoint: URL
    private let model: String
    private let session: URLSession
    private let timeoutSeconds: TimeInterval
    private let maxResponseBytes: Int
    private let maxRetryCount: Int

    init(
        endpoint: URL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
        model: String = "qwen-plus",
        session: URLSession? = nil,
        timeoutSeconds: TimeInterval = 20,
        maxResponseBytes: Int = 24 * 1024,
        maxRetryCount: Int = 1
    ) {
        self.endpoint = endpoint
        self.model = model
        self.session = session ?? URLSession(configuration: .default)
        self.timeoutSeconds = timeoutSeconds
        self.maxResponseBytes = maxResponseBytes
        self.maxRetryCount = maxRetryCount
    }

    func classifyTasks(
        apiKey: String,
        rawInput: String,
        panels: [AIPanelContext]
    ) async throws -> [UUID: [String]] {
        guard !Task.isCancelled else { throw AIToDoClassifierError.cancelled }

        let primaryPayload = makePayload(rawInput: rawInput, panels: panels, strictJSONRetry: false)
        let retryPayload = makePayload(rawInput: rawInput, panels: panels, strictJSONRetry: true)

        let classification: AIClassificationOutput
        do {
            classification = try await requestClassification(apiKey: apiKey, payload: primaryPayload)
        } catch is CancellationError {
            throw AIToDoClassifierError.cancelled
        } catch {
            guard maxRetryCount > 0 else {
                throw mapCancellation(error)
            }
            do {
                classification = try await requestClassification(apiKey: apiKey, payload: retryPayload)
            } catch {
                throw mapCancellation(error)
            }
        }

        let validPanelIds = Set(panels.map { $0.id })
        var result: [UUID: [String]] = [:]

        for assignment in classification.assignments {
            guard let panelId = UUID(uuidString: assignment.panelId),
                  validPanelIds.contains(panelId) else {
                continue
            }

            let normalizedTasks = assignment.tasks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !normalizedTasks.isEmpty else { continue }
            result[panelId, default: []].append(contentsOf: normalizedTasks)
        }

        return result
    }

    private func makePayload(
        rawInput: String,
        panels: [AIPanelContext],
        strictJSONRetry: Bool
    ) -> ChatCompletionRequest {
        let panelsData = (try? JSONEncoder().encode(panels)) ?? Data("[]".utf8)
        let panelsJSON = String(data: panelsData, encoding: .utf8) ?? "[]"

        var systemPrompt = """
        你是待办事项分类助手。你必须把用户输入拆分成可执行任务，并归类到给定面板。
        只允许使用面板列表中已有的 panelId，禁止创建新分类。
        你必须只输出一个 JSON 对象，格式如下：
        {"assignments":[{"panelId":"UUID","tasks":["任务1","任务2"]}]}
        不要输出任何额外解释、注释或 Markdown。
        """

        var userPrompt = """
        面板列表(JSON):
        \(panelsJSON)

        用户输入:
        \(rawInput)
        """

        let temperature: Double
        if strictJSONRetry {
            systemPrompt += "\n再次强调：只返回一个合法 JSON 对象。"
            userPrompt += "\n请只返回 JSON，不要包含任何其他字符。"
            temperature = 0.1
        } else {
            temperature = 0.2
        }

        return ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: temperature,
            responseFormat: .init(type: "json_object")
        )
    }

    private func requestClassification(
        apiKey: String,
        payload: ChatCompletionRequest
    ) async throws -> AIClassificationOutput {
        guard endpoint.absoluteString.hasPrefix("http") else {
            throw AIToDoClassifierError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await withTimeout(seconds: timeoutSeconds) { [session] in
            try await session.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIToDoClassifierError.invalidHTTPStatus(-1, "")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIToDoClassifierError.invalidHTTPStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIToDoClassifierError.emptyModelResponse
        }

        try validateOutputHealth(content)

        let directText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let directData = directText.data(using: .utf8),
           let directOutput = try? JSONDecoder().decode(AIClassificationOutput.self, from: directData) {
            return directOutput
        }

        let extractedText = extractJSONObject(from: content)
        try validateOutputHealth(extractedText)
        guard let extractedData = extractedText.data(using: .utf8),
              let extractedOutput = try? JSONDecoder().decode(AIClassificationOutput.self, from: extractedData) else {
            throw AIToDoClassifierError.invalidModelJSON
        }

        return extractedOutput
    }

    private func validateOutputHealth(_ content: String) throws {
        let byteCount = content.lengthOfBytes(using: .utf8)
        if byteCount > maxResponseBytes {
            throw AIToDoClassifierError.responseTooLarge(limitBytes: maxResponseBytes, actualBytes: byteCount)
        }

        if hasDegenerateRepetition(in: content) {
            throw AIToDoClassifierError.degenerateOutputDetected
        }
    }

    private func hasDegenerateRepetition(in content: String) -> Bool {
        let normalized = content.filter { !$0.isWhitespace }
        guard normalized.count >= 48 else { return false }

        let characters = Array(normalized)
        let totalCount = characters.count
        guard totalCount > 0 else { return false }

        var frequency: [Character: Int] = [:]
        for char in characters {
            frequency[char, default: 0] += 1
        }
        if let maxCount = frequency.values.max(),
           Double(maxCount) / Double(totalCount) >= 0.88 {
            return true
        }

        for unitLength in 1...3 {
            guard totalCount >= unitLength * 16 else { continue }
            let unit = Array(characters[0..<unitLength])
            var matchCount = 0
            var index = 0
            while index + unitLength <= totalCount {
                let chunk = Array(characters[index..<(index + unitLength)])
                if chunk == unit {
                    matchCount += unitLength
                }
                index += unitLength
            }
            if Double(matchCount) / Double(totalCount) >= 0.9 {
                return true
            }
        }

        return false
    }

    private func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count >= 3 {
                let body = lines.dropFirst().dropLast().joined(separator: "\n")
                return extractJSONObject(from: body)
            }
        }

        if let first = trimmed.firstIndex(of: "{"),
           let last = trimmed.lastIndex(of: "}") {
            return String(trimmed[first...last])
        }

        return trimmed
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                let sleepSeconds = max(seconds, 0.001)
                try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                throw AIToDoClassifierError.timedOut(seconds: seconds)
            }

            guard let firstFinished = try await group.next() else {
                throw AIToDoClassifierError.timedOut(seconds: seconds)
            }
            group.cancelAll()
            return firstFinished
        }
    }

    private func mapCancellation(_ error: Error) -> Error {
        if error is CancellationError {
            return AIToDoClassifierError.cancelled
        }
        return error
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String?
    }
}

private struct AIClassificationOutput: Decodable, Sendable {
    let assignments: [Assignment]

    struct Assignment: Decodable, Sendable {
        let panelId: String
        let tasks: [String]
    }
}
