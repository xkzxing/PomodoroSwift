import XCTest
@testable import PomodoroSwift

final class AIClassificationServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
    }

    func testClassifyTasksWithValidJSONResponse() async throws {
        let panelId = UUID(uuidString: "9A3A085C-0C53-46B3-9048-C5F46D4B3D6C")!
        let service = makeService()

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let payload = try JSONSerialization.jsonObject(with: requestBodyData(request)) as! [String: Any]
            XCTAssertEqual(payload["model"] as? String, "qwen3.8-flash")
            XCTAssertEqual(payload["enable_thinking"] as? Bool, false)
            XCTAssertNil(payload["extra_body"])
            let content = "{\"assignments\":[{\"panelId\":\"\(panelId.uuidString)\",\"tasks\":[\"Task A\",\"Task B\"]}]}"
            let body = try makeResponseBody(content: content)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let result = try await service.classifyTasks(
            apiKey: "test-key",
            rawInput: "foo",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        )

        XCTAssertEqual(result[panelId], ["Task A", "Task B"])
    }

    func testClassifyTasksParsesCodeFenceJSON() async throws {
        let panelId = UUID(uuidString: "4135E026-C54A-42F4-9E66-281BBA8D47E7")!
        let service = makeService()

        MockURLProtocol.requestHandler = { request in
            let fenced = "```json\\n{\"assignments\":[{\"panelId\":\"\(panelId.uuidString)\",\"tasks\":[\"Task C\"]}]}\\n```"
            let body = try makeResponseBody(content: fenced)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let result = try await service.classifyTasks(
            apiKey: "test-key",
            rawInput: "foo",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        )

        XCTAssertEqual(result[panelId], ["Task C"])
    }

    func testClassifyTasksThrowsForInvalidHTTPStatus() async {
        let panelId = UUID()
        let service = makeService()

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data("server-error".utf8)
            )
        }

        do {
            _ = try await service.classifyTasks(
                apiKey: "test-key",
                rawInput: "foo",
                panels: [AIPanelContext(id: panelId, title: "Work")]
            )
            XCTFail("Expected invalidHTTPStatus error")
        } catch let error as AIToDoClassifierError {
            switch error {
            case .invalidHTTPStatus(let code, _):
                XCTAssertEqual(code, 500)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testClassifyTasksThrowsWhenOutputTooLarge() async {
        let panelId = UUID()
        let service = makeService(maxResponseBytes: 32)

        MockURLProtocol.requestHandler = { request in
            let hugeText = String(repeating: "A", count: 300)
            let body = try makeResponseBody(content: hugeText)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        do {
            _ = try await service.classifyTasks(
                apiKey: "test-key",
                rawInput: "foo",
                panels: [AIPanelContext(id: panelId, title: "Work")]
            )
            XCTFail("Expected responseTooLarge error")
        } catch let error as AIToDoClassifierError {
            switch error {
            case .responseTooLarge(let limitBytes, let actualBytes):
                XCTAssertEqual(limitBytes, 32)
                XCTAssertGreaterThan(actualBytes, 32)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testClassifyTasksDetectsDegenerateRepetition() async {
        let panelId = UUID()
        let service = makeService()

        MockURLProtocol.requestHandler = { request in
            let repeated = String(repeating: "哈", count: 80)
            let body = try makeResponseBody(content: repeated)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        do {
            _ = try await service.classifyTasks(
                apiKey: "test-key",
                rawInput: "foo",
                panels: [AIPanelContext(id: panelId, title: "Work")]
            )
            XCTFail("Expected degenerateOutputDetected error")
        } catch let error as AIToDoClassifierError {
            XCTAssertEqual(error, .degenerateOutputDetected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testClassifyTasksTimesOut() async {
        let panelId = UUID()
        let service = makeService(timeoutSeconds: 0.05)

        MockURLProtocol.requestHandler = { request in
            try await Task.sleep(nanoseconds: 300_000_000)
            let body = try makeResponseBody(content: "{}")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        do {
            _ = try await service.classifyTasks(
                apiKey: "test-key",
                rawInput: "foo",
                panels: [AIPanelContext(id: panelId, title: "Work")]
            )
            XCTFail("Expected timeout error")
        } catch let error as AIToDoClassifierError {
            switch error {
            case .timedOut:
                XCTAssertTrue(true)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testClassifyTasksRetriesOnceOnInvalidModelJSON() async throws {
        let panelId = UUID(uuidString: "1883A0D3-B89C-4D8C-BE49-C4E4A4AC2B5E")!
        let service = makeService()

        var callCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            let currentCall = lock.withLock {
                callCount += 1
                return callCount
            }

            if currentCall == 1 {
                let body = try makeResponseBody(content: "not-json")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    body
                )
            }

            let content = "{\"assignments\":[{\"panelId\":\"\(panelId.uuidString)\",\"tasks\":[\"Task D\"]}]}"
            let body = try makeResponseBody(content: content)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let result = try await service.classifyTasks(
            apiKey: "test-key",
            rawInput: "foo",
            panels: [AIPanelContext(id: panelId, title: "Work")]
        )

        XCTAssertEqual(result[panelId], ["Task D"])
        XCTAssertEqual(callCount, 2)
    }

    private func makeService(
        timeoutSeconds: TimeInterval = 20,
        maxResponseBytes: Int = 24 * 1024
    ) -> DashScopeAIToDoClassificationService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        return DashScopeAIToDoClassificationService(
            session: session,
            timeoutSeconds: timeoutSeconds,
            maxResponseBytes: maxResponseBytes,
            maxRetryCount: 1
        )
    }
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        result.append(buffer, count: count)
    }
    return result
}

private func makeResponseBody(content: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "choices": [
            ["message": ["content": content]]
        ]
    ])
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        loadingTask = Task {
            do {
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}
