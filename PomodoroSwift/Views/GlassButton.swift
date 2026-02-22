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
    
    // Customization parameters
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat

    @State private var isHovered = false
    @State private var isPressed = false

    init(
        _ title: String,
        variant: String = "regular",
        tintColor: Color = .blue,
        tintOpacity: Double = 0.15,
        isInteractive: Bool = false,
        isDestructive: Bool = false,
        fontSize: CGFloat = 14,
        horizontalPadding: CGFloat = 20,
        verticalPadding: CGFloat = 8,
        cornerRadius: CGFloat = 8,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.isInteractive = isInteractive
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
                .foregroundStyle(isDestructive ? Color.red : .primary)
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
                        var glass: Glass = variant == "clear" ? .clear : .regular
                        let color = isDestructive ? Color.red : tintColor
                        glass = glass.tint(color.opacity(tintOpacity))
                        if isInteractive {
                            glass = glass.interactive()
                        }
                        return glass
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
        self.init(
            title,
            variant: settings.glassVariant,
            tintColor: settings.glassTintColor,
            tintOpacity: settings.glassTintOpacity,
            isInteractive: settings.glassInteractive,
            isDestructive: isDestructive,
            fontSize: fontSize,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            cornerRadius: cornerRadius,
            action: action
        )
    }
}
