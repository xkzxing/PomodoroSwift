import XCTest
@testable import PomodoroSwift

@MainActor
final class AIWeeklyScheduleControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: WeeklyScheduleStore!

    override func setUp() async throws {
        suite = "AIWeeklyScheduleTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = WeeklyScheduleStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        store = nil
        defaults = nil
    }

    private func event(title: String = "读书", days: Set<ScheduleWeekday> = [.monday]) -> WeeklyScheduleEvent {
        WeeklyScheduleEvent(title: title, weekdays: days, startMinute: 550, endMinute: 610)
    }

    func testAddsBatchAndReportsOverlapsAndHiddenTimes() async throws {
        let service = ControlledWeeklyService()
        let controller = AIWeeklyScheduleController(service: service)
        controller.inputText = "每周日9:10—10:10读书，学习"
        controller.start(apiKey: " test-key ", store: store)
        await waitUntil { service.requests.count == 1 }
        XCTAssertEqual(service.requests[0].key, "test-key")
        service.complete(0, .success([event(days: [.sunday]), event(title: "学习", days: [.sunday])]))
        await waitUntil { !controller.isRunning }
        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(controller.addedEvents.count, 2)
        XCTAssertFalse(controller.statusIsError)
        XCTAssertTrue(controller.inputText.isEmpty)
        XCTAssertTrue(controller.notices.contains { $0.contains("重叠") })
        XCTAssertTrue(controller.notices.contains { $0.contains("显示范围之外") })
        XCTAssertEqual(WeeklyScheduleStore(defaults: defaults).events, store.events)
    }

    func testValidationDoesNotStartNetworkRequest() async {
        let service = ControlledWeeklyService()
        let controller = AIWeeklyScheduleController(service: service)
        controller.inputText = "日程"
        controller.start(apiKey: " ", store: store)
        XCTAssertTrue(controller.statusIsError)
        XCTAssertFalse(controller.isRunning)
        controller.inputText = String(repeating: "字", count: 6001)
        controller.start(apiKey: "test-key", store: store)
        XCTAssertTrue(controller.statusMessage.contains("6000"))
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testFailurePreservesInputAndRetrySucceeds() async {
        let service = ControlledWeeklyService()
        let controller = AIWeeklyScheduleController(service: service)
        controller.inputText = "日程描述"
        controller.start(apiKey: "test-key", store: store)
        await waitUntil { service.requests.count == 1 }
        service.complete(0, .failure(AIWeeklyScheduleError.clarification("请补充日期")))
        await waitUntil { !controller.isRunning }
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(controller.inputText, "日程描述")
        XCTAssertTrue(controller.statusIsError)
        controller.start(apiKey: "test-key", store: store)
        await waitUntil { service.requests.count == 2 }
        service.complete(1, .success([event()]))
        await waitUntil { !controller.isRunning }
        XCTAssertEqual(store.events.count, 1)
        XCTAssertFalse(controller.statusIsError)
    }

    func testCancellationIgnoresLateResultWithoutAffectingNewRequest() async {
        let service = ControlledWeeklyService()
        let controller = AIWeeklyScheduleController(service: service)
        controller.inputText = "旧请求"
        controller.start(apiKey: "test-key", store: store)
        await waitUntil { service.requests.count == 1 }
        controller.cancel()
        controller.inputText = "新请求"
        controller.start(apiKey: "test-key", store: store)
        await waitUntil { service.requests.count == 2 }
        service.complete(0, .success([event(title: "旧日程")]))
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(controller.isRunning)
        XCTAssertTrue(store.events.isEmpty)
        service.complete(1, .success([event(title: "新日程")]))
        await waitUntil { !controller.isRunning }
        XCTAssertEqual(store.events.map(\.title), ["新日程"])
        XCTAssertFalse(controller.statusIsError)
    }

    func testDoubleStartAndRepeatedImportsDoNotDuplicate() async throws {
        let service = ControlledWeeklyService()
        let controller = AIWeeklyScheduleController(service: service)
        let original = event()
        XCTAssertTrue(store.save(original))
        controller.inputText = "日程"
        controller.start(apiKey: "test-key", store: store)
        controller.start(apiKey: "test-key", store: store)
        await waitUntil { service.requests.count == 1 }
        service.complete(0, .success([event()]))
        await waitUntil { !controller.isRunning }
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(store.events, [original])
        XCTAssertTrue(controller.addedEvents.isEmpty)
        XCTAssertTrue(controller.statusMessage.contains("没有重复添加"))
    }

    func testInvalidBatchDoesNotPartiallyPersist() throws {
        let original = event(title: "原有")
        XCTAssertTrue(store.save(original))
        var invalid = event(title: "无效")
        invalid.endMinute = invalid.startMinute
        XCTAssertThrowsError(try store.addBatch([event(title: "有效"), invalid]))
        XCTAssertEqual(store.events, [original])
        XCTAssertEqual(WeeklyScheduleStore(defaults: defaults).events, [original])
    }

    func testDeduplicatesByDayWithinBatchAndAgainstExistingEvents() throws {
        let original = event()
        XCTAssertTrue(store.save(original))
        var draft = event(title: "  读书  ", days: [.monday, .tuesday])
        draft.id = original.id
        let result = try store.addBatch([draft, event(days: [.tuesday, .wednesday])])
        XCTAssertEqual(result.duplicateDayCount, 2)
        XCTAssertEqual(result.added.map(\.weekdays), [[.tuesday], [.wednesday]])
        XCTAssertEqual(store.events.first, original)
        XCTAssertTrue(result.added.allSatisfy { $0.id != original.id })
        let again = try store.addBatch([event(days: [.monday, .tuesday, .wednesday])])
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(store.events.count, 3)
    }

    func testSameTimeWithDifferentTitleIsKeptAndCorruptStorageBlocksImport() throws {
        let result = try store.addBatch([event(), event(title: "开会")])
        XCTAssertEqual(result.added.count, 2)
        let corrupt = Data("broken".utf8)
        defaults.set(corrupt, forKey: WeeklyScheduleStore.eventsKey)
        let brokenStore = WeeklyScheduleStore(defaults: defaults)
        XCTAssertThrowsError(try brokenStore.addBatch([event()]))
        XCTAssertEqual(defaults.data(forKey: WeeklyScheduleStore.eventsKey), corrupt)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(predicate(), "Operation did not complete")
    }
}

@MainActor
private final class ControlledWeeklyService: AIWeeklyScheduleService {
    struct Request {
        let key: String
        let continuation: CheckedContinuation<[WeeklyScheduleEvent], Error>
    }
    private(set) var requests: [Request] = []

    func parseSchedule(apiKey: String, input: String) async throws -> [WeeklyScheduleEvent] {
        try await withCheckedThrowingContinuation {
            requests.append(Request(key: apiKey, continuation: $0))
        }
    }

    func complete(_ index: Int, _ result: Result<[WeeklyScheduleEvent], Error>) {
        requests[index].continuation.resume(with: result)
    }
}
