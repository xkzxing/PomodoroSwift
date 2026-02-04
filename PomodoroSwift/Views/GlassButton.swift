//
//  GlassButton.swift
//  PomodoroSwift
//

import SwiftUI

struct GlassButton: View {
    let title: String
    let action: () -> Void
    let variant: String
    let tintColor: Color
    let tintOpacity: Double
    let isInteractive: Bool
    let isDestructive: Bool
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    init(
        _ title: String,
        variant: String = "regular",
        tintColor: Color = .blue,
        tintOpacity: Double = 0.15,
        isInteractive: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.isInteractive = isInteractive
        self.isDestructive = isDestructive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.clear)
                .glassEffect(
                    {
                        let baseGlass: Glass = variant == "clear" ? .clear : .regular
                        if isInteractive {
                            return baseGlass.interactive()
                        } else {
                            let color = isDestructive ? Color.red : tintColor
                            return baseGlass.tint(color.opacity(tintOpacity))
                        }
                    }()
                )
        )
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.03 : 1.0))
        .opacity(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// Extension to use settings directly
extension GlassButton {
    init(_ title: String, settings: Settings, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.init(
            title,
            variant: settings.glassVariant,
            tintColor: settings.glassTintColor,
            tintOpacity: settings.glassTintOpacity,
            isInteractive: settings.glassInteractive,
            isDestructive: isDestructive,
            action: action
        )
    }
}
