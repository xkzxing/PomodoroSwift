import SwiftUI
import UniformTypeIdentifiers

struct MobileMirrorSettingsView: View {
    @EnvironmentObject private var mirror: MobileTaskMirror
    @State private var choosingDirectory = false

    var body: some View {
        Form {
            Section {
                Label("电脑发布 → 手机只读", systemImage: "arrow.right")
                Text("待办内容、顺序、置顶、配色和「今日」均来自电脑。手机只读查看。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("同步文件夹") {
                if let folder = mirror.folderName { Label(folder, systemImage: "folder") }
                Button(mirror.isConfigured ? "更换同步文件夹" : "选择同步文件夹") { choosingDirectory = true }
                if mirror.isConfigured {
                    Button("立即读取") { mirror.refresh() }.disabled(mirror.isRefreshing)
                    Button("停止读取") { mirror.disconnect() }
                }
            }
            Section("读取状态") {
                if mirror.isRefreshing { ProgressView("正在读取电脑结果") }
                if let snapshot = mirror.snapshot {
                    LabeledContent("待办面板", value: "\(snapshot.panels.count) 个")
                    LabeledContent("待办事项", value: "\(snapshot.panels.reduce(0) { $0 + $1.items.count }) 项")
                    if snapshot.today != nil { LabeledContent("今日", value: "\(snapshot.todayEntries.count) 项") }
                    else { Text("若要查看「今日」，请更新电脑版并发布一次。")
                        .font(.footnote).foregroundStyle(.secondary) }
                    LabeledContent("电脑更新", value: snapshot.publishedAt.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute()))
                } else { Text("尚未读取到电脑结果").foregroundStyle(.secondary) }
                if let date = mirror.lastReadAt {
                    LabeledContent("手机读取", value: date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).hour().minute().second()))
                }
                if let message = mirror.statusMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let error = mirror.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Text("先在新版电脑版设置的“手机单向同步”中选择苹果云盘里的一个文件夹，再在这里选择同一个文件夹。")
                Text("只在点击“立即读取”时更新；打开或返回应用不会自动读取。离线时显示上次成功结果。云盘传输可能有延迟。")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("电脑待办同步").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { mirror.selectDirectory(url) }
        }
    }
}
