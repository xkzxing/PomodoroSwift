import SwiftUI

/// Measure wrapped content at descending sizes, without allowing implicit scaling below the user's floor.
struct ScheduleEventText: View {
    let title: String
    let time: String
    let isCalendarEvent: Bool
    let textColor: Color
    let minimumFontSize: Double
    let width: CGFloat
    let height: CGFloat

    private var minimum: CGFloat { min(11, max(7, minimumFontSize)) }
    private var sizes: [CGFloat] {
        let steps = Array(stride(from: CGFloat(11), through: minimum, by: -0.5))
        return steps.last == minimum ? steps : steps + [minimum]
    }
    private var titleText: Text {
        if isCalendarEvent { Text("\(Image(systemName: "calendar")) \(title)") }
        else { Text(title) }
    }

    var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            ForEach(sizes, id: \.self) { size in
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                        .font(.system(size: size, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(time)
                        .font(.system(size: max(minimum, size - 2), design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            }
            // At the minimum size, prioritize the title; the full title/time remains in the tooltip.
            titleText
                .font(.system(size: minimum, weight: .semibold))
                .lineLimit(max(1, Int(height / (minimum * 1.25))))
                .truncationMode(.tail)
                .frame(width: width, height: height, alignment: .topLeading)
        }
        .multilineTextAlignment(.leading)
        .foregroundStyle(textColor)
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }
}
