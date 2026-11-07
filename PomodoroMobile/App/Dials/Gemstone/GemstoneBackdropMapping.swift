import Foundation
import CoreGraphics

/// A small linear-light image, retained instead of rereading the full photo on
/// timer ticks. Coordinates match the background texture's bitmap convention.
nonisolated struct GemstoneBackdropBrightness: Sendable {
    private static let side = 64
    private let luminance: [Float]

    init(image: CGImage) throws {
        let side = Self.side
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 32,
                bytesPerRow: side * 16, space: space,
                bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: Float.self)
        else { throw CocoaError(.fileReadCorruptFile) }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        luminance = (0..<side * side).map { index in
            let p = index * 4
            return max(0, bytes[p] * 0.2126 + bytes[p + 1] * 0.7152 + bytes[p + 2] * 0.0722)
        }
    }

    private func sample(_ point: CGPoint) -> Float {
        let x = Float(min(1, max(0, point.x))) * Float(Self.side) - 0.5
        let y = Float(min(1, max(0, point.y))) * Float(Self.side) - 0.5
        let ix = Int(floor(x)), iy = Int(floor(y)), fx = x - floor(x), fy = y - floor(y)
        func value(_ x: Int, _ y: Int) -> Float {
            luminance[min(Self.side - 1, max(0, y)) * Self.side + min(Self.side - 1, max(0, x))]
        }
        return (value(ix, iy) * (1 - fx) + value(ix + 1, iy) * fx) * (1 - fy)
            + (value(ix, iy + 1) * (1 - fx) + value(ix + 1, iy + 1) * fx) * fy
    }

    func mean(mapping: GemstoneBackdropMapping, dialSize: CGSize) -> Float {
        var sum: Float = 0, weight: Float = 0
        let diameter = min(dialSize.width, dialSize.height)
        for row in -5...5 {
            for column in -5...5 {
                let x = Float(column) * 0.12, y = Float(row) * 0.12
                let radius = x * x + y * y
                guard radius <= 0.36 else { continue }
                let w = exp(-radius / 0.18)
                let point = CGPoint(x: dialSize.width * 0.5 + CGFloat(x) * diameter,
                    y: dialSize.height * 0.5 + CGFloat(y) * diameter)
                sum += sample(mapping.imagePoint(for: point)) * w
                weight += w
            }
        }
        return sum / max(weight, 1)
    }

    static func emissionGain(luminance: Float) -> Float {
        // Continuous dimming in linear light: dark scenes retain the night
        // glow, while daylight leaves only a small residual emission.
        0.025 + 0.975 / (1 + pow(max(0, luminance) / 0.045, 1.8))
    }

    func emissionGain(mapping: GemstoneBackdropMapping, dialSize: CGSize) -> Float {
        Self.emissionGain(luminance: mean(mapping: mapping, dialSize: dialSize))
    }
}

/// Maps dial-local points into the same aspect-fill image displayed by the
/// window. Keeping this mapping independent of the dial size also makes dragging
/// reveal the correct part of the background through each lens.
nonisolated struct GemstoneBackdropMapping: Sendable {
    let origin: CGPoint
    let step: CGSize

    init(imageSize: CGSize, viewportSize: CGSize, dialFrame: CGRect, horizontalPosition: CGFloat = 0.5) {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            origin = CGPoint(x: 0.5, y: 0.5)
            step = .zero
            return
        }
        var visible = Self.aspectFillRect(imageSize:imageSize,in:CGRect(origin:.zero,size:viewportSize))
        visible.origin.x = (viewportSize.width - visible.width) * min(1, max(0, horizontalPosition))
        origin = CGPoint(
            x: (dialFrame.minX - visible.minX) / visible.width,
            y: (dialFrame.minY - visible.minY) / visible.height
        )
        step = CGSize(width: 1 / visible.width, height: 1 / visible.height)
    }

    /// Used by offscreen drawing as well as optical sampling. Drawing a photo
    /// directly into the viewport would stretch it and misalign the two paths.
    static func aspectFillRect(imageSize: CGSize, in viewport: CGRect) -> CGRect {
        guard imageSize.width>0,imageSize.height>0,viewport.width>0,viewport.height>0 else { return .zero }
        let scale=max(viewport.width/imageSize.width,viewport.height/imageSize.height)
        let width=imageSize.width*scale,height=imageSize.height*scale
        return CGRect(x:viewport.midX-width/2,y:viewport.midY-height/2,width:width,height:height)
    }

    func imagePoint(for localPoint: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + localPoint.x * step.width,
                y: origin.y + localPoint.y * step.height)
    }
}
