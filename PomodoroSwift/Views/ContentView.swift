//
//  ContentView.swift
//  PomodoroSwift
//

import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject private var settings = Settings()
    @StateObject private var timer: PomodoroTimer
    @State private var showSidebar = false
    @State private var isButtonHovered = false
    @State private var isButtonPressed = false
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
                // Background
                BackgroundView(imageData: settings.backgroundImageData)
                
                
                // Content
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        // Main Timer & Controls
                        // strictly constrained to the top "Safe Zone" to prevent overlap
                        let safeAreaHeight = max(geometry.size.height - 160, 150)
                        
                        VStack(spacing: 0) {
                            Spacer()
                            
                            // Timer Display
                            // Uses user-selected font size, but shrinks if constrained by the Safe Zone
                            TimerView(
                                time: timer.formattedTime,
                                isCompleted: timer.isCompleted,
                                nsFont: settings.selectedNSFont
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                            
                            // Control Button
                            Button(action: toggleTimer) {
                                Text(buttonText)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.clear)
                                    .glassEffect(glassStyle)
                            )
                            .scaleEffect(isButtonPressed ? 0.95 : (isButtonHovered ? 1.05 : 1.0))
                            .opacity(isButtonPressed ? 0.9 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonHovered)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isButtonPressed)
                            .onHover { hovering in
                                isButtonHovered = hovering
                            }
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        isButtonPressed = true
                                    }
                                    .onEnded { _ in
                                        isButtonPressed = false
                                    }
                            )
                            .padding(.top, 20)
                            
                            Spacer()
                        }
                        .frame(width: geometry.size.width, height: safeAreaHeight)
                        .position(x: geometry.size.width / 2, y: safeAreaHeight / 2) // Explicit positioning
                        
                        // Time Selector (Pinned to Bottom)
                        if !timer.isRunning && !timer.isCompleted {
                            VStack {
                                Spacer()
                                TimeSelector(selectedTime: $settings.selectedTime)
                                    .onChange(of: settings.selectedTime) { oldValue, newValue in
                                        timer.updateTime(
                                            workMinutes: newValue,
                                            breakMinutes: settings.breakTime,
                                            longBreakMinutes: settings.longBreakTime
                                        )
                                    }
                                    .padding(.bottom, 50)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .allowsHitTesting(true)
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: timer.isRunning)
                    .animation(.easeInOut(duration: 0.5), value: timer.isCompleted)
                }
            }
            .frame(minWidth: 400, minHeight: 400)
            .ignoresSafeArea()
            .background(WindowDragger()) 
            .zIndex(0)
            
            // Overlay Backdrop (tap to close)
            Color.clear
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
            .environment(\.colorScheme, .dark)
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
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            requestNotificationPermission()
        }
    }
    
    private var glassStyle: Glass {
        let baseGlass: Glass = settings.glassVariant == "clear" ? .clear : .regular
        if settings.glassInteractive {
            return baseGlass.interactive()
        } else {
            return baseGlass.tint(settings.glassTintColor.opacity(settings.glassTintOpacity))
        }
    }
    
    private var buttonText: String {
        if timer.isCompleted {
            switch timer.currentMode {
            case .work:
                if timer.sessionCount % 4 == 0 {
                    return "Start Long Break"
                } else {
                    return "Start Short Break"
                }
            case .shortBreak, .longBreak:
                return "Start Focus Session"
            }
        } else if timer.isRunning {
            return "Pause"
        } else {
            return "Start"
        }
    }
    
    private func toggleTimer() {
        if timer.isCompleted {
            timer.startNextMode()
        } else if timer.isRunning {
            timer.pause()
        } else {
            timer.start()
        }
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
