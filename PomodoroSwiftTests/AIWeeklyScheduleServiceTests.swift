import XCTest
@testable import PomodoroSwift

@MainActor
final class AIWeeklyScheduleServiceTests: XCTestCase {
    private let validJSON = """
    {"events":[{"title":"  开会  ","weekdays":[1,3,5],"start":"14:10","end":"15:40","color":"teal"}],"needsClarification":[]}
    """

    override func tearDown() {
        WeeklyScheduleURLProtocol.handler = nil
        super.tearDown()
    }

    func testDecodesMultipleDaysAndExactMinutes() throws {
        let events = try DashScopeAIWeeklyScheduleService.decodeEvents(validJSON)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].title, "开会")
        XCTAssertEqual(events[0].weekdays, [.monday, .wednesday, .friday])
        XCTAssertEqual(events[0].startMinute, 850)
        XCTAssertEqual(events[0].endMinute, 940)
        XCTAssertEqual(events[0].color, .teal)
    }

    func testAcceptsFencedJSONAndMidnightEnd() throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let text = """
        {"events":[{"title":"阅读","weekdays":[7],"start":"23:10","end":"24:00"}],"needsClarification":[]}
        """
        let events = try DashScopeAIWeeklyScheduleService.decodeEvents(fence + "json\n" + text + "\n" + fence)
        XCTAssertEqual(events.first?.endMinute, 1440)
        XCTAssertEqual(events.first?.color, .blue)
    }

    func testRejectsWholeResponseIfAnyEventIsInvalid() {
        let invalid = """
        {"events":[{"title":"阅读","weekdays":[1],"start":"09:00","end":"10:00"},
        {"title":"开会","weekdays":[8],"start":"11:00","end":"12:00"}],"needsClarification":[]}
        """
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(invalid)) {
            XCTAssertEqual($0 as? AIWeeklyScheduleError, .invalidOutput)
        }
    }

    func testRejectsInvalidWeekdaysNamesAndTimeFormats() {
        let pairs = [
            ("09:60", "10:00"), ("9:00", "10:00"), ("24:00", "24:00"),
            ("22:00", "01:00"), ("10:00", "10:00"), ("-1:00", "10:00"),
            ("09:00", "24:01")
        ]
        for (start, end) in pairs {
            let text = """
            {"events":[{"title":"安排","weekdays":[1],"start":"\(start)","end":"\(end)"}],"needsClarification":[]}
            """
            XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(text), "\(start)—\(end)")
        }
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(validJSON.replacingOccurrences(of: "[1,3,5]", with: "[]")))
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(validJSON.replacingOccurrences(of: "开会", with: " ")))
    }

    func testClarificationPreventsPartialImport() {
        let text = validJSON.replacingOccurrences(of: "\"needsClarification\":[]", with: "\"needsClarification\":[\"运动在每周哪几天、几点结束？\"]")
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(text)) {
            XCTAssertEqual($0 as? AIWeeklyScheduleError, .clarification("运动在每周哪几天、几点结束？"))
        }
    }

    func testRejectsEmptyTruncatedAndOversizedOutput() {
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(#"{"events":[],"needsClarification":[]}"#)) {
            XCTAssertEqual($0 as? AIWeeklyScheduleError, .noEvents)
        }
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(String(validJSON.dropLast())))
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(String(repeating: "x", count: 33 * 1024))) {
            XCTAssertEqual($0 as? AIWeeklyScheduleError, .responseTooLarge)
        }
        let event = #"{"title":"安排","weekdays":[1],"start":"09:00","end":"10:00"}"#
        let tooMany = #"{"events":["# + Array(repeating: event, count: 51).joined(separator: ",") + #"],"needsClarification":[]}"#
        XCTAssertThrowsError(try DashScopeAIWeeklyScheduleService.decodeEvents(tooMany)) {
            XCTAssertEqual($0 as? AIWeeklyScheduleError, .tooManyEvents)
        }
    }

    func testRequestUsesSharedConfigurationAndSendsOnlyInput() async throws {
        WeeklyScheduleURLProtocol.handler = { [validJSON] request in
            XCTAssertEqual(request.url, DashScopeConfiguration.endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try JSONSerialization.jsonObject(with: Self.bodyData(request)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "qwen3.8-flash")
            XCTAssertEqual(body["enable_thinking"] as? Bool, false)
            XCTAssertNil(body["extra_body"])
            let messages = body["messages"] as! [[String: String]]
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[1]["role"], "user")
            XCTAssertEqual(messages[1]["content"], "每周一三五14:10—15:40开会")
            XCTAssertNil(body["events"])
            return try Self.response(request, content: validJSON)
        }
        let result = try await service().parseSchedule(apiKey: "test-key", input: "每周一三五14:10—15:40开会")
        XCTAssertEqual(result.first?.startMinute, 850)
    }

    func testRetriesMalformedJSONOnce() async throws {
        var count = 0
        WeeklyScheduleURLProtocol.handler = { [validJSON] request in
            count += 1
            return try Self.response(request, content: count == 1 ? "invalid" : validJSON)
        }
        let result = try await service().parseSchedule(apiKey: "test-key", input: "每周日程")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(count, 2)
    }

    func testDoesNotRetryAuthenticationFailureOrClarification() async {
        var count = 0
        WeeklyScheduleURLProtocol.handler = { request in
            count += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await service().parseSchedule(apiKey: "test-key", input: "周日程")
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? AIWeeklyScheduleError, .serviceStatus(401))
        }
        XCTAssertEqual(count, 1)
        count = 0
        WeeklyScheduleURLProtocol.handler = { request in
            count += 1
            return try Self.response(request, content: #"{"events":[],"needsClarification":["请提供起止时间"]}"#)
        }
        do {
            _ = try await service().parseSchedule(apiKey: "test-key", input: "周一读书")
            XCTFail("Expected clarification")
        } catch {
            XCTAssertEqual(error as? AIWeeklyScheduleError, .clarification("请提供起止时间"))
        }
        XCTAssertEqual(count, 1)
    }

    func testTimeoutAndAlreadyCancelledRequestsDoNotRetry() async {
        var count = 0
        WeeklyScheduleURLProtocol.handler = { [validJSON] request in
            count += 1
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try Self.response(request, content: validJSON)
        }
        do {
            _ = try await service(timeout: 0.03).parseSchedule(apiKey: "test-key", input: "日程")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertTrue(error as? AIWeeklyScheduleError == .timedOut || (error as? URLError)?.code == .timedOut)
        }
        XCTAssertEqual(count, 1)
        let client = service()
        let task = Task {
            try await client.parseSchedule(apiKey: "test-key", input: "日程")
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(count, 1)
    }

    private func service(timeout: TimeInterval = 5) -> DashScopeAIWeeklyScheduleService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeeklyScheduleURLProtocol.self]
        return DashScopeAIWeeklyScheduleService(session: URLSession(configuration: config), timeoutSeconds: timeout)
    }

    private static func response(_ request: URLRequest, content: String) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": "stop"]]])
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            result.append(buffer, count: read)
        }
        return result
    }
}

private final class WeeklyScheduleURLProtocol: URLProtocol {
    static var handler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?
    private var loadingTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        loadingTask = Task {
            do {
                let (response, data) = try await handler(request)
                try Task.checkCancellation()
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                if !Task.isCancelled { client?.urlProtocol(self, didFailWithError: error) }
            }
        }
    }
    override func stopLoading() { loadingTask?.cancel() }
}
