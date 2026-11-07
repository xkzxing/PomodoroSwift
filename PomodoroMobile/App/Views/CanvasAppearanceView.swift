import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CanvasAppearanceView: View {
    @EnvironmentObject private var style: CanvasStyle
    @EnvironmentObject private var skyLocation: MobileSkyLocation
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loading = false
    @State private var choosingFile = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ZStack {
                    CanvasBackdrop()
                    Circle().fill(.clear).frame(width: 95, height: 95).desktopGlass(in: Circle())
                    Text("12").font(.title3.weight(.medium)).foregroundStyle(style.textColor).offset(y: -28)
                }
                .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .accessibilityHidden(true)
                Picker("背景主题", selection: $style.preferences.backgroundTheme) {
                    ForEach(BackgroundTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                if style.preferences.backgroundTheme.isDynamic {
                    Picker("时段预览", selection: $style.backgroundPreview) {
                        ForEach(BackgroundTimePreview.allCases) { time in Text(time.title).tag(time) }
                    }
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从照片中选择背景", systemImage: "photo")
                    }.disabled(loading)
                    Button("从文件中选择背景", systemImage: "folder") { choosingFile = true }.disabled(loading)
                    if loading { ProgressView("正在读取照片") }
                    Toggle("使用照片背景", isOn: $style.preferences.usesPhoto)
                    Button("恢复电脑版背景") {
                        do { try style.restoreBackground() } catch { errorMessage = "恢复背景失败：\(error.localizedDescription)" }
                    }
                }
            } header: { Text("背景") } footer: {
                Text(style.preferences.backgroundTheme.isDynamic ? "实时模式随昼夜变化。选择其他时段可预览配色。" :
                    "照片仅保存在本机。关闭照片背景时显示纯黑背景。")
            }
            if !style.preferences.backgroundTheme.isDynamic && style.preferences.usesPhoto {
                Section("横向取景") {
                    Slider(value: $style.preferences.photoPosition, in: 0...1)
                        .accessibilityLabel("背景图片横向取景位置")
                }
            }
            Section {
                LabeledContent("天空依据", value: skyLocation.coordinates == nil ? "本地时间" : "已保存的位置")
                Button(skyLocation.isLocating ? "正在定位…" : "更新位置") { skyLocation.update() }
                    .disabled(skyLocation.isLocating)
                if skyLocation.coordinates != nil { Button("改用本地时间") { skyLocation.useLocalTime() } }
                if let message = skyLocation.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("湖岸与今日晴空") } footer: { Text("位置仅保存在本机，供实时湖岸和「今日」晴空使用。") }
            Section("本机布局") {
                VStack(alignment: .leading, spacing: 7) {
                    LabeledContent("表盘大小", value: "\(Int(style.preferences.clockSize)) 点")
                    Slider(value: $style.preferences.clockSize, in: 160...520, step: 10)
                        .accessibilityLabel("表盘大小")
                }
                VStack(alignment: .leading, spacing: 7) {
                    LabeledContent("表盘与面板间距", value: "\(Int(style.preferences.sectionSpacing)) 点")
                    Slider(value: $style.preferences.sectionSpacing, in: 8...72, step: 2)
                        .accessibilityLabel("表盘与面板间距")
                }
                Button("重置本机布局") { style.resetLayout() }
                Text("表盘会按手机宽度自动适配。展开待办面板后，可拖动底部把手调整高度。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("文字与玻璃") {
                if !style.preferences.backgroundTheme.isDynamic { Toggle("深色文字", isOn: $style.preferences.darkText) }
                Picker("亮暗配色", selection: $style.preferences.pairedGlassTint) {
                    Text("原着色").tag(nil as ScenePanelColor?)
                    ForEach(ScenePanelColor.allCases) { tint in Text(tint.mobileTitle).tag(Optional(tint)) }
                }
                if style.preferences.pairedGlassTint == nil {
                    ColorPicker("全局着色", selection: Binding(get: { style.glassTint }, set: { style.setGlassTint($0) }), supportsOpacity: false)
                }
                Picker("玻璃样式", selection: $style.preferences.clearGlass) {
                    Text("常规").tag(false)
                    Text("清透").tag(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("全局着色强度").font(.subheadline)
                    Slider(value: $style.preferences.glassOpacity, in: 0...1)
                        .accessibilityLabel("全局玻璃着色强度")
                }.padding(.vertical, 4)
                Toggle("触控光泽", isOn: $style.preferences.interactive)
            }
            Section {
                Text("待办配色和「今日」主题来自电脑。湖岸背景会按时段选用待办面板的亮色或暗色；这里的配色设置用于手机表盘和控制按钮。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            loading = true
            Task {
                defer { loading = false }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do { try style.setBackground(Data(contentsOf: url)) }
                catch { errorMessage = "背景文件未能读取：\(error.localizedDescription)" }
            }
        }
        .navigationTitle("背景与玻璃").navigationBarTitleDisplayMode(.inline)
        .onChange(of: style.preferences.backgroundTheme) { _, theme in
            if !theme.isDynamic { style.backgroundPreview = .live }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            loading = true
            Task {
                defer { loading = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                    try style.setBackground(data)
                } catch { errorMessage = "照片未能读取：\(error.localizedDescription)" }
            }
        }
        .alert("背景图片", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

private extension ScenePanelColor {
    var mobileTitle: String {
        switch self {
        case .red: "红色"
        case .orange: "橙色"
        case .yellow: "黄色"
        case .green: "绿色"
        case .cyan: "青色"
        case .blue: "蓝色"
        case .purple: "紫色"
        case .monochrome: "黑白"
        }
    }
}
