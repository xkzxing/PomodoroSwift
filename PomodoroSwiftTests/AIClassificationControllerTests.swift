import XCTest
@testable import PomodoroSwift

@MainActor
final class AIClassificationControllerTests: XCTestCase {
    func testStartClassificationSuccessPersistsAssignments() async {
        let panelId = UUID(uuidString: "A14C18E8-C979-4ED8-8746-D38F6F7D44B8")!
        let service = StubClassificationService(results: [.success([panelId: ["Task 1"]])])
        let controller = AIClassificationController(service: service)
        controller.inputText = "整理今天要做的事"

        var persistedAssignments: [UUID: [String]]?

        controller.startClassification(
            apiKey: "test-key",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        ) { @MainActor assignments in
            persistedAssignments = assignments
            return assignments.values.flatMap { $0 }.count
        }

        await waitForControllerToBecomeIdle(controller)

        XCTAssertEqual(persistedAssignments?[panelId], ["Task 1"])
        XCTAssertFalse(controller.statusIsError)
        XCTAssertTrue(controller.statusMessage.contains("Added 1"))
        XCTAssertTrue(controller.inputText.isEmpty)
    }

    func testStartClassificationFailureDoesNotPersist() async {
        let panelId = UUID()
        let service = StubClassificationService(results: [.failure(StubError.failure)])
        let controller = AIClassificationController(service: service)
        controller.inputText = "分类任务"

        var persistCallCount = 0

        controller.startClassification(
            apiKey: "test-key",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        ) { @MainActor assignments in
            persistCallCount += 1
            return assignments.values.flatMap { $0 }.count
        }

        await waitForControllerToBecomeIdle(controller)

        XCTAssertEqual(persistCallCount, 0)
        XCTAssertTrue(controller.statusIsError)
        XCTAssertFalse(controller.statusMessage.isEmpty)
    }

    func testCancelClassificationStopsAndDoesNotPersist() async {
        let panelId = UUID()
        let service = StubClassificationService(
            results: [.success([panelId: ["Task 1"]])],
            delayNanoseconds: 300_000_000
        )
        let controller = AIClassificationController(service: service)
        controller.inputText = "分类任务"

        var persistCallCount = 0

        controller.startClassification(
            apiKey: "test-key",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        ) { @MainActor assignments in
            persistCallCount += 1
            return assignments.values.flatMap { $0 }.count
        }

        controller.cancelClassification()
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertFalse(controller.isClassifying)
        XCTAssertEqual(controller.statusMessage, "AI classification cancelled.")
        XCTAssertEqual(persistCallCount, 0)
    }

    func testRetryClassificationUsesSameFlow() async {
        let panelId = UUID(uuidString: "5B86EE67-CCDF-48A6-A9B4-8A3FC9EE5FB1")!
        let service = StubClassificationService(results: [
            .failure(StubError.failure),
            .success([panelId: ["Task 2"]])
        ])
        let controller = AIClassificationController(service: service)
        controller.inputText = "重试分类"

        var persistedAssignments: [UUID: [String]]?

        controller.startClassification(
            apiKey: "test-key",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        ) { @MainActor assignments in
            persistedAssignments = assignments
            return assignments.values.flatMap { $0 }.count
        }

        await waitForControllerToBecomeIdle(controller)
        XCTAssertTrue(controller.statusIsError)

        controller.retryClassification(
            apiKey: "test-key",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        ) { @MainActor assignments in
            persistedAssignments = assignments
            return assignments.values.flatMap { $0 }.count
        }

        await waitForControllerToBecomeIdle(controller)

        XCTAssertEqual(persistedAssignments?[panelId], ["Task 2"])
        XCTAssertFalse(controller.statusIsError)
    }

    private func waitForControllerToBecomeIdle(
        _ controller: AIClassificationController,
        timeout: TimeInterval = 2.0
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !controller.isClassifying {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Controller did not become idle before timeout")
    }
}

private enum StubError: Error {
    case failure
}

private actor StubClassificationService: AIToDoClassificationService {
    private var results: [Result<[UUID: [String]], Error>]
    private let delayNanoseconds: UInt64

    init(
        results: [Result<[UUID: [String]], Error>],
        delayNanoseconds: UInt64 = 0
    ) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func classifyTasks(
        apiKey: String,
        rawInput: String,
        panels: [AIPanelContext]
    ) async throws -> [UUID: [String]] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        try Task.checkCancellation()

        guard !results.isEmpty else {
            return [:]
        }

        let result = results.removeFirst()
        return try result.get()
    }
}
