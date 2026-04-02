import SwiftUI

struct DragHandle: View {
    let textColor: Color
    let onDragChanged: (_ translationY: CGFloat, _ globalY: CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(textColor.opacity(isHovered ? 0.5 : 0.2))
            .frame(width: 18, height: 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        onDragChanged(value.translation.height, value.location.y)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
