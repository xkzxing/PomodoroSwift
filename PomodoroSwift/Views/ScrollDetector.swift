//
//  ScrollDetector.swift
//  PomodoroSwift
//
//

import SwiftUI
import AppKit

struct ScrollViewModifier: ViewModifier {
    var onScroll: (CGFloat) -> Void
    var onScrollEnd: () -> Void
    
    @State private var monitor: Any?
    @State private var scrollTimer: Timer?
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { _ in
                    Color.clear
                        .onAppear {
                            // Add local monitor for scroll wheel events
                            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                detectScroll(event: event)
                                return event
                            }
                        }
                        .onDisappear {
                            if let monitor = monitor {
                                NSEvent.removeMonitor(monitor)
                                self.monitor = nil
                            }
                            scrollTimer?.invalidate()
                            scrollTimer = nil
                        }
                }
            )
    }
    
    private func detectScroll(event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let hasHorizontalIntent = abs(deltaX) > abs(deltaY)
        guard hasHorizontalIntent, abs(deltaX) > 0 else { return }
        
        if event.phase == .changed || event.momentumPhase == .changed || deltaX != 0 {
            onScroll(deltaX)
            
            // Debounce end of scroll
            scrollTimer?.invalidate()
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                onScrollEnd()
            }
        }
    }
}

extension View {
    func onScroll(perform action: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) -> some View {
        self.modifier(ScrollViewModifier(onScroll: action, onScrollEnd: onEnd))
    }
}
