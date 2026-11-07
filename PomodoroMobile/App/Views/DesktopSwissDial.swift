import SwiftUI

/// Uses the desktop dial's twelve indices, proportions and red glass hand.
struct DesktopSwissDial: View {
    let timer: FocusTimer
    @EnvironmentObject private var style: CanvasStyle
    private let red = Color(red: 0.89, green: 0.12, blue: 0.10)

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let handAngle = timer.status == .running ? nil : timer.progress * 360
            ZStack {
                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    for index in 0..<12 {
                        var rotated = context
                        rotated.rotate(by: .degrees(Double(index) * 30))
                        let quarter = index.isMultiple(of: 3)
                        let width = diameter * (quarter ? 0.0175 : 0.014)
                        let length = diameter * (quarter ? 0.074 : 0.063)
                        rotated.fill(Path(roundedRect: CGRect(x: -width / 2, y: -diameter * 0.438,
                                                             width: width, height: length), cornerRadius: diameter * 0.001),
                                     with: .color(style.textColor.opacity(0.94)))
                    }
                }
                .desktopGlass(in: Circle())
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: timer.status != .running)) { timeline in
                    let hand = DesktopRedHand(degrees: handAngle ?? timer.progress(at: timeline.date) * 360)
                    Group {
                        if #available(iOS 26, *) {
                            hand.fill(red.opacity(0.42)).glassEffect(.regular.tint(red), in: hand)
                        } else { hand.fill(red) }
                    }
                    .shadow(color: .black.opacity(0.24), radius: max(0.75, diameter * 0.004),
                            x: diameter * 0.0015, y: diameter * 0.006)
                }
                Circle().fill(style.textColor.opacity(0.94)).frame(width: diameter * 0.031, height: diameter * 0.031)
                Circle().fill(style.preferences.darkText ? Color(white: 0.22) : Color(white: 0.78))
                    .frame(width: diameter * 0.019, height: diameter * 0.019)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timer.mode.title)，剩余 \(timer.remainingSeconds / 60) 分 \(timer.remainingSeconds % 60) 秒")
        .accessibilityIdentifier("timer-dial")
    }
}

private struct DesktopRedHand: Shape {
    var degrees: Double
    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let width = max(1, diameter * 0.0065)
        let stem = Path(roundedRect: CGRect(x: -width / 2, y: -diameter * 0.303,
                                            width: width, height: diameter * 0.3165), cornerRadius: width / 2)
        let tip = Path(ellipseIn: CGRect(x: -diameter * 0.022, y: -diameter * 0.325,
                                       width: diameter * 0.044, height: diameter * 0.044))
        return stem.union(tip)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .applying(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }
}
