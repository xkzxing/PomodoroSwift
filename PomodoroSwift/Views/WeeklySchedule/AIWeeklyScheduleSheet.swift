import SwiftUI

struct AIWeeklyScheduleSheet: View {
    @ObservedObject var store: WeeklyScheduleStore
    @ObservedObject var settings: Settings
    @StateObject private var controller = AIWeeklyScheduleController()
    @Environment(\.dismiss) private var dismiss

    private let example = "每周一、三、五上午9点到10点读书；工作日12:00到13:00午餐；每周二、四14:10到15:40开会。"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("AI 添加日程").font(.title2.weight(.semibold))
            }
            Text("用自然语言描述固定安排，识别后自动添加为每周重复日程。")
                .font(.subheadline).foregroundStyle(.secondary)

            SecureField("模型服务密钥（与 AI 任务分类共用）", text: $settings.aiApiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(controller.isRunning)
                .accessibilityIdentifier("weeklyAIKey")
            Text("沿用通义千问服务（DashScope）的密钥。仅发送本次输入，不发送已有日程；调用可能产生服务费用。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("描述日程").font(.headline)
                Spacer()
                Button("填入示例") { controller.inputText = example }
                    .disabled(controller.isRunning)
                    .accessibilityIdentifier("weeklyAIExample")
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $controller.inputText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .disabled(controller.isRunning)
                    .accessibilityIdentifier("weeklyAIInput")
                if controller.inputText.isEmpty {
                    Text(example)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 120)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.12)))
            HStack {
                Text("请写明每周哪几天及起止时间。仅支持固定周计划。")
                Spacer()
                Text("\(controller.inputText.count)/6000")
                    .foregroundStyle(controller.inputText.count > 6000 ? .red : .secondary)
            }
            .font(.caption).foregroundStyle(.secondary)

            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(controller.statusIsError ? .red : .green)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("weeklyAIStatus")
            }
            if !controller.addedEvents.isEmpty || !controller.notices.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(controller.notices, id: \.self) { notice in
                            Label(notice, systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(controller.addedEvents) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(event.color.tint).frame(width: 7, height: 7).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).fontWeight(.medium)
                                    Text(event.weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: "、")
                                         + "  \(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
            }

            HStack(spacing: 10) {
                if controller.isRunning {
                    ProgressView().controlSize(.small)
                    Text("正在识别日程…").font(.caption).foregroundStyle(.secondary)
                    Button("取消请求") { controller.cancel() }
                }
                Spacer()
                Button("关闭") { controller.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(controller.statusIsError ? "重试并添加" : "识别并添加日程") {
                    controller.start(apiKey: settings.aiApiKey, store: store)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isRunning
                          || controller.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || controller.inputText.count > 6000
                          || settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || store.storageError != nil)
                .accessibilityIdentifier("weeklyAIAdd")
            }
            if let error = store.storageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onDisappear { controller.cancel() }
    }
}
