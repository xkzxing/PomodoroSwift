import SwiftUI

struct CanvasTaskPanel: View {
    @EnvironmentObject private var style: CanvasStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let panel: TaskMirrorSnapshot.Panel
    let index: Int
    let first: Bool
    let last: Bool

    @State private var resizingHeight = 0.0
    private var group: TaskGroup { TaskGroup(id: panel.id, title: panel.title) }
    private var look: PanelLook { style.look(for: group, index: index) }
    private var expanded: Bool { look.expanded }
    private var palette: (tint: [Double], darkText: Bool) {
        panel.appearance.colors(forLightScene: style.scenePhase.map { $0 == .light })
    }
    private var textColor: Color { palette.darkText ? .black : .white }
    private var pinnedCount: Int { panel.items.filter(\.isPinned).count }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: first ? 16 : 0, bottomLeadingRadius: last ? 16 : 0,
                               bottomTrailingRadius: last ? 16 : 0, topTrailingRadius: first ? 16 : 0)
    }

    var body: some View {
        let firstUnpinned = panel.items.first { !$0.isPinned }?.id
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle").font(.system(size: 16, weight: .medium))
                    Text(panel.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if pinnedCount > 0 {
                        Text("\(pinnedCount)").font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(textColor.opacity(0.17), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(textColor.opacity(0.65))
                }
                .foregroundStyle(textColor.opacity(0.9)).padding(.horizontal, 16)
                .frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(panel.title)，\(expanded ? "收起" : "展开")只读面板")
            if expanded {
                Divider().overlay(textColor.opacity(0.06))
                if panel.items.isEmpty {
                    Text("暂无待办").font(.system(size: 14)).foregroundStyle(textColor.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(panel.items) { item in
                                if pinnedCount > 0, item.id == firstUnpinned {
                                    Divider().overlay(textColor.opacity(0.1)).padding(.horizontal, 16).padding(.vertical, 4)
                                }
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 16)).foregroundStyle(item.isPinned ? .blue : textColor.opacity(0.35))
                                        .frame(width: 22).padding(.top, 2).accessibilityHidden(true)
                                    Text(item.text).font(.system(size: 15, weight: item.isPinned ? .semibold : .regular))
                                        .foregroundStyle(textColor.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                    if item.isInToday {
                                        Image(systemName: "sun.max.fill").font(.system(size: 14))
                                            .foregroundStyle(textColor.opacity(0.65)).accessibilityHidden(true)
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 12)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(item.isPinned ? "已置顶，" : "")\(item.isInToday ? "已加入今日，" : "")\(item.text)")
                            }
                        }
                    }.frame(height: max(100, min(600, look.expandedHeight + resizingHeight)))
                }
                Capsule().fill(textColor.opacity(0.3)).frame(width: 32, height: 4)
                    .frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { resizingHeight = $0.translation.height }
                        .onEnded { value in
                            var updated = look
                            updated.expandedHeight = max(100, min(600, look.expandedHeight + value.translation.height))
                            style.update(updated, for: group)
                            resizingHeight = 0
                        })
                    .accessibilityLabel("调整面板显示高度")
                    .accessibilityAdjustableAction { direction in
                        var updated = look
                        updated.expandedHeight = max(100, min(600, look.expandedHeight + (direction == .increment ? 40 : -40)))
                        style.update(updated, for: group)
                    }
            }
        }
        .desktopGlass(in: shape, tint: palette.tint.canvasColor, opacity: panel.appearance.opacity, clearGlass: panel.appearance.clearGlass)
        .environment(\.colorScheme, palette.darkText ? .light : .dark)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(.white.opacity(0.25)).frame(height: 0.7) } }
    }

    private func toggleExpanded() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            var look = style.look(for: group, index: index)
            look.expanded.toggle()
            style.update(look, for: group)
        }
    }
}
