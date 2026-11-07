import SwiftUI
import AppKit

nonisolated enum GemstoneClockCadence {
    static func interval(duration: TimeInterval, diameter: CGFloat, displayScale: CGFloat) -> TimeInterval {
        guard duration.isFinite, duration > 0, diameter.isFinite, displayScale.isFinite else { return 0.25 }
        // Keep motion below half a physical pixel per update where possible.
        // A whole-session hand moves much slower than a conventional second hand.
        let pixelsPerSecond = max(0, diameter) * 0.362 * max(1, displayScale) * 2 * .pi / duration
        let rate = min(30, max(4, pixelsPerSecond / 0.5))
        return 1 / rate
    }
}

struct GemstoneClockView: View {
    let progress: SwissClockProgress
    let glassStyle: Glass
    var backdropImage: NSImage? = nil
    var backdropSize: CGSize = .zero
    var body: some View {
        if GemstoneRayResources.supported, let backdropImage {
            Gemstone3DView(background: backdropImage,
                viewportSize: backdropSize, handDegrees: progress.redHandDegrees)
                .aspectRatio(1, contentMode: .fit)
        } else {
            GemstoneLegacyClockView(progress: progress, glassStyle: glassStyle,
                backdropImage: backdropImage, backdropSize: backdropSize)
        }
    }
}

/// Retained for GPUs without ray intersection support.
private struct GemstoneLegacyClockView: View {
    let progress: SwissClockProgress
    let glassStyle: Glass
    let backdropImage: NSImage?
    let backdropSize: CGSize
    @State private var surfaceMaps: GemstoneSurfaceMaps?
    @State private var dialFrame = CGRect.zero

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let image = backdropImage ?? GemstoneOptics.blackBackground
            let viewport = backdropSize == .zero ? geometry.size : backdropSize
            ZStack {
                Circle()
                    .fill(.white.opacity(0.012))
                    .glassEffect(glassStyle, in: .circle)
                    .frame(width: diameter * 0.700, height: diameter * 0.700)
                if let surfaceMaps {
                    GemstoneMetalSurface(maps: surfaceMaps, background: image, viewportSize: viewport,
                        dialFrame: dialFrame, handDegrees: progress.redHandDegrees)
                        .shadow(color: .black.opacity(0.28), radius: diameter * 0.005, y: diameter * 0.008)
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("gemstoneBackdrop"))
            } action: { frame in
                // Only a tiny uniform block changes while dragging. Curve data
                // and GPU textures are retained by the existing native view.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { dialFrame = frame }
            }
        }
        .task { surfaceMaps = await GemstoneSculpture.maps.value }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum GemstoneOptics {
    static let blackBackground = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
        NSColor.black.setFill()
        rect.fill()
        return true
    }
}
