//
//  ContentView.swift
//  PomodoroSwift
//

import SwiftUI
import UserNotifications
import Combine

struct ContentView: View {
    @StateObject private var settings = Settings()
    @StateObject private var timer: PomodoroTimer
    @StateObject private var noiseManager = WhiteNoiseManager()
    @State private var showSidebar = false
    @State private var isSidebarToggleHovered = false
    @State private var isSidebarTogglePressed = false
    
    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        _timer = StateObject(wrappedValue: PomodoroTimer(
            workMinutes: settings.selectedTime,
            breakMinutes: settings.breakTime,
            longBreakMinutes: settings.longBreakTime
        ))
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
                        
                        VStack(spacing: 0) {
                            Spacer()
                            
                            // Break Label
                            if timer.currentMode == .shortBreak || timer.currentMode == .longBreak {
                                Text("Break")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.bottom, 4)
                            }
                            
                            // Timer Display
                            // Uses user-selected font size, but shrinks if constrained by the Safe Zone
                            TimerView(
                                time: timer.formattedTime,
                                isCompleted: timer.isCompleted,
                                nsFont: settings.selectedNSFont
                            )
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
                            
                            Spacer()
                        }
                        .frame(width: geometry.size.width, height: safeAreaHeight)
                        .position(x: geometry.size.width / 2, y: safeAreaHeight / 2) // Explicit positioning
                        
                        // Time Selector (Pinned to Window Bottom)
                        if !timer.isRunning && !timer.isCompleted && timer.currentMode == .work {
                            TimeSelector(selectedTime: $settings.selectedTime)
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

                        // To-Do Panel (pinned bottom, above TimeSelector)
                        let bottomPadding: CGFloat = (!timer.isRunning && !timer.isCompleted && timer.currentMode == .work) ? 100 : 16
                        // Available height below the safe area (where Start button lives)
                        let todoMaxHeight = max(geometry.size.height - safeAreaHeight - bottomPadding, 60)
                        VStack {
                            Spacer()
                            ToDoView(glassEffect: glassStyle, listMaxHeight: max(todoMaxHeight - 100, 180))
                                .padding(.bottom, bottomPadding)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
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
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showSidebar = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
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
                    SettingsView(settings: settings)
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
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.clear)
                        .glassEffect(glassStyle)
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
            requestNotificationPermission()
            // Sync initial noise settings
            noiseManager.setVolume(settings.whiteNoiseVolume)
            if let type = NoiseType(rawValue: settings.whiteNoiseType) {
                noiseManager.setNoiseType(type)
            }
            syncCampfireParams()
        }
        .onChange(of: settings.whiteNoiseVolume) { _, newValue in
            noiseManager.setVolume(newValue)
        }
        .onChange(of: settings.whiteNoiseType) { _, newValue in
            if let type = NoiseType(rawValue: newValue) {
                noiseManager.setNoiseType(type)
            }
        }
        .onChange(of: settings.whiteNoiseEnabled) { _, enabled in
            if enabled && timer.isRunning {
                noiseManager.play()
            } else if !enabled {
                noiseManager.stop()
            }
        }
        .onChange(of: timer.isRunning) { _, running in
            if running && settings.whiteNoiseEnabled {
                noiseManager.play()
            } else if !running {
                noiseManager.stop()
            }
        }
        .onReceive(
            settings.$campfireRumble.merge(with:
                settings.$campfireTexture,
                settings.$campfireWoodyDensity,
                settings.$campfireWoodyLevel,
                settings.$campfireSnapDensity,
                settings.$campfireSnapLevel,
                settings.$campfireRumbleSmooth
            ).merge(with:
                settings.$campfireTextureSmooth,
                settings.$campfireFreqLo,
                settings.$campfireFreqMid,
                settings.$campfireFreqHi,
                settings.$campfireResonance,
                settings.$campfireBurstProb
            ).dropFirst()
        ) { _ in
            syncCampfireParams()
        }
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
