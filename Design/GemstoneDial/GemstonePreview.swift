import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum BackgroundCollection: String, CaseIterable {
    case photographs = "实拍照片", diagnostics = "诊断图案"
}

private struct PreviewRoot: View {
    @State private var study = false
    @State private var tilt = false
    @State private var dark = false
    @State private var diameter: CGFloat = 440
    @State private var elapsed: Double = 250
    @State private var collection = BackgroundCollection.photographs
    @State private var backgroundID = "photo-office"
    @State private var imported: [PreviewBackdrops.Backdrop] = []
    @State private var importError: String?
    @State private var offset: CGFloat = 0
    @State private var position: CGSize = .zero
    @State private var running = false
    @State private var runStarted = Date.now
    @GestureState private var dragOffset: CGSize = .zero

    private var backdrops: [PreviewBackdrops.Backdrop] {
        let photos=PreviewBackdrops.photographs+imported
        return collection == .photographs && !photos.isEmpty ? photos : PreviewBackdrops.diagnostics
    }

    var body: some View {
        let choices=backdrops
        let index=choices.firstIndex{$0.id==backgroundID} ?? 0
        let backdrop=choices[index]
        ZStack {
            Image(nsImage: backdrop.image).resizable().scaledToFill()
                .frame(width: 660, height: 660)
                .accessibilityHidden(true)
            TimelineView(.animation(minimumInterval: 0.25, paused: !running)) { context in
                let current = elapsed + (running ? max(0, context.date.timeIntervalSince(runStarted)) : 0)
                Gemstone3DView(scene: study ? .study : .dial, background: backdrop.image,
                    viewportSize: CGSize(width: 660, height: 660),
                    handDegrees: SwissClockProgress(totalDuration: 1500, elapsedTime: current).redHandDegrees,
                    cameraTilt: tilt ? SIMD2<Float>(0.80, -1.10) : .zero)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($dragOffset) { value, state, transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                    state = value.translation
                }
                .onEnded { value in
                    position.width += value.translation.width
                    position.height += value.translation.height
                }
            )
            .offset(x: offset + position.width + dragOffset.width, y: -50 + position.height + dragOffset.height)
            .help("拖动表盘，可观察反光和折射随位置变化。")

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button(study ? "表盘" : "样件") { study.toggle() }
                        Button("角度") { tilt.toggle() }
                        Button("外观") { dark.toggle() }
                        Button("尺寸") { diameter = diameter == 440 ? 160 : diameter == 160 ? 300 : diameter == 300 ? 520 : 440 }
                        Button("针位") { elapsed = elapsed == 250 ? 600 : elapsed == 600 ? 1500 : elapsed == 1500 ? 0 : 250 }
                        Button("位置") { offset = offset == 0 ? 60 : 0 }
                        Button("居中") { offset = 0; position = .zero }
                    }
                    HStack(spacing: 6) {
                        Picker("背景类型",selection:$collection) {
                            ForEach(BackgroundCollection.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width:108)
                        Button { changeBackground(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("上一个背景")
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        Picker("预览背景", selection: $backgroundID) {
                            ForEach(choices) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 170)
                        Button { changeBackground(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("下一个背景")
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        Text("\(index + 1) / \(choices.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44)
                        Button("打开照片…",action:openPhotographs)
                    }
                    HStack(spacing: 10) {
                        Text(backdrop.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let source=backdrop.source { Link("照片来源",destination:source).font(.caption) }
                        Button(running ? "暂停计时" : "试运行计时") {
                            if running { elapsed += Date.now.timeIntervalSince(runStarted); running = false }
                            else { runStarted = .now; running = true }
                        }
                        .controlSize(.small)
                    }
                }
                .buttonStyle(.bordered)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(14)
        }
        .frame(width: 660, height: 660)
        .coordinateSpace(name: "gemstoneBackdrop")
        .clipped()
        .preferredColorScheme(dark ? .dark : .light)
        .onChange(of:collection) { _,_ in
            if !backdrops.contains(where:{$0.id==backgroundID}) { backgroundID=backdrops[0].id }
        }
        .alert("无法打开照片",isPresented:Binding(get:{importError != nil},set:{if !$0 { importError=nil }})) {
            Button("好",role:.cancel) { importError=nil }
        } message: { Text(importError ?? "") }
    }

    private func changeBackground(_ step: Int) {
        let choices=backdrops
        let current=choices.firstIndex{$0.id==backgroundID} ?? 0
        backgroundID=choices[(current+step+choices.count)%choices.count].id
    }

    private func openPhotographs() {
        let panel=NSOpenPanel()
        panel.title="选择测试照片"
        panel.allowedContentTypes=[.image]
        panel.allowsMultipleSelection=true
        panel.canChooseDirectories=false
        guard panel.runModal() == .OK else { return }
        var additions: [PreviewBackdrops.Backdrop]=[], failures: [String]=[]
        for url in panel.urls {
            guard let image=PreviewBackdrops.loadPhotograph(url) else { failures.append(url.lastPathComponent); continue }
            additions.append(.init(id:UUID().uuidString,name:url.deletingPathExtension().lastPathComponent,
                detail:"本地照片 · \(Int(image.size.width)) × \(Int(image.size.height))",image:image))
        }
        imported.append(contentsOf:additions)
        if let first=additions.first { collection = .photographs; backgroundID=first.id }
        if !failures.isEmpty { importError="这些文件无法解码："+failures.joined(separator:"、") }
    }
}

@main struct GemstonePreviewApp: App {
    var body: some Scene {
        WindowGroup("鎏金彩晶实拍预览") { PreviewRoot() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 660, height: 660)
    }
}
