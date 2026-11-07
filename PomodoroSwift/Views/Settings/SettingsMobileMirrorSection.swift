import SwiftUI
import UniformTypeIdentifiers

struct SettingsMobileMirrorSection: View {
    @ObservedObject private var publisher = DesktopTaskPublisher.shared
    @State private var choosingDirectory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手机单向同步").font(.headline)
            Text("电脑发布待办面板，手机只读查看。手机不会回写电脑。")
                .font(.caption).foregroundStyle(.secondary)
            Text("修改保存后一秒写出，也可手动更新；不定时检查。")
                .font(.caption).foregroundStyle(.secondary)
            if let folder = publisher.folderName {
                Label(folder, systemImage: "folder").font(.subheadline).lineLimit(2)
            }
            Button(publisher.isConfigured ? "更换同步文件夹…" : "选择同步文件夹…") { choosingDirectory = true }
            if publisher.isConfigured {
                HStack {
                    Button("立即更新") { publisher.publish(force: true) }.disabled(publisher.isPublishing)
                    Button("停止发布") { publisher.disconnect() }
                }
                if publisher.isPublishing { ProgressView("正在更新").controlSize(.small) }
                if let date = publisher.lastPublishedAt {
                    Text("上次更新：\(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = publisher.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            Text("选择苹果云盘中的一个专用文件夹，再在手机设置中选择同一个文件夹。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { publisher.selectDirectory(url) }
        }
    }
}
