//
//  WindowDragger.swift
//  PomodoroSwift
//
//

import SwiftUI
import AppKit

struct WindowDragger: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }
        
        // This is necessary because we turned off isMovableByWindowBackground
        // We explicitly tell the window to move when the background is clicked
        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
        }
    }
}
