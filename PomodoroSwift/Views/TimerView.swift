//
//  TimerView.swift
//  PomodoroSwift
//

import SwiftUI
import AppKit
import CoreText

struct TimerView: View {
    let time: String
    let nsFont: NSFont
    let glassStyle: Glass
    var sceneInk: Color? = nil
    @State private var cachedPath: Path = Path()
    @State private var cachedPathKey: String = ""

    var body: some View {
        Text(time)
            .font(Font(nsFont as CTFont))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.1)
            .foregroundStyle(.clear)
            .overlay {
                GeometryReader { proxy in
                    let pathKey = makePathKey(for: proxy.size)
                    ZStack {
                        Color.clear
                            .glassEffect(glassStyle, in: cachedPath)

                        if let sceneInk {
                            cachedPath.fill(sceneInk.opacity(0.58))
                        }

                        cachedPath
                            .stroke(.black.opacity(0.20), lineWidth: 1.2)
                            .blur(radius: 1.0)
                            .offset(y: 1.2)
                            .mask(cachedPath)

                    }
                    .onAppear {
                        rebuildPathIfNeeded(for: proxy.size, pathKey: pathKey)
                    }
                    .onChange(of: pathKey) { _, _ in
                        rebuildPathIfNeeded(for: proxy.size, pathKey: pathKey)
                    }
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
    }

    private func makePathKey(for size: CGSize) -> String {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        let pointSize = Int(nsFont.pointSize.rounded())
        return "\(time)|\(nsFont.fontName)|\(pointSize)|\(w)x\(h)"
    }

    private func rebuildPathIfNeeded(for size: CGSize, pathKey: String) {
        guard pathKey != cachedPathKey else { return }
        cachedPath = TimerTextPathFactory.makePath(
            text: time,
            fontName: nsFont.fontName,
            fontSize: nsFont.pointSize,
            in: CGRect(origin: .zero, size: size)
        )
        cachedPathKey = pathKey
    }
}

private enum TimerTextPathFactory {
    static func makePath(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        in rect: CGRect
    ) -> Path {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else {
            return Path()
        }

        let ctFont = monospacedDigitFont(fontName: fontName, fontSize: fontSize)
        let ctFontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
        let attributed = NSAttributedString(
            string: text,
            attributes: [ctFontKey: ctFont]
        )
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let originX = rect.midX - lineWidth / 2
        let baselineY = rect.midY + (ascent - descent) / 2

        let result = CGMutablePath()
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else {
            return Path()
        }

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = Array(repeating: CGGlyph(), count: glyphCount)
            var positions = Array(repeating: CGPoint.zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)

            for idx in 0..<glyphCount {
                guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[idx], nil) else {
                    continue
                }

                let position = positions[idx]
                let transform = CGAffineTransform(
                    a: 1,
                    b: 0,
                    c: 0,
                    d: -1,
                    tx: originX + position.x,
                    ty: baselineY - position.y
                )
                result.addPath(glyphPath, transform: transform)
            }
        }

        return Path(result)
    }

    private static func monospacedDigitFont(fontName: String, fontSize: CGFloat) -> CTFont {
        let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let featureSettings: [[NSFontDescriptor.FeatureKey: Int]] = [[
            .typeIdentifier: kNumberSpacingType,
            .selectorIdentifier: kMonospacedNumbersSelector
        ]]
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .featureSettings: featureSettings
        ])
        let adjusted = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
        return adjusted as CTFont
    }
}

#Preview {
    ZStack {
        Color.black
        TimerView(
            time: "25:00",
            nsFont: NSFont(name: "Helvetica Neue", size: 120) ?? NSFont.systemFont(ofSize: 120),
            glassStyle: .regular
        )
    }
}
