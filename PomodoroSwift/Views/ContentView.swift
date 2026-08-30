//
//  ContentView.swift
//  PomodoroSwift
//

import SwiftUI
import UserNotifications
import Combine
import AppKit

struct ContentView: View {
    @StateObject private var settings = Settings()
    @StateObject private var timer: PomodoroTimer
    @StateObject private var noiseManager = WhiteNoiseManager()
    @StateObject private var weeklySchedule = WeeklyScheduleStore()
    @State private var showSidebar = false
    @State private var isSidebarToggleHovered = false
    @State private var isSidebarTogglePressed = false
    @State private var timerPanelOffset: CGSize = .zero
    @State private var timerPanelLiveOffset: CGSize = .zero
    @State private var didLoadTimerPanelOffset = false
    @State private var todoPanelGroupLiveOffset: CGSize = .zero
    @State private var todoPanelGroupLiveWidthDelta: CGFloat = 0
    
    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        _timer = StateObject(wrappedValue: PomodoroTimer(
            workMinutes: settings.selectedTime,
            breakMinutes: settings.breakTime,
            longBreakMinutes: settings.longBreakTime
        ))
    }
    
    /// Global resolved font color based on user setting
    private var fontColor: Color {
        settings.sidebarDarkMode ? .white : .black
    }
    
    var body: some View {
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
                                    .foregroundStyle(fontColor.opacity(0.7))
                                    .padding(.bottom, 4)
                            }
                            
                            // Timer Display
                            // Uses user-selected font size, but shrinks if constrained by the Safe Zone
                            TimerView(
                                time: timer.formattedTime,
                                nsFont: settings.selectedNSFont,
                                glassStyle: glassStyle
                            )
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
                                    glassControlButton("Stop") {
                                        timer.resetToWork()
                                    }
                                    glassControlButton("Short Break") {
                                        timer.startBreak(long: false)
                                    }
                                    glassControlButton("Long Break") {
                                        timer.startBreak(long: true)
                                    }
                                }
                                .padding(.top, 20)
                            } else if timer.isCompleted {
                                // Break completed → start focus
                                glassControlButton("Start Focus Session") {
                                    timer.startNextMode()
                                }
                                .padding(.top, 20)
                            } else if timer.isRunning && (timer.currentMode == .shortBreak || timer.currentMode == .longBreak) {
                                // Break running → stop break
                                glassControlButton("Stop Break") {
                                    timer.resetToWork()
                                }
                                .padding(.top, 20)
                            } else {
                                // Work: Start or Pause
                                glassControlButton(timer.isRunning ? "Pause" : "Start") {
                                    if timer.isRunning {
                                        timer.pause()
                                    } else {
                                        timer.start()
                                    }
                                }
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
                        todoPanelsLayer(geometry: geometry, glassStyle: glassStyle)

                        if weeklySchedule.preferences.isVisible {
                            WeeklySchedulePanel(
                                store: weeklySchedule,
                                containerSize: geometry.size,
                                glassEffect: glassStyle
                            )
                            .environmentObject(settings)
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: timer.isRunning)
                    .animation(.easeInOut(duration: 0.5), value: timer.isCompleted)
                }
            }
            .frame(minWidth: 400, minHeight: 400)
            .background(BackgroundView(imageData: settings.backgroundImageData))
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
                        .foregroundStyle(fontColor)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showSidebar = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(fontColor.opacity(0.6))
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
                    SettingsView(settings: settings, weeklySchedule: weeklySchedule)
                        .padding(20)
                }
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity)
            .background(.clear)
            .glassEffect(glassStyle, in: RoundedRectangle(cornerRadius: 16))
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
                        .foregroundStyle(fontColor)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.clear)
                        .glassEffect(glassStyle)
                        .id(settings.sidebarDarkMode) // Force recreation on mode change
                )
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
        .preferredColorScheme(settings.sidebarDarkMode ? .dark : .light)
        .environment(\.colorScheme, settings.sidebarDarkMode ? .dark : .light)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
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
    
    private func clampedTimerPanelOffset(
        _ proposedOffset: CGSize,
        in containerSize: CGSize,
        safeAreaHeight: CGFloat
    ) -> CGSize {
        let horizontalMargin: CGFloat = 120
        let verticalMargin: CGFloat = 90
        
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
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                timerPanelLiveOffset = value.translation
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
    
    private var glassStyle: Glass {
        var glass: Glass = settings.glassVariant == "clear" ? .clear : .regular
        glass = glass.tint(settings.glassTintColor.opacity(settings.glassTintOpacity))
        if settings.glassInteractive {
            glass = glass.interactive()
        }
        return glass
    }
    
    @ViewBuilder
    private func glassControlButton(_ title: String, action: @escaping () -> Void) -> some View {
        GlassButton(
            title, 
            settings: settings, 
            fontSize: 18, 
            horizontalPadding: 32, 
            verticalPadding: 12, 
            cornerRadius: 14, 
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
    private func todoPanelsLayer(geometry: GeometryProxy, glassStyle: Glass) -> some View {
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

        VStack(spacing: 0) {
            ForEach(Array(settings.todoPanels.enumerated()), id: \.element.id) { index, panel in
                ToDoView(
                    panel: panel,
                    isFirst: index == settings.todoPanels.startIndex,
                    isLast: index == settings.todoPanels.count - 1,
                    glassEffect: glassStyle,
                    listMaxHeight: CGFloat(panel.expandedHeight),
                    onGroupDragChanged: { translation in
                        todoPanelGroupLiveOffset = translation
                    },
                    onGroupDragEnded: { translation in
                        finishToDoPanelGroupDrag(
                            translation,
                            in: geometry.size,
                            panelWidth: panelWidth
                        )
                    },
                    onExpandedHeightChanged: { height in
                        updateToDoPanelExpandedHeight(panelID: panel.id, height: height)
                    }
                )
                .id("\(panel.id.uuidString)-\(settings.sidebarDarkMode ? "dark" : "light")")
                .environmentObject(settings)
            }
        }
        .frame(width: panelWidth)
        .overlay(alignment: .trailing) {
            todoPanelGroupWidthResizeHandle(
                containerSize: geometry.size,
                basePanelWidth: basePanelWidth,
                maximumPanelWidth: maximumPanelWidth
            )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
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
                    .fill(fontColor.opacity(0.28))
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
