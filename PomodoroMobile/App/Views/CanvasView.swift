import SwiftUI

private enum CanvasSheet: String, Identifiable {
    case settings, mirror, sound
    var id: String { rawValue }
}

struct CanvasView: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var style: CanvasStyle
    @EnvironmentObject private var mirror: MobileTaskMirror
    @EnvironmentObject private var skyLocation: MobileSkyLocation
    @Environment(\.scenePhase) private var appPhase
    @State private var sheet: CanvasSheet?
    @State private var resetConfirmation = false
    @State private var pendingMode: FocusMode?

    private var hasProgress: Bool { store.timer.status == .running || store.timer.status == .paused }
    private var canSetDuration: Bool { store.timer.status == .ready || store.timer.status == .paused }
    private var tracksLiveSky: Bool {
        (style.preferences.backgroundTheme.isDynamic && style.backgroundPreview == .live) || mirror.snapshot?.today?.theme == .sky
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if geometry.size.width > geometry.size.height {
                    ScrollView {
                        HStack(alignment: .top, spacing: 28) {
                            clockArea(diameter: min(style.preferences.clockSize, geometry.size.width * 0.3, 250)).frame(maxWidth: .infinity)
                            panels.frame(maxWidth: .infinity)
                        }.padding(.horizontal, 24).padding(.vertical, 12)
                    }.scrollDismissesKeyboard(.interactively)
                } else {
                    ScrollView {
                        VStack(spacing: style.preferences.sectionSpacing) {
                            clockArea(diameter: min(style.preferences.clockSize, geometry.size.width - 64))
                                .padding(.top, 6)
                            panels
                        }.padding(.horizontal, 20).padding(.bottom, 12)
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 8) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.timer.mode == .focus && store.timer.status != .running && store.timer.status != .completed { durationRuler }
        }
        .background { CanvasBackdrop(tracksFrame: true, capturesForGemstone: store.settings.dial.resolved == .gemstone) }
        .preferredColorScheme(style.usesDarkText ? .light : .dark)
        .task(id: tracksLiveSky && appPhase == .active) {
            guard tracksLiveSky && appPhase == .active else { return }
            while !Task.isCancelled {
                style.updateSky(coordinates: skyLocation.coordinates)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onChange(of: skyLocation.coordinates) { _, coordinates in style.updateSky(coordinates: coordinates) }
        .sheet(item: $sheet) { item in
            switch item {
            case .settings: SettingsView()
            case .mirror:
                NavigationStack {
                    MobileMirrorSettingsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
                }
            case .sound: SoundSelectionView().presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog("重新开始这一段计时？", isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button("重新开始", role: .destructive) { store.resetTimer() }
        }
        .confirmationDialog("切换模式会重新开始计时", isPresented: Binding(
            get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } }
        ), titleVisibility: .visible) {
            if let mode = pendingMode {
                Button("切换到\(mode.title)", role: .destructive) { store.selectMode(mode); pendingMode = nil }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CanvasIconButton(symbol: "sidebar.left", title: "设置") { sheet = .settings }
                .accessibilityIdentifier("open-settings")
            Spacer()
            CanvasIconButton(symbol: store.settings.sound == .none ? "speaker.slash" : "waveform", title: "环境声") { sheet = .sound }
            CanvasIconButton(symbol: "arrow.down.circle", title: "电脑待办同步") { sheet = .mirror }
        }.padding(.horizontal, 20).padding(.top, 4)
    }

    private func clockArea(diameter: CGFloat) -> some View {
        VStack(spacing: 15) {
            switch store.settings.dial.resolved {
            case .digital:
                MobileDigitalDial(time: store.timer.displayTime).frame(width: max(160, diameter), height: max(110, diameter * 0.48))
            case .gemstone:
                MobileGemstoneDial(timer: store.timer, diameter: max(160, diameter))
            case .swiss, .ring:
                DesktopSwissDial(timer: store.timer).frame(width: max(160, diameter), height: max(160, diameter))
            }
            if store.timer.status == .completed && store.timer.mode == .focus {
                HStack(spacing: 10) {
                    completionButton("停止") { store.complete(.stop) }
                    completionButton("短休息") { store.complete(.shortBreak) }
                    completionButton("长休息") { store.complete(.longBreak) }
                }
            } else if store.timer.status == .completed {
                completionButton("开始专注") { store.complete(.focus) }
            } else {
                HStack(spacing: 24) {
                    CanvasIconButton(symbol: "arrow.counterclockwise", title: "重置计时") { resetConfirmation = true }
                        .opacity(hasProgress ? 1 : 0).disabled(!hasProgress).accessibilityHidden(!hasProgress)
                    CanvasIconButton(symbol: store.timer.status == .running ? "pause.fill" : "play.fill",
                                     title: controlTitle, size: 56) { store.toggleTimer() }
                        .accessibilityIdentifier("timer-toggle")
                    Menu {
                        ForEach(FocusMode.allCases) { mode in
                            Button(mode.title, systemImage: mode.symbol) {
                                if mode != store.timer.mode {
                                    if hasProgress { pendingMode = mode } else { store.selectMode(mode) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(style.textColor).frame(width: 44, height: 44).desktopGlass(in: Circle())
                    }.accessibilityLabel("选择专注或休息")
                }
                if store.timer.mode != .focus && hasProgress {
                    completionButton("结束休息") { store.stopBreak() }
                }
            }
            HStack(spacing: 7) {
                Text(store.timer.mode.title)
                Text("·")
                Text(store.timer.displayTime).monospacedDigit()
                if store.timer.status == .paused { Text("已暂停") }
                if store.timer.status == .completed { Text("已完成") }
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(style.textColor.opacity(0.8))
            .padding(.horizontal, 13).padding(.vertical, 7).desktopGlass(in: Capsule(), opacity: 0.05)
        }.frame(maxWidth: .infinity)
    }

    private func completionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .medium))
                .foregroundStyle(style.textColor).padding(.horizontal, 16).frame(minHeight: 46)
                .desktopGlass(in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private var controlTitle: String {
        switch store.timer.status {
        case .running: return "暂停"
        case .paused: return "继续"
        case .ready: return "开始\(store.timer.mode.title)"
        case .completed: return "开始\(store.archive.nextMode.title)"
        }
    }

    private var panels: some View {
        VStack(spacing: 10) {
            if let snapshot = mirror.snapshot {
                if snapshot.panels.isEmpty && snapshot.today == nil {
                    Text("电脑暂无待办面板")
                        .font(.subheadline).foregroundStyle(style.textColor.opacity(0.7))
                        .frame(maxWidth: .infinity).padding(20).desktopGlass(in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 0) {
                        if let appearance = snapshot.today {
                            CanvasTodayPanel(appearance: appearance, entries: snapshot.todayEntries, last: snapshot.panels.isEmpty)
                        }
                        ForEach(Array(snapshot.panels.enumerated()), id: \.element.id) { index, panel in
                            CanvasTaskPanel(panel: panel, index: index, first: index == 0 && snapshot.today == nil,
                                            last: index == snapshot.panels.count - 1)
                        }
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "lock")
                    Text("电脑待办 · 只读")
                    Spacer()
                    if mirror.isRefreshing { ProgressView().controlSize(.mini) }
                    else if mirror.isConfigured {
                        Button { mirror.refresh() } label: {
                            Label("立即读取", systemImage: "arrow.down.circle").frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityIdentifier("manual-refresh")
                    }
                }.font(.system(size: 11)).foregroundStyle(style.textColor.opacity(0.7))
                if let error = mirror.errorMessage {
                    Button { sheet = .mirror } label: {
                        Text(error).font(.caption).multilineTextAlignment(.leading)
                            .foregroundStyle(style.textColor.opacity(0.8)).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .desktopGlass(in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 14) {
                    Label("从电脑读取待办", systemImage: "desktopcomputer").font(.headline)
                    Text("在电脑上编辑，手机只读查看。\n请选择与电脑版相同的同步文件夹。")
                        .font(.subheadline).multilineTextAlignment(.center).lineSpacing(4)
                    Button("设置单向同步") { sheet = .mirror }
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 20).frame(minHeight: 44)
                        .desktopGlass(in: Capsule())
                }
                .foregroundStyle(style.textColor.opacity(0.85)).frame(maxWidth: .infinity).padding(24)
                .desktopGlass(in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var durationRuler: some View {
        MobileTimeRuler(selection: Binding(get: {
            switch store.timer.mode {
            case .focus: return store.settings.focusMinutes
            case .shortBreak: return store.settings.shortBreakMinutes
            case .longBreak: return store.settings.longBreakMinutes
            }
        }, set: { minutes in
            guard canSetDuration else { return }
            var settings = store.settings
            switch store.timer.mode {
            case .focus: settings.focusMinutes = minutes
            case .shortBreak: settings.shortBreakMinutes = minutes
            case .longBreak: settings.longBreakMinutes = minutes
            }
            store.updateSettings(settings)
        }), mode: store.timer.mode, enabled: canSetDuration)
        .frame(height: 78).padding(.bottom, 4)
    }
}

struct MobileTimeRuler: View {
    @Binding var selection: Int
    let mode: FocusMode
    let enabled: Bool
    @State private var position: Int?
    private var values: [Int] {
        switch mode {
        case .focus: return Array(stride(from: 5, through: 120, by: 5))
        case .shortBreak: return Array(1...30)
        case .longBreak: return Array(stride(from: 5, through: 60, by: 5))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 3) {
                Circle().fill(.white).frame(width: 4, height: 4).shadow(color: .black.opacity(0.3), radius: 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(values, id: \.self) { minute in
                            Button { withAnimation(.snappy) { position = minute } } label: {
                                Text("\(minute)")
                                    .font(.system(size: selection == minute ? 28 : 19, weight: selection == minute ? .semibold : .regular))
                                    .foregroundStyle(.white.opacity(selection == minute ? 1 : 0.55))
                                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                    .frame(width: 55, height: 41)
                            }.buttonStyle(.plain).id(minute).accessibilityLabel("\(minute) 分钟")
                                .accessibilityAddTraits(selection == minute ? .isSelected : [])
                        }
                    }.scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, (geometry.size.width - 55) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $position, anchor: .center)
                .scrollDisabled(!enabled)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                             .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                Text("分钟").font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).shadow(color: .black, radius: 3)
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
        .onAppear { position = selection }
        .onChange(of: mode) { _, _ in position = selection }
        .onChange(of: position) { _, value in if enabled, let value, values.contains(value) { selection = value } }
        .onChange(of: selection) { _, value in if position != value { position = value } }
        .accessibilityIdentifier("duration-ruler")
    }
}
