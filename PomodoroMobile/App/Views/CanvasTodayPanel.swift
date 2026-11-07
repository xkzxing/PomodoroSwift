import SwiftUI

struct CanvasTodayPanel: View {
    @EnvironmentObject private var style: CanvasStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let appearance: TaskMirrorSnapshot.TodayAppearance
    let entries: [TaskMirrorSnapshot.TodayEntry]
    let last: Bool

    var body: some View {
        let expanded = style.preferences.todayExpanded
        let sky = appearance.theme == .sky ? style.liveSky : nil
        let darkText = sky.map { $0.sunAltitude > -6 } ?? style.usesDarkText
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: last ? 16 : 0,
                                           bottomTrailingRadius: last ? 16 : 0, topTrailingRadius: 16)

        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    style.preferences.todayExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    if sky == nil { Image(systemName: "sunrise").accessibilityHidden(true) }
                    Text("今日").font(.system(size: 16, weight: .semibold))
                    Text(entries.count, format: .number).font(.system(size: 11, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.primary.opacity(0.12), in: Capsule())
                    Spacer(minLength: 0)
                        .frame(height: 32)
                        .overlay { if let sky { TodaySkyStars(sky: sky, area: .header) } }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("今日，\(entries.count) 项，\(expanded ? "收起" : "展开")只读面板")
            .background {
                if let sky {
                    ZStack {
                        TodaySkyStars(sky: sky, area: .rim)
                        TodaySkyBodies(sky: sky)
                    }
                    .clipped()
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            if expanded {
                Divider()
                if entries.isEmpty {
                    Text("电脑尚未将待办加入今日")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else {
                    if entries.count <= 4 {
                        ViewThatFits(in: .vertical) {
                            rows.fixedSize(horizontal: false, vertical: true)
                            scrollableRows
                        }
                        .frame(maxHeight: 185)
                    } else {
                        scrollableRows
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .background { shape.fill(gradient(sky: sky)) }
        .desktopGlass(in: shape, opacity: 0, clearGlass: false)
        .environment(\.colorScheme, darkText ? .light : .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-task-panel")
    }

    private var scrollableRows: some View { ScrollView { rows }.frame(height: 185) }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.item.text).font(.subheadline).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    let title = entry.panelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(title.isEmpty ? "未命名面板" : title)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func gradient(sky: TodaySkyAstronomy.Sky?) -> LinearGradient {
        if let sky { return TodaySkyAppearance(sky: sky).gradient(concentration: appearance.skyConcentration) }
        func color(_ hex: Int) -> Color {
            [16, 8, 0].map { Double((hex >> $0) & 255) / 255 }.canvasColor
        }
        return LinearGradient(colors: [color(appearance.gradientStart).opacity(appearance.gradientOpacity),
                                       color(appearance.gradientEnd).opacity(appearance.gradientOpacity * 0.75)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
