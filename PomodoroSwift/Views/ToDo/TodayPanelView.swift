import SwiftUI
import AppKit

struct TodayPanelView: View {
    private static let defaultGradientStart = TaskMirrorSnapshot.TodayAppearance.defaultGradientStart
    private static let defaultGradientEnd = TaskMirrorSnapshot.TodayAppearance.defaultGradientEnd
    private static let defaultGradientOpacity = TaskMirrorSnapshot.TodayAppearance.defaultGradientOpacity
    typealias Theme = TaskMirrorSnapshot.TodayAppearance.Theme

    let panels: [ToDoPanel]
    @ObservedObject var panelStores: ToDoPanelStores
    let skyDate: Date
    let onGroupDragChanged: (CGSize) -> Void
    let onGroupDragEnded: (CGSize) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("todayPanelTheme") private var theme = Theme.custom
    @AppStorage("todayPanelExpanded") private var isExpanded = true
    @AppStorage("todayGradientStart") private var gradientStart = TodayPanelView.defaultGradientStart
    @AppStorage("todayGradientEnd") private var gradientEnd = TodayPanelView.defaultGradientEnd
    @AppStorage("todayGradientOpacity") private var gradientOpacity = TodayPanelView.defaultGradientOpacity
    @AppStorage("todaySkyColorConcentration") private var skyColorConcentration = TaskMirrorSnapshot.TodayAppearance.defaultSkyConcentration
    @State private var showAppearance = false
    @ObservedObject private var skyLocation = TodaySkyLocation.shared

    private struct Entry: Identifiable {
        struct ID: Hashable {
            let panel: UUID
            let task: UUID
        }

        let panel: ToDoPanel
        let store: ToDoStore
        let item: ToDoItem
        var id: ID { ID(panel: panel.id, task: item.id) }
    }

    private var entries: [Entry] {
        panels.flatMap { panel -> [Entry] in
            guard let store = panelStores.stores[panel.id] else { return [] }
            return store.items.filter(\.isInToday).map { Entry(panel: panel, store: store, item: $0) }
        }
    }

    var body: some View {
        let entries = entries
        let sky = theme == .sky ? TodaySkyAstronomy.sky(at: skyDate, coordinates: skyLocation.coordinates) : nil
        let gradient = sky.map { TodaySkyAppearance(sky: $0).gradient(concentration: skyColorConcentration) }
            ?? LinearGradient(
                colors: [
                    color(for: gradientStart).opacity(gradientOpacity),
                    color(for: gradientEnd).opacity(gradientOpacity * 0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        VStack(spacing: 0) {
            header(count: entries.count, sky: sky)
            TodayDisclosureLayout(progress: isExpanded ? 1 : 0) {
                tasksBody(entries)
            }
            .clipped()
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .taskPanelSurface(gradient: gradient, roundsTop: true, roundsBottom: panels.isEmpty)
        .environment(\.colorScheme, (sky?.sunAltitude ?? 0) <= -6 ? .dark : colorScheme)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayTaskPanel")
    }

    private func header(count: Int, sky: TodaySkyAstronomy.Sky?) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if sky == nil {
                    Image(systemName: "sunrise")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text("今日").font(.system(size: 14, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.12), in: Capsule())
                    .accessibilityLabel("已固定 \(count) 项")
                Spacer(minLength: 0)
                    .frame(height: 28)
                    .overlay {
                        if let sky {
                            TodaySkyStars(sky: sky, area: .header)
                        }
                    }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { onGroupDragChanged($0.translation) }
                    .onEnded { onGroupDragEnded($0.translation) }
            )

            Button {
                showAppearance.toggle()
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("调整今日外观")
            .accessibilityLabel("调整今日外观")
            .popover(isPresented: $showAppearance, arrowEdge: .top) {
                appearancePicker
            }

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "折叠今日" : "展开今日")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            if let sky {
                ZStack {
                    TodaySkyStars(sky: sky, area: .rim)
                    TodaySkyBodies(sky: sky)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
            }
        }
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("今日主题", selection: $theme) {
                Text("自定义渐变").tag(Theme.custom)
                Text("晴空").tag(Theme.sky)
            }
            Divider()
            if theme == .sky {
                opacitySlider("晴空颜色浓度", value: $skyColorConcentration, in: 0...1)
                Text(skyLocation.coordinates == nil ? "按本地时间" : "按已保存的位置")
                    .foregroundStyle(.secondary)
                Button(skyLocation.isLocating ? "正在定位…" : "更新位置") {
                    skyLocation.updateLocation()
                }
                .disabled(skyLocation.isLocating || !skyLocation.canUpdateLocation)
                if !skyLocation.canUpdateLocation {
                    Text("可在系统设置中允许定位。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if skyLocation.lastUpdateFailed {
                    Text("未能更新位置，可以稍后重试。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                customGradientControls
            }
        }
        .padding(14)
        .frame(width: 220)
    }

    private var customGradientControls: some View {
        Group {
            ColorPicker("渐变起点", selection: colorBinding($gradientStart), supportsOpacity: false)
            ColorPicker("渐变终点", selection: colorBinding($gradientEnd), supportsOpacity: false)
            opacitySlider("渐变不透明度", value: $gradientOpacity, in: 0...0.65)
            Button("恢复默认渐变") {
                gradientStart = Self.defaultGradientStart
                gradientEnd = Self.defaultGradientEnd
                gradientOpacity = Self.defaultGradientOpacity
            }
        }
    }

    private func opacitySlider(_ label: LocalizedStringKey, value: Binding<Double>,
                               in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 0.01) { Text(label) }
                .labelsHidden()
        }
    }

    private func color(for rgb: Int) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    private func colorBinding(_ rgb: Binding<Int>) -> Binding<Color> {
        Binding {
            color(for: rgb.wrappedValue)
        } set: { selected in
            guard let srgb = NSColor(selected).usingColorSpace(.sRGB) else { return }
            rgb.wrappedValue = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].reduce(0) {
                let channel = Int((min(max($1, 0), 1) * 255).rounded())
                return ($0 << 8) | channel
            }
        }
    }

    private func tasksBody(_ entries: [Entry]) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(.primary.opacity(0.12)).frame(height: 1)
            if entries.isEmpty {
                Text("从其他面板固定任务到这里")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ViewThatFits(in: .vertical) {
                    taskRows(entries).fixedSize(horizontal: false, vertical: true)
                    ScrollView { taskRows(entries) }
                        .frame(height: 160)
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func taskRows(_ entries: [Entry]) -> some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.item.text)
                            .font(.system(size: 13))
                            .lineLimit(2)
                        let title = entry.panel.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(title.isEmpty ? "未命名面板" : title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ToDoTodayButton(isInToday: true, textColor: .primary) {
                        entry.store.setInToday(false, id: entry.item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("移出今日") { entry.store.setInToday(false, id: entry.item.id) }
                    Button("删除", role: .destructive) { entry.store.delete(id: entry.item.id) }
                }
            }
        }
    }
}

private struct TodayDisclosureLayout: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * min(max(progress, 0), 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
