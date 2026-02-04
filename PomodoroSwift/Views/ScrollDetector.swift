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
        // Only process if the mouse is roughly over the window (simple check)
        // For a more complex app we might check hit testing, but for this specific 
        // full-width component, capturing all scrolls while it's active is usually fine/better.
        // However, to be safe, we rely on the fact this modifier is only active when the view is present.
        
        if event.phase == .changed || event.momentumPhase == .changed || event.deltaX != 0 {
            // macOS scroll deltas can be small, multiply for better feel
            onScroll(event.scrollingDeltaX)
            
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
