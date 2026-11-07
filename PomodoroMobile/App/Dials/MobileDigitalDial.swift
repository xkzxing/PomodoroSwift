import CoreText
import SwiftUI
import UIKit

/// The desktop's glyph-outline glass rendering, using phone font descriptors.
struct MobileDigitalDial: View {
    let time: String
    @EnvironmentObject private var style: CanvasStyle

    var body: some View {
        GeometryReader { geometry in
            let path = DigitalTimerPath.make(text: time, fontName: style.preferences.digitalFontName,
                                             fontSize: style.preferences.digitalFontSize, in: CGRect(origin: .zero, size: geometry.size))
            ZStack {
                Color.clear.desktopGlass(in: path)
                path.stroke(.black.opacity(0.2), lineWidth: 1.2).blur(radius: 1)
                    .offset(y: 1.2).mask(path)
            }.shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("数字倒计时表盘")
        .accessibilityValue(time)
        .accessibilityIdentifier("digital-dial")
    }
}

@MainActor
enum DigitalTimerPath {
    static func make(text: String, fontName: String, fontSize: CGFloat, in rect: CGRect) -> Path {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return Path() }
        let base = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]
        ])
        let font = UIFont(descriptor: descriptor, size: fontSize) as CTFont
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let result = CGMutablePath()
        for case let run as CTRun in CTLineGetGlyphRuns(line) as NSArray {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)
            for index in 0..<count {
                if let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
                    result.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                                      tx: positions[index].x, ty: -positions[index].y))
                }
            }
        }
        let bounds = result.boundingBoxOfPath
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return Path() }
        let scale = min(1, (rect.width - 8) / bounds.width, (rect.height - 8) / bounds.height)
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - bounds.midX * scale, ty: rect.midY - bounds.midY * scale)
        return Path(result).applying(transform)
    }
}
