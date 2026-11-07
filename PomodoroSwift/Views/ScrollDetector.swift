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

    func body(content: Content) -> some View {
        content
            .background(
                ScrollEventMonitor(
                    onScroll: onScroll,
                    onScrollEnd: onScrollEnd
                )
            )
    }
}

private struct ScrollEventMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onScrollEnd: () -> Void

    func makeNSView(context: Context) -> ScrollMonitorView {
        let view = ScrollMonitorView()
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        return view
    }

    func updateNSView(_ view: ScrollMonitorView, context: Context) {
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
    }
}

private final class ScrollMonitorView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var onScrollEnd: (() -> Void)?
    private var monitor: Any?
    private var scrollEndWorkItem: DispatchWorkItem?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        removeMonitor()
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak newWindow] event in
            guard let self, let newWindow, event.window === newWindow else { return event }
            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else { return event }
            self.detectScroll(event)
            return event
        }
    }

    deinit {
        removeMonitor()
    }

    private func detectScroll(_ event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        guard abs(deltaX) > abs(event.scrollingDeltaY), deltaX != 0 else { return }
        onScroll?(deltaX)

        scrollEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.onScrollEnd?() }
        scrollEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func removeMonitor() {
        scrollEndWorkItem?.cancel()
        scrollEndWorkItem = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

extension View {
    func onScroll(perform action: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) -> some View {
        self.modifier(ScrollViewModifier(onScroll: action, onScrollEnd: onEnd))
    }
}
