import Foundation
import Combine

@MainActor
final class AIClassificationController: ObservableObject {
    @Published var inputText: String = ""
    @Published var isClassifying: Bool = false
    @Published var statusMessage: String = ""
    @Published var statusIsError: Bool = false

    private let service: AIToDoClassificationService
    private var requestID: UUID?
    private var classificationTask: Task<Void, Never>?

    init(service: AIToDoClassificationService) {
        self.service = service
    }

    convenience init() {
        self.init(service: DashScopeAIToDoClassificationService())
    }

    func startClassification(
        apiKey: String,
        panels: [AIPanelContext],
        persistAssignments: @MainActor @escaping ([UUID: [String]]) -> Int
    ) {
        guard !isClassifying else { return }

        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedInput = inputText
        let trimmedInput = submittedInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedApiKey.isEmpty else {
            statusIsError = true
            statusMessage = "Please input DashScope API Key first."
            return
        }

        guard !trimmedInput.isEmpty else {
            statusIsError = true
            statusMessage = "Please describe your tasks first."
            return
        }

        guard !panels.isEmpty else {
            statusIsError = true
            statusMessage = "No available panel to classify into."
            return
        }

        statusMessage = ""
        statusIsError = false
        isClassifying = true

        let id = UUID()
        requestID = id
        classificationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let assignments = try await self.service.classifyTasks(
                    apiKey: trimmedApiKey,
                    rawInput: trimmedInput,
                    panels: panels
                )

                try Task.checkCancellation()

                guard self.requestID == id else { return }
                // Keep cancellation validation and persistence in the same actor turn.
                let inserted = persistAssignments(assignments)
                self.isClassifying = false
                self.classificationTask = nil
                self.requestID = nil
                self.statusIsError = false

                if inserted > 0 {
                    self.statusMessage = "Added \(inserted) task(s) into existing panels."
                    if self.inputText == submittedInput { self.inputText = "" }
                } else {
                    self.statusMessage = "No valid tasks were returned by AI."
                }
            } catch {
                guard self.requestID == id else { return }
                self.isClassifying = false
                self.statusIsError = true
                self.statusMessage = self.userFacingError(error)
                self.classificationTask = nil
                self.requestID = nil
            }
        }
    }

    func retryClassification(
        apiKey: String,
        panels: [AIPanelContext],
        persistAssignments: @MainActor @escaping ([UUID: [String]]) -> Int
    ) {
        startClassification(
            apiKey: apiKey,
            panels: panels,
            persistAssignments: persistAssignments
        )
    }

    func cancelClassification() {
        requestID = nil
        classificationTask?.cancel()
        classificationTask = nil

        guard isClassifying else { return }
        isClassifying = false
        statusIsError = true
        statusMessage = "AI classification cancelled."
    }

    private func userFacingError(_ error: Error) -> String {
        if let classifierError = error as? AIToDoClassifierError,
           let description = classifierError.errorDescription {
            return description
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return "AI 分类失败：无法连接模型服务，请检查网络、代理或 DNS 设置。"
            default:
                return "AI 分类失败：网络请求异常（\(urlError.code.rawValue)）。"
            }
        }

        if error is CancellationError {
            return "AI classification cancelled."
        }

        return "AI 分类失败：\(error.localizedDescription)"
    }
}
