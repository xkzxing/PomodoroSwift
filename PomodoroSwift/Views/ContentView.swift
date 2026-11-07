//
//  ContentView.swift
//  PomodoroSwift
//

import SwiftUI
import UserNotifications
import Combine
import AppKit

struct ContentView: View {
    @StateObject private var settings: Settings
    @StateObject private var todoPanelStores: ToDoPanelStores
    @StateObject private var timer: PomodoroTimer
    @StateObject private var noiseManager = WhiteNoiseManager()
    @StateObject private var weeklySchedule = WeeklyScheduleStore()
    @State private var showSidebar = false
    @State private var isSidebarToggleHovered = false
    @State private var isSidebarTogglePressed = false
    @State private var timerPanelOffset: CGSize = .zero
    @State private var gemstoneBackdropImage: NSImage?
    @State private var sceneBackdropImage: NSImage?
    @State private var sceneViewport: CGSize = .zero
    @State private var skyDate = Date()
    @State private var backgroundPreview = BackgroundTimePreview.live
    @State private var backgroundPreviewMinute = Double(BackgroundTimePreview.defaultCustomMinute)
    @State private var lakeDay = LakeDaySchedule(at: .now)
    @AppStorage("todayPanelTheme") private var todayPanelTheme = TodayPanelView.Theme.custom
    @AppStorage("timerPanelColors") private var timerPanelColors = ScenePanelColors.chromeDefault()
    @ObservedObject private var skyLocation = TodaySkyLocation.shared
    @State private var timerPanelLiveOffset: CGSize = .zero
    @State private var didLoadTimerPanelOffset = false
    @State private var todoPanelGroupLiveOffset: CGSize = .zero
    @State private var todoPanelGroupLiveWidthDelta: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var windowPhase
    
    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        _todoPanelStores = StateObject(wrappedValue: ToDoPanelStores(panels: settings.todoPanels))
        _timer = StateObject(wrappedValue: PomodoroTimer(
            workMinutes: settings.selectedTime,
            breakMinutes: settings.breakTime,
            longBreakMinutes: settings.longBreakTime
        ))
    }
    
    var body: some View {
        let sky = settings.backgroundTheme.isDynamic
            ? backgroundPreview.sky(at: skyDate, coordinates: skyLocation.coordinates, customMinute: Int(backgroundPreviewMinute))
            : nil
        let phase = sky.map(ScenePanelPhase.init(sky:)) ?? (settings.sidebarDarkMode ? .dark : .light)
        let timerPalette = timerPanelColors.palette(for: phase)
        let settingsPalette = settings.settingsPanelColors.palette(for: phase)
        ZStack(alignment: .leading) {
            // Main Content
            ZStack {
                // Content
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        // Main Timer & Controls
                        // strictly constrained to the top "Safe Zone" to prevent overlap
                        let safeAreaHeight = max(geometry.size.height - 160, 150)
                        let timerPanelBasePosition = CGPoint(
                            x: geometry.size.width / 2,
                            y: safeAreaHeight / 2
                        )
                        let currentTimerBaseOffset = clampedTimerPanelOffset(
                            timerPanelOffset,
                            in: geometry.size,
                            safeAreaHeight: safeAreaHeight
                        )
                        
                        VStack(spacing: 0) {
                            // Break Label
                            if timer.currentMode == .shortBreak || timer.currentMode == .longBreak {
                                Text("Break")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(timerPalette.ink.opacity(0.82))
                                    .padding(.bottom, 4)
                            }
                            
                            timerDisplay(in: geometry.size, safeAreaHeight: safeAreaHeight, palette: timerPalette)
                            .contentShape(Rectangle())
                            .gesture(
                                timerPanelDragGesture(
                                    currentTimerBaseOffset: currentTimerBaseOffset,
                                    containerSize: geometry.size,
                                    safeAreaHeight: safeAreaHeight
                                )
                            )
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.openHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                            
                            // Control Buttons
                            if timer.isCompleted && timer.currentMode == .work {
                                // Work completed → 3 options
                                HStack(spacing: 12) {
                                    glassControlButton("Stop", palette: timerPalette) {
                                        timer.resetToWork()
                                    }
                                    glassControlButton("Short Break", palette: timerPalette) {
                                        timer.startBreak(long: false)
                                    }
                                    glassControlButton("Long Break", palette: timerPalette) {
                                        timer.startBreak(long: true)
                                    }
                                }
                                .padding(.top, 20)
                            } else if timer.isCompleted {
                                // Break completed → start focus
                                glassControlButton("Start Focus Session", palette: timerPalette) {
                                    timer.startNextMode()
                                }
                                .padding(.top, 20)
                            } else if timer.isRunning && (timer.currentMode == .shortBreak || timer.currentMode == .longBreak) {
                                // Break running → stop break
                                glassControlButton("Stop Break", palette: timerPalette) {
                                    timer.resetToWork()
                                }
                                .padding(.top, 20)
                            } else {
                                startPauseControl(palette: timerPalette)
                                    .padding(.top, 20)
                            }
                        }
                        .frame(width: min(geometry.size.width - 24, 900))
                        .position(
                            x: timerPanelBasePosition.x + currentTimerBaseOffset.width + timerPanelLiveOffset.width,
                            y: timerPanelBasePosition.y + currentTimerBaseOffset.height + timerPanelLiveOffset.height
                        )
                        .onAppear {
                            loadTimerPanelOffsetIfNeeded()
                        }
                        
                        // Time Selector (Pinned to Window Bottom)
                        if !timer.isRunning && !timer.isCompleted && timer.currentMode == .work {
                            TimeSelector(selectedTime: $settings.selectedTime, scrollEnabled: !showSidebar)
                                .onChange(of: settings.selectedTime) { oldValue, newValue in
                                    timer.updateTime(
                                        workMinutes: newValue,
                                        breakMinutes: settings.breakTime,
                                        longBreakMinutes: settings.longBreakTime
                                    )
                                }
                                .frame(width: geometry.size.width)
                                .position(x: geometry.size.width / 2, y: geometry.size.height - 60)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .allowsHitTesting(true)
                        }

                        // To-Do Panels (single top-to-bottom stack)
                        todoPanelsLayer(geometry: geometry, phase: phase)

                        if weeklySchedule.preferences.isVisible {
                            WeeklySchedulePanel(
                                store: weeklySchedule,
                                containerSize: geometry.size
                            )
                            .environmentObject(settings)
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: timer.isRunning)
                    .animation(.easeInOut(duration: 0.5), value: timer.isCompleted)
                }
            }
            .frame(minWidth: 400, minHeight: 400)
            .coordinateSpace(name: "gemstoneBackdrop")
            .background { mainBackground(sky: sky) }
            .clipped()
            .ignoresSafeArea()
            .background(WindowDragger()) 
            .zIndex(0)
            
            // Overlay Backdrop (tap to close)
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSidebar = false
                    }
                }
                .opacity(showSidebar ? 1 : 0)
                .allowsHitTesting(showSidebar)
                .zIndex(10)
            
            // Custom Glass Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Sidebar Header
                HStack {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(settingsPalette.ink)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showSidebar = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(settingsPalette.ink.opacity(0.6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Settings Content
                ScrollView {
                    SettingsView(settings: settings, weeklySchedule: weeklySchedule,
                                 backgroundPreview: $backgroundPreview, backgroundPreviewMinute: $backgroundPreviewMinute,
                                 hasSkyLocation: skyLocation.coordinates != nil)
                        .padding(20)
                }
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity)
            .scenePanelSurface(RoundedRectangle(cornerRadius: 16), palette: settingsPalette)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 5, y: 0)
            .offset(x: showSidebar ? 0 : -400)
            .zIndex(11)
            
            // Sidebar Toggle Button
            VStack {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSidebar = true
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(settingsPalette.ink)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .scenePanelSurface(Circle(), palette: settingsPalette)
                .scaleEffect(isSidebarTogglePressed ? 0.95 : (isSidebarToggleHovered ? 1.05 : 1.0))
                .opacity(isSidebarTogglePressed ? 0.9 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSidebarToggleHovered)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSidebarTogglePressed)
                .onHover { hovering in
                    isSidebarToggleHovered = hovering
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            isSidebarTogglePressed = true
                        }
                        .onEnded { _ in
                            isSidebarTogglePressed = false
                        }
                )
                .padding(.leading, 16)
                .padding(.top, 16)
                
                Spacer()
            }
            .opacity(showSidebar ? 0 : 1)
            .allowsHitTesting(!showSidebar)
            .zIndex(1)
        }
        .environment(\.scenePanelPhase, phase)
        .environment(\.panelGlassStyle, settings.panelGlassStyle)
        .preferredColorScheme(settings.sidebarDarkMode ? .dark : .light)
        .environment(\.colorScheme, settings.sidebarDarkMode ? .dark : .light)
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: settings.backgroundImageData, initial: true) { _, data in
            gemstoneBackdropImage = data.flatMap(NSImage.init(data:))
        }
        .onChange(of: todayPanelTheme, initial: true) { previous, selected in
            if selected == .sky { refreshSky() }
            updateSkyLocation(askForAuthorization: previous != selected && selected == .sky)
        }
        .onChange(of: settings.backgroundTheme) { _, theme in
            sceneBackdropImage = nil
            if !theme.isDynamic {
                backgroundPreview = .live
            } else {
                refreshSky()
            }
            updateSkyLocation()
        }
        .onChange(of: backgroundPreview) {
            if backgroundPreview == .live { refreshSky() }
        }
        .onChange(of: skyLocation.coordinates) {
            if skyRefreshInterval != nil { refreshSky() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            skyLocation.resumePendingRequest()
            if skyRefreshInterval != nil { refreshSky() }
        }
        .onChange(of: windowPhase) {
            if windowPhase == .active, skyRefreshInterval != nil { refreshSky() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            if skyRefreshInterval != nil { refreshSky() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            if skyRefreshInterval != nil { refreshSky() }
        }
        .task(id: skyRefreshInterval) {
            guard let interval = skyRefreshInterval else { return }
            while !Task.isCancelled {
                let now = Date.now
                refreshSky(at: now)
                let localTime = now.timeIntervalSince1970 + TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: now))
                let elapsed = localTime.truncatingRemainder(dividingBy: interval)
                do {
                    try await Task.sleep(for: .seconds(interval - elapsed))
                } catch {
                    return
                }
            }
        }
        .onAppear {
            DesktopTaskPublisher.shared.start(settings: settings)
            applyAppAppearance()
            requestNotificationPermission()
            // Sync initial noise settings
            noiseManager.setVolume(settings.whiteNoiseVolume)
            if let type = NoiseType(rawValue: settings.whiteNoiseType) {
                noiseManager.setNoiseType(type)
            }
            syncCampfireParams()
            updateWhiteNoisePlayback()
        }
        .onChange(of: settings.whiteNoiseVolume) { _, newValue in
            noiseManager.setVolume(newValue)
        }
        .onChange(of: settings.whiteNoiseType) { _, newValue in
            if let type = NoiseType(rawValue: newValue) {
                noiseManager.setNoiseType(type)
            }
        }
        .onChange(of: settings.whiteNoiseEnabled) { _, _ in
            updateWhiteNoisePlayback()
        }
        .onChange(of: settings.whiteNoiseOnlyWhenTimerRunning) { _, _ in
            updateWhiteNoisePlayback()
        }
        .onChange(of: timer.isRunning) { _, _ in
            updateWhiteNoisePlayback()
        }
        .onChange(of: settings.breakTime) { _, newValue in
            timer.updateTime(
                workMinutes: settings.selectedTime,
                breakMinutes: newValue,
                longBreakMinutes: settings.longBreakTime
            )
        }
        .onChange(of: settings.longBreakTime) { _, newValue in
            timer.updateTime(
                workMinutes: settings.selectedTime,
                breakMinutes: settings.breakTime,
                longBreakMinutes: newValue
            )
        }
        .onReceive(campfireParamUpdatePublisher) { _ in
            syncCampfireParams()
        }
        .onChange(of: settings.sidebarDarkMode) { _, _ in
            applyAppAppearance()
        }
    }

    private var skyRefreshInterval: TimeInterval? {
        if settings.backgroundTheme.isDynamic && backgroundPreview == .live { return 60 }
        return todayPanelTheme == .sky ? 30 * 60 : nil
    }

    private func refreshSky(at now: Date = .now) {
        let calendar = LakeDaySchedule.localCalendar
        if !lakeDay.covers(now, calendar: calendar) {
            lakeDay = LakeDaySchedule(at: now, calendar: calendar)
        }
        skyDate = now
    }

    private func updateSkyLocation(askForAuthorization: Bool = false) {
        let todayUsesSky = todayPanelTheme == .sky
        skyLocation.setEnabled(todayUsesSky || settings.backgroundTheme.isDynamic,
                               askForAuthorization: askForAuthorization, permitsAuthorization: todayUsesSky)
    }

    @ViewBuilder
    private func mainBackground(sky: TodaySkyAstronomy.Sky?) -> some View {
        if let sky {
            let live = backgroundPreview == .live
            let date = backgroundPreview.date(at: skyDate, customMinute: Int(backgroundPreviewMinute))
            let theme = settings.backgroundTheme
            let schedule = theme == .lakeside ? (live ? lakeDay : Self.demoLakeDay) : nil
            let frame = DynamicBackgroundView.Frame(theme: theme, sky: sky, date: date, schedule: schedule)
            let snapshot = sceneSnapshot(for: frame)
            DynamicBackgroundView(frame: frame, advancesMotion: live && !reduceMotion && windowPhase == .active)
                .equatable()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { sceneViewport = $0 }
                .task(id: snapshot) {
                    guard let snapshot else {
                        sceneBackdropImage = nil
                        return
                    }
                    // Only capture the minute frame, after preview scrubbing or resizing settles.
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    let scene = DynamicBackgroundView(frame: snapshot.frame, advancesMotion: false)
                    let renderer = ImageRenderer(content: scene.frame(width: snapshot.size.width, height: snapshot.size.height))
                    sceneBackdropImage = renderer.nsImage
                }
        } else {
            BackgroundView(imageData: settings.backgroundImageData)
        }
    }

    private static let demoLakeDay = LakeDaySchedule(at: BackgroundTimePreview.demoDay,
                                                      calendar: BackgroundTimePreview.demoCalendar, demo: true)

    private struct SceneSnapshot: Equatable {
        let frame: DynamicBackgroundView.Frame
        let size: CGSize
    }

    private func sceneSnapshot(for frame: DynamicBackgroundView.Frame) -> SceneSnapshot? {
        guard settings.timerDisplayStyle == .gemstone, sceneViewport.width > 0, sceneViewport.height > 0 else { return nil }
        let scale = min(1, 1024 / max(sceneViewport.width, sceneViewport.height))
        let size = CGSize(width: (sceneViewport.width * scale).rounded(), height: (sceneViewport.height * scale).rounded())
        return SceneSnapshot(frame: frame, size: size)
    }

    @ViewBuilder
    private func timerDisplay(in containerSize: CGSize, safeAreaHeight: CGFloat, palette: ScenePanelPalette) -> some View {
        let glass = settings.panelGlassStyle.tinted(palette.color)
        if settings.timerDisplayStyle.isAnalog {
            let diameter = swissClockDiameter(in: containerSize, safeAreaHeight: safeAreaHeight)
            let interval = settings.timerDisplayStyle == .gemstone
                ? GemstoneClockCadence.interval(duration: TimeInterval(timer.totalDuration), diameter: diameter, displayScale: displayScale)
                : 1.0 / 30
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : interval, paused: !timer.isRunning)) { context in
                let progress = SwissClockProgress(
                    totalDuration: timer.totalDuration,
                    elapsedTime: timer.elapsedTime(at: context.date)
                )
                if settings.timerDisplayStyle == .gemstone {
                    GemstoneClockView(
                        progress: progress,
                        glassStyle: glass,
                        backdropImage: settings.backgroundTheme.isDynamic ? sceneBackdropImage : gemstoneBackdropImage,
                        backdropSize: containerSize
                    )
                } else {
                    SwissClockView(
                        progress: progress,
                        palette: palette
                    )
                }
            }
            .frame(
                width: diameter,
                height: diameter
            )
            .environment(\.colorScheme, palette.colorScheme)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(settings.timerDisplayStyle == .gemstone ? "鎏金彩晶倒计时表盘" : "Swiss countdown clock")
            .accessibilityValue("\(timer.formattedTime) remaining")
            .help(settings.timerDisplayStyle == .gemstone
                  ? "剩余时间：\(timer.formattedTime)\n指针在整段倒计时内转一圈。"
                  : "Remaining: \(timer.formattedTime)\nRed hand: one full session.")
        } else {
            TimerView(
                time: timer.formattedTime,
                nsFont: settings.selectedNSFont,
                glassStyle: glass,
                sceneInk: settings.backgroundTheme.isDynamic ? palette.ink : nil
            )
            .environment(\.colorScheme, palette.colorScheme)
        }
    }

    private var swissClockControlsHeight: CGFloat {
        88 + (timer.currentMode == .work ? 0 : 28)
    }

    @ViewBuilder
    private func startPauseControl(palette: ScenePanelPalette) -> some View {
        let title = timer.isRunning ? "Pause" : "Start"
        if settings.timerDisplayStyle.isAnalog {
            Button(action: toggleTimer) {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
                    .scenePanelSurface(Circle(), palette: palette)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .help(title)
        } else {
            glassControlButton(title, palette: palette, action: toggleTimer)
        }
    }

    private func toggleTimer() {
        if timer.isRunning {
            timer.pause()
        } else {
            timer.start()
        }
    }

    private func swissClockDiameter(in containerSize: CGSize, safeAreaHeight: CGFloat) -> CGFloat {
        return min(
            CGFloat(settings.swissClockSize),
            max(100, containerSize.width - 48),
            max(100, safeAreaHeight - swissClockControlsHeight)
        )
    }
    
    private func clampedTimerPanelOffset(
        _ proposedOffset: CGSize,
        in containerSize: CGSize,
        safeAreaHeight: CGFloat
    ) -> CGSize {
        let diameter = swissClockDiameter(in: containerSize, safeAreaHeight: safeAreaHeight)
        let horizontalMargin: CGFloat = settings.timerDisplayStyle.isAnalog ? diameter / 2 + 24 : 120
        let verticalMargin: CGFloat = settings.timerDisplayStyle.isAnalog
            ? (diameter + swissClockControlsHeight) / 2
            : 90
        
        let minX = -containerSize.width / 2 + horizontalMargin
        let maxX = containerSize.width / 2 - horizontalMargin
        let minY = -safeAreaHeight / 2 + verticalMargin
        let maxY = safeAreaHeight / 2 - verticalMargin
        
        return CGSize(
            width: min(max(proposedOffset.width, minX), maxX),
            height: min(max(proposedOffset.height, minY), maxY)
        )
    }

    private func timerPanelDragGesture(
        currentTimerBaseOffset: CGSize,
        containerSize: CGSize,
        safeAreaHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: settings.timerDisplayStyle.isAnalog ? 1 : 8, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    timerPanelLiveOffset = value.translation
                }
            }
            .onEnded { value in
                let proposedOffset = CGSize(
                    width: currentTimerBaseOffset.width + value.translation.width,
                    height: currentTimerBaseOffset.height + value.translation.height
                )
                timerPanelOffset = clampedTimerPanelOffset(
                    proposedOffset,
                    in: containerSize,
                    safeAreaHeight: safeAreaHeight
                )
                timerPanelLiveOffset = .zero
                persistTimerPanelOffset()
            }
    }
    
    private func persistTimerPanelOffset() {
        UserDefaults.standard.set(timerPanelOffset.width, forKey: "timerPanelOffsetX")
        UserDefaults.standard.set(timerPanelOffset.height, forKey: "timerPanelOffsetY")
    }
    
    private func loadTimerPanelOffsetIfNeeded() {
        guard !didLoadTimerPanelOffset else { return }
        let savedX = UserDefaults.standard.double(forKey: "timerPanelOffsetX")
        let savedY = UserDefaults.standard.double(forKey: "timerPanelOffsetY")
        timerPanelOffset = CGSize(width: savedX, height: savedY)
        didLoadTimerPanelOffset = true
    }
    
    private func syncCampfireParams() {
        noiseManager.setCampfireParams(
            rumble: settings.campfireRumble,
            texture: settings.campfireTexture,
            woodyDensity: settings.campfireWoodyDensity,
            woodyLevel: settings.campfireWoodyLevel,
            snapDensity: settings.campfireSnapDensity,
            snapLevel: settings.campfireSnapLevel,
            rumbleSmooth: settings.campfireRumbleSmooth,
            textureSmooth: settings.campfireTextureSmooth,
            freqLo: settings.campfireFreqLo,
            freqMid: settings.campfireFreqMid,
            freqHi: settings.campfireFreqHi,
            resonance: settings.campfireResonance,
            burstProb: settings.campfireBurstProb
        )
    }

    private func applyAppAppearance() {
        NSApp.appearance = NSAppearance(
            named: settings.sidebarDarkMode ? .darkAqua : .aqua
        )
    }

    private func shouldPlayWhiteNoise() -> Bool {
        guard settings.whiteNoiseEnabled else { return false }
        if settings.whiteNoiseOnlyWhenTimerRunning {
            return timer.isRunning
        }
        return true
    }

    private func updateWhiteNoisePlayback() {
        if shouldPlayWhiteNoise() {
            noiseManager.play()
        } else {
            noiseManager.stop()
        }
    }
    
    private var campfireParamUpdatePublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            settings.$campfireRumble.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireTexture.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireWoodyDensity.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireWoodyLevel.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireSnapDensity.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireSnapLevel.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireRumbleSmooth.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireTextureSmooth.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireFreqLo.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireFreqMid.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireFreqHi.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireResonance.map { _ in () }.eraseToAnyPublisher(),
            settings.$campfireBurstProb.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst()
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .eraseToAnyPublisher()
    }
    
    @ViewBuilder
    private func glassControlButton(_ title: String, palette: ScenePanelPalette, action: @escaping () -> Void) -> some View {
        GlassButton(
            title, 
            settings: settings, 
            fontSize: 18, 
            horizontalPadding: 32, 
            verticalPadding: 12, 
            cornerRadius: 14, 
            panelPalette: palette,
            action: action
        )
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private func todoPanelsLayer(geometry: GeometryProxy, phase: ScenePanelPhase) -> some View {
        let maximumPanelWidth = max(geometry.size.width - 24, 240)
        let basePanelWidth = min(max(CGFloat(settings.todoPanelGroupWidth), 240), maximumPanelWidth)
        let panelWidth = min(max(basePanelWidth + todoPanelGroupLiveWidthDelta, 240), maximumPanelWidth)
        let liveWidthChange = panelWidth - basePanelWidth
        let groupOffset = clampedToDoPanelGroupOffset(
            CGSize(
                width: CGFloat(settings.todoPanelGroupOffsetX)
                    + todoPanelGroupLiveOffset.width
                    + liveWidthChange / 2,
                height: CGFloat(settings.todoPanelGroupOffsetY) + todoPanelGroupLiveOffset.height
            ),
            in: geometry.size,
            panelWidth: panelWidth
        )

        let onGroupDragChanged: (CGSize) -> Void = { todoPanelGroupLiveOffset = $0 }
        let onGroupDragEnded: (CGSize) -> Void = {
            finishToDoPanelGroupDrag($0, in: geometry.size, panelWidth: panelWidth)
        }

        VStack(spacing: 0) {
            TodayPanelView(
                panels: settings.todoPanels,
                panelStores: todoPanelStores,
                skyDate: skyDate,
                onGroupDragChanged: onGroupDragChanged,
                onGroupDragEnded: onGroupDragEnded
            )
            ForEach(Array(settings.todoPanels.enumerated()), id: \.element.id) { index, panel in
                if let store = todoPanelStores.stores[panel.id] {
                    ToDoView(
                        panel: panel,
                        store: store,
                        roundsBottom: index == settings.todoPanels.count - 1,
                        defaultColors: .taskDefault(at: index),
                        listMaxHeight: CGFloat(panel.expandedHeight),
                        onGroupDragChanged: onGroupDragChanged,
                        onGroupDragEnded: onGroupDragEnded,
                        onExpandedHeightChanged: { height in
                            updateToDoPanelExpandedHeight(panelID: panel.id, height: height)
                        }
                    )
                }
            }
        }
        .onChange(of: settings.todoPanels) { _, panels in
            todoPanelStores.updatePanels(panels)
        }
        .frame(width: panelWidth)
        .environment(\.colorScheme, phase == .light ? .light : .dark)
        .overlay(alignment: .trailing) {
            todoPanelGroupWidthResizeHandle(
                containerSize: geometry.size,
                basePanelWidth: basePanelWidth,
                maximumPanelWidth: maximumPanelWidth
            )
        }
        .padding(.top, 12)
        .offset(x: groupOffset.width, y: groupOffset.height)
    }

    private func todoPanelGroupWidthResizeHandle(
        containerSize: CGSize,
        basePanelWidth: CGFloat,
        maximumPanelWidth: CGFloat
    ) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 14)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(.secondary)
                    .frame(width: 3, height: 36)
                    .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        todoPanelGroupLiveWidthDelta = value.translation.width
                    }
                    .onEnded { value in
                        finishToDoPanelGroupWidthResize(
                            value.translation.width,
                            in: containerSize,
                            basePanelWidth: basePanelWidth,
                            maximumPanelWidth: maximumPanelWidth
                        )
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func clampedToDoPanelGroupOffset(
        _ proposedOffset: CGSize,
        in containerSize: CGSize,
        panelWidth: CGFloat
    ) -> CGSize {
        let minimumVisibleWidth = min(panelWidth, 80)
        let minimumX = minimumVisibleWidth - containerSize.width / 2 - panelWidth / 2
        let maximumX = containerSize.width / 2 + panelWidth / 2 - minimumVisibleWidth
        let minimumY: CGFloat = -12
        let maximumY = max(containerSize.height - 60, minimumY)

        return CGSize(
            width: min(max(proposedOffset.width, minimumX), maximumX),
            height: min(max(proposedOffset.height, minimumY), maximumY)
        )
    }

    private func finishToDoPanelGroupDrag(
        _ translation: CGSize,
        in containerSize: CGSize,
        panelWidth: CGFloat
    ) {
        let proposedOffset = CGSize(
            width: CGFloat(settings.todoPanelGroupOffsetX) + translation.width,
            height: CGFloat(settings.todoPanelGroupOffsetY) + translation.height
        )
        let clampedOffset = clampedToDoPanelGroupOffset(
            proposedOffset,
            in: containerSize,
            panelWidth: panelWidth
        )

        settings.todoPanelGroupOffsetX = Double(clampedOffset.width)
        settings.todoPanelGroupOffsetY = Double(clampedOffset.height)
        todoPanelGroupLiveOffset = .zero
    }

    private func finishToDoPanelGroupWidthResize(
        _ horizontalTranslation: CGFloat,
        in containerSize: CGSize,
        basePanelWidth: CGFloat,
        maximumPanelWidth: CGFloat
    ) {
        let newWidth = min(max(basePanelWidth + horizontalTranslation, 240), maximumPanelWidth)
        let widthChange = newWidth - basePanelWidth
        let proposedOffset = CGSize(
            width: CGFloat(settings.todoPanelGroupOffsetX) + widthChange / 2,
            height: CGFloat(settings.todoPanelGroupOffsetY)
        )
        let clampedOffset = clampedToDoPanelGroupOffset(
            proposedOffset,
            in: containerSize,
            panelWidth: newWidth
        )

        settings.todoPanelGroupWidth = Double(newWidth)
        settings.todoPanelGroupOffsetX = Double(clampedOffset.width)
        todoPanelGroupLiveWidthDelta = 0
    }

    private func updateToDoPanelExpandedHeight(panelID: UUID, height: CGFloat) {
        guard let index = settings.todoPanels.firstIndex(where: { $0.id == panelID }) else {
            return
        }
        settings.todoPanels[index].expandedHeight = Double(height)
    }
}

struct BackgroundView: View {
    let imageData: Data?
    
    var body: some View {
        if let imageData = imageData,
           let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        } else {
            Color.black
                .ignoresSafeArea()
        }
    }
}

#Preview {
    ContentView()
}
