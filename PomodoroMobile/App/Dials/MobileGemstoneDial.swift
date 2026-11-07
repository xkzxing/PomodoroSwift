import SwiftUI
import UIKit

nonisolated enum GemstoneClockCadence {
    static func interval(duration: TimeInterval, diameter: CGFloat, displayScale: CGFloat) -> TimeInterval {
        guard duration.isFinite, duration > 0, diameter.isFinite, displayScale.isFinite else { return 0.25 }
        let pixelsPerSecond = max(0, diameter) * 0.362 * max(1, displayScale) * 2 * .pi / duration
        return 1 / min(30, max(4, pixelsPerSecond / 0.5))
    }
}

struct MobileGemstoneDial: View {
    let timer: FocusTimer
    let diameter: CGFloat
    @EnvironmentObject private var style: CanvasStyle
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var rayFailed = false

    var body: some View {
        let interval = reduceMotion ? 1 : GemstoneClockCadence.interval(
            duration: Double(timer.durationSeconds), diameter: diameter, displayScale: displayScale)
        TimelineView(.animation(minimumInterval: interval, paused: timer.status != .running || scenePhase != .active)) { timeline in
            let degrees = timer.progress(at: timeline.date) * 360
            let image = style.dialBackdrop
            Group {
                if scenePhase != .active {
                    Color.clear
                } else if GemstoneRayResources.supported, let image, !rayFailed {
                    Gemstone3DView(background: image, viewportSize: style.backdropFrame.size,
                        backgroundPosition: style.dialBackdropPosition, handDegrees: degrees,
                        backdropOrigin: style.backdropFrame.origin, onFailure: { rayFailed = true })
                } else {
                    MobileLegacyGemstoneDial(image: image ?? Self.blackBackground, degrees: degrees)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("鎏金彩晶倒计时表盘")
        .accessibilityValue("\(timer.mode.title)，剩余 \(timer.remainingSeconds / 60) 分 \(timer.remainingSeconds % 60) 秒")
        .accessibilityIdentifier("gemstone-dial")
    }

    private static let blackBackground: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image {
        UIColor.black.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

private struct MobileLegacyGemstoneDial: View {
    let image: UIImage
    let degrees: Double
    @EnvironmentObject private var style: CanvasStyle
    @State private var maps: GemstoneSurfaceMaps?
    @State private var frame = CGRect.zero

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let origin = style.backdropFrame.origin
            ZStack {
                Circle().fill(.white.opacity(0.012)).desktopGlass(in: Circle())
                    .frame(width: diameter * 0.7, height: diameter * 0.7)
                if let maps {
                    GemstoneMetalSurface(maps: maps, background: image, viewportSize: style.backdropFrame.size,
                        backgroundPosition: style.dialBackdropPosition, dialFrame: frame, handDegrees: degrees)
                        .shadow(color: .black.opacity(0.28), radius: diameter * 0.005, y: diameter * 0.008)
                } else { ProgressView("正在准备彩晶表盘").font(.caption) }
            }
            .frame(width: diameter, height: diameter)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global).offsetBy(dx: -origin.x, dy: -origin.y)
            } action: { frame = $0 }
        }
        .task { maps = await GemstoneSculpture.maps.value }
        .allowsHitTesting(false)
    }
}
