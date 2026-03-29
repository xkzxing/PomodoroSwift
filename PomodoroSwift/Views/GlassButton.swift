//
//  GlassButton.swift
//  PomodoroSwift
//

import SwiftUI

struct GlassButton: View {
    let title: String
    let action: () -> Void
    var isDestructive: Bool = false
    
    // Customization parameters
    var fontSize: CGFloat = 14
    var horizontalPadding: CGFloat = 20
    var verticalPadding: CGFloat = 8
    var cornerRadius: CGFloat = 8
    
    // Direct reactivity to settings
    @ObservedObject var settings: Settings

    @State private var isHovered = false
    @State private var isPressed = false

    init(
        _ title: String, 
        settings: Settings, 
        isDestructive: Bool = false, 
        fontSize: CGFloat = 14,
        horizontalPadding: CGFloat = 20,
        verticalPadding: CGFloat = 8,
        cornerRadius: CGFloat = 8,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.settings = settings
        self.isDestructive = isDestructive
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red : (!settings.sidebarDarkMode ? Color.black : Color.white))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(
                    {
                        var glass: Glass = settings.glassVariant == "clear" ? .clear : .regular
                        let color = isDestructive ? Color.red : settings.glassTintColor
                        glass = glass.tint(color.opacity(settings.glassTintOpacity))
                        if settings.glassInteractive {
                            glass = glass.interactive()
                        }
                        return glass
                    }()
                )
                .id(settings.sidebarDarkMode) // Force recreation on mode change
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
