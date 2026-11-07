import Foundation
import Combine

@MainActor
final class AIWeeklyScheduleController: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var statusIsError = false
    @Published private(set) var addedEvents: [WeeklyScheduleEvent] = []
    @Published private(set) var notices: [String] = []

    private let service: AIWeeklyScheduleService
    private var requestTask: Task<Void, Never>?
    private var requestID: UUID?

    init(service: AIWeeklyScheduleService) {
        self.service = service
    }

    convenience init() {
        self.init(service: DashScopeAIWeeklyScheduleService())
    }

    func start(apiKey: String, store: WeeklyScheduleStore) {
        guard !isRunning else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { fail("请先填写与 AI 任务分类共用的模型服务密钥。"); return }
        guard !input.isEmpty else { fail("请描述每周的日程名称、日期和起止时间。"); return }
        guard input.count <= 6000 else { fail(AIWeeklyScheduleError.inputTooLong.localizedDescription); return }
        guard store.storageError == nil else { fail(WeeklyScheduleImportError.unavailable.localizedDescription); return }

        let id = UUID()
        requestID = id
        isRunning = true
        statusMessage = ""
        statusIsError = false
        addedEvents = []
        notices = []

        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let events = try await self.service.parseSchedule(apiKey: key, input: input)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                // No suspension between the cancellation guard and the atomic local write.
                let result = try store.addBatch(events)
                self.addedEvents = result.added
                self.statusMessage = result.added.isEmpty
                    ? "这些安排已存在，没有重复添加。"
                    : "已添加 \(result.added.count) 条每周日程。"
                if result.duplicateDayCount > 0 {
                    self.notices.append("已跳过 \(result.duplicateDayCount) 个重复的日期安排。")
                }
                let overlaps = result.added.filter { new in
                    store.events.contains {
                        $0.id != new.id && !$0.weekdays.isDisjoint(with: new.weekdays)
                            && $0.startMinute < new.endMinute && $0.endMinute > new.startMinute
                    }
                }.count
                if overlaps > 0 {
                    self.notices.append("\(overlaps) 条日程与其他固定安排重叠，已并排保留。")
                }
                let outsideRange = result.added.filter {
                    $0.startMinute < store.preferences.startMinute || $0.endMinute > store.preferences.endMinute
                        || !($0.weekdays.subtracting(store.preferences.weekdays)).isEmpty
                }.count
                if outsideRange > 0 {
                    self.notices.append("\(outsideRange) 条日程有日期或时段位于显示范围之外，可在日程列表查看。")
                }
                if !result.added.isEmpty { store.preferences.isVisible = true }
                self.inputText = ""
                self.finish(id)
            } catch {
                guard self.requestID == id else { return }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.fail("已取消，本次没有添加日程。")
                } else if let error = error as? URLError {
                    self.fail(error.code == .timedOut ? AIWeeklyScheduleError.timedOut.localizedDescription
                              : "无法连接模型服务，请检查网络后重试。本次没有添加日程。")
                } else if let error = error as? LocalizedError {
                    self.fail(error.errorDescription ?? "识别失败，本次没有添加日程，请重试。")
                } else {
                    self.fail("识别失败，本次没有添加日程，请重试。")
                }
                self.finish(id)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
        isRunning = false
        fail("已取消，本次没有添加日程。")
    }

    private func fail(_ message: String) {
        statusIsError = true
        statusMessage = message
    }

    private func finish(_ id: UUID) {
        guard requestID == id else { return }
        isRunning = false
        requestTask = nil
        requestID = nil
    }
}
