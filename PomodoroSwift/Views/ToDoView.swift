//
//  ToDoView.swift
//  PomodoroSwift
//

import SwiftUI

struct ToDoView: View {
    let panel: ToDoPanel
    let roundsBottom: Bool
    let onGroupDragChanged: (CGSize) -> Void
    let onGroupDragEnded: (CGSize) -> Void
    let onExpandedHeightChanged: (CGFloat) -> Void
    @ObservedObject private var store: ToDoStore
    @StateObject private var appearance: PanelAppearanceSettings
    @Environment(\.scenePanelPhase) private var phase
    @State private var newText: String = ""
    @FocusState private var inputFocused: Bool

    @State private var draggingItemId: UUID?
    @State private var cancelledDragItemId: UUID?
    @State private var pendingDropItemId: UUID?
    @State private var latestDragGlobalY: CGFloat?
    @State private var dragDisplayOffsetY: CGFloat = 0
    @State private var initialDragIndex: Int?
    @State private var currentDragIndex: Int?
    @State private var lastChangeItemId: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var scrollViewportFrame: CGRect = .zero
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollDirection: ToDoAutoScrollDirection?

    var listMaxHeight: CGFloat

    @State private var showGlassPicker: Bool = false
    @State private var liveExpandedHeightDelta: CGFloat = 0

    private let autoScrollHotZoneHeight: CGFloat = 32
    private let autoScrollTickInterval: TimeInterval = 0.06
    private let swapEdgeBumper: CGFloat = 18

    init(
        panel: ToDoPanel,
        store: ToDoStore,
        roundsBottom: Bool,
        defaultColors: ScenePanelColors,
        listMaxHeight: CGFloat = 180,
        onGroupDragChanged: @escaping (CGSize) -> Void,
        onGroupDragEnded: @escaping (CGSize) -> Void,
        onExpandedHeightChanged: @escaping (CGFloat) -> Void
    ) {
        self.panel = panel
        self.roundsBottom = roundsBottom
        self.listMaxHeight = listMaxHeight
        self.onGroupDragChanged = onGroupDragChanged
        self.onGroupDragEnded = onGroupDragEnded
        self.onExpandedHeightChanged = onExpandedHeightChanged

        self.store = store
        self._appearance = StateObject(wrappedValue: PanelAppearanceSettings(panelId: panel.id, fallback: defaultColors))
    }

    private var palette: ScenePanelPalette { appearance.colors.palette(for: phase) }
    private var textColor: Color { palette.ink }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.85))

                Text(panel.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.9))

                if store.pinnedCount > 0 {
                    Text("\(store.pinnedCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(textColor.opacity(0.25)))
                        .help("置顶待办：\(store.pinnedCount)")
                        .accessibilityLabel("置顶待办：\(store.pinnedCount)")
                }

                Spacer()

                Button(action: { showGlassPicker.toggle() }) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.65))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("面板配色")
                .accessibilityLabel("面板配色")
                .popover(isPresented: $showGlassPicker, arrowEdge: .top) {
                    ScenePanelColorControls(colors: $appearance.colors)
                        .padding(14)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
                    .rotationEffect(.degrees(appearance.panelExpanded ? 180 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: appearance.panelExpanded)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            appearance.panelExpanded.toggle()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        onGroupDragChanged(value.translation)
                    }
                    .onEnded { value in
                        onGroupDragEnded(value.translation)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if appearance.panelExpanded {
                Divider().background(.white.opacity(0.15))

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.items) { item in
                                if store.pinnedCount > 0,
                                   item.id == store.items.first(where: { !$0.isPinned })?.id {
                                    Rectangle()
                                        .fill(textColor.opacity(0.12))
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .accessibilityHidden(true)
                                }

                                HStack(spacing: 0) {
                                    DragHandle(textColor: textColor) { translationY, globalY in
                                            handleItemDragChanged(
                                                itemId: item.id,
                                                translationY: translationY,
                                                globalY: globalY,
                                                scrollProxy: scrollProxy
                                            )
                                        } onDragEnded: {
                                            cancelledDragItemId = nil
                                            finishReorderDrag()
                                        }

                                    ToDoRow(item: item, onTogglePin: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            store.togglePin(item)
                                        }
                                    }, onToggleToday: {
                                        store.setInToday(!item.isInToday, id: item.id)
                                    }, onDelete: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            store.delete(id: item.id)
                                        }
                                    }, onEdit: { newText in
                                        store.update(item, newText: newText)
                                    })
                                }
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: RowFrameKey.self,
                                            value: [item.id: geo.frame(in: .global)]
                                        )
                                    }
                                )
                                .id(item.id.uuidString)
                                .offset(y: dragOffset(for: item.id))
                                .zIndex((draggingItemId == item.id || pendingDropItemId == item.id) ? 10 : 0)
                                .scaleEffect(draggingItemId == item.id ? 1.01 : 1)
                                .shadow(
                                    color: draggingItemId == item.id ? .black.opacity(0.14) : .clear,
                                    radius: draggingItemId == item.id ? 8 : 0,
                                    y: draggingItemId == item.id ? 2 : 0
                                )
                                .transaction { transaction in
                                    if draggingItemId == item.id {
                                        transaction.animation = nil
                                    }
                                }
                            }
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollViewportFrameKey.self,
                                value: geo.frame(in: .global)
                            )
                        }
                    )
                    .onPreferenceChange(RowFrameKey.self) { frames in
                        rowFrames = frames
                    }
                    .onPreferenceChange(ScrollViewportFrameKey.self) { frame in
                        scrollViewportFrame = frame
                    }
                }
                .frame(height: displayedExpandedHeight)
                .environment(\.todoTextColor, textColor)

                if !store.items.isEmpty {
                    Divider().background(.white.opacity(0.15))
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.5))

                    TextField("Add a task…", text: $newText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(textColor)
                        .focused($inputFocused)
                        .onSubmit {
                            store.add(newText)
                            newText = ""
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .taskPanelSurface(tint: palette.color, roundsBottom: roundsBottom)
        .environment(\.colorScheme, palette.colorScheme)
        .overlay(alignment: .bottom) {
            if appearance.panelExpanded {
                expandedHeightResizeHandle
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onReceive(store.willChangeStructure) {
            cancelledDragItemId = draggingItemId ?? cancelledDragItemId
            finishReorderDrag(animateDrop: false)
        }
        .onChange(of: appearance.panelExpanded) { _, expanded in
            if !expanded {
                cancelledDragItemId = nil
                finishReorderDrag(animateDrop: false)
            }
        }
        .onDisappear {
            cancelledDragItemId = nil
            finishReorderDrag(animateDrop: false)
        }
    }

    private var displayedExpandedHeight: CGFloat {
        min(max(listMaxHeight + liveExpandedHeightDelta, 80), 480)
    }

    private var expandedHeightResizeHandle: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(textColor.opacity(0.28))
                    .frame(width: 36, height: 3)
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        liveExpandedHeightDelta = value.translation.height
                    }
                    .onEnded { value in
                        let targetHeight = min(max(listMaxHeight + value.translation.height, 80), 480)
                        onExpandedHeightChanged(targetHeight)
                        liveExpandedHeightDelta = 0
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func handleItemDragChanged(
        itemId: UUID,
        translationY: CGFloat,
        globalY: CGFloat,
        scrollProxy: ScrollViewProxy
    ) {
        guard cancelledDragItemId != itemId else { return }
        if draggingItemId == nil {
            guard let index = store.items.firstIndex(where: { $0.id == itemId }) else { return }
            draggingItemId = itemId
            pendingDropItemId = nil
            latestDragGlobalY = globalY
            dragDisplayOffsetY = 0
            initialDragIndex = index
            currentDragIndex = index
            lastChangeItemId = nil
        }

        guard draggingItemId == itemId else { return }

        withTransaction(Transaction(animation: nil)) {
            dragDisplayOffsetY = translationY
        }
        latestDragGlobalY = globalY

        checkIntersection(at: globalY)
        updateAutoScrollState(for: globalY, scrollProxy: scrollProxy)
    }

    private func dragOffset(for itemId: UUID) -> CGFloat {
        guard draggingItemId == itemId else { return 0 }
        return dragDisplayOffsetY + positionOffsetForDraggedItem()
    }

    private func positionOffsetForDraggedItem() -> CGFloat {
        guard draggingItemId != nil,
              let initialDragIndex,
              let currentDragIndex,
              !store.items.isEmpty,
              store.items.indices.contains(initialDragIndex),
              store.items.indices.contains(currentDragIndex) else {
            return 0
        }

        if currentDragIndex > initialDragIndex {
            return store.items[initialDragIndex..<currentDragIndex].reduce(CGFloat.zero) { offset, item in
                offset - (rowFrames[item.id]?.height ?? 0)
            }
        } else if currentDragIndex < initialDragIndex {
            return store.items[(currentDragIndex + 1)...initialDragIndex].reduce(CGFloat.zero) { offset, item in
                offset + (rowFrames[item.id]?.height ?? 0)
            }
        }

        return 0
    }

    private func checkIntersection(at pointerY: CGFloat) {
        guard let draggingItemId,
              let currentDragIndex,
              let draggedItem = store.items.first(where: { $0.id == draggingItemId }) else {
            return
        }

        let intersectedItem = store.items.first { item in
            guard item.id != draggingItemId,
                  item.isPinned == draggedItem.isPinned,
                  let frame = rowFrames[item.id],
                  !frame.isEmpty else {
                return false
            }
            return pointerY >= frame.minY && pointerY <= frame.maxY
        }

        guard let intersectedItem,
              let targetIndex = store.items.firstIndex(where: { $0.id == intersectedItem.id }),
              let targetFrame = rowFrames[intersectedItem.id] else {
            lastChangeItemId = nil
            return
        }

        guard hasCrossedSwapThreshold(
            currentIndex: currentDragIndex,
            targetIndex: targetIndex,
            targetFrame: targetFrame,
            pointerY: pointerY
        ) else {
            return
        }

        if lastChangeItemId == intersectedItem.id,
           notAtOtherEdge(
                currentIndex: currentDragIndex,
                targetIndex: targetIndex,
                targetFrame: targetFrame,
                pointerY: pointerY
           ) {
            return
        }

        lastChangeItemId = intersectedItem.id
        moveDraggedItem(from: currentDragIndex, to: targetIndex)
    }

    private func hasCrossedSwapThreshold(
        currentIndex: Int,
        targetIndex: Int,
        targetFrame: CGRect,
        pointerY: CGFloat
    ) -> Bool {
        guard !targetFrame.isEmpty else { return false }

        let midY = targetFrame.midY
        if targetIndex > currentIndex {
            return pointerY >= midY
        } else if targetIndex < currentIndex {
            return pointerY <= midY
        }

        return false
    }

    private func notAtOtherEdge(
        currentIndex: Int,
        targetIndex: Int,
        targetFrame: CGRect,
        pointerY: CGFloat
    ) -> Bool {
        guard !targetFrame.isEmpty else {
            return true
        }

        let edgeBumper = min(max(targetFrame.height * 0.45, 8), swapEdgeBumper)
        if currentIndex > targetIndex {
            let upperBandMax = min(targetFrame.minY + edgeBumper, targetFrame.maxY)
            let isInUpperBand = pointerY >= targetFrame.minY && pointerY <= upperBandMax
            return !isInUpperBand
        } else {
            let lowerBandMin = max(targetFrame.maxY - edgeBumper, targetFrame.minY)
            let isInLowerBand = pointerY <= targetFrame.maxY && pointerY >= lowerBandMin
            return !isInLowerBand
        }
    }

    private func moveDraggedItem(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              store.items.indices.contains(fromIndex),
              store.items.indices.contains(toIndex) else {
            return
        }

        var moved = false
        withAnimation(.easeInOut(duration: 0.14)) {
            moved = store.move(from: fromIndex, to: toIndex)
        }
        if moved {
            currentDragIndex = toIndex
        }
    }

    private func updateAutoScrollState(for globalY: CGFloat, scrollProxy: ScrollViewProxy) {
        guard draggingItemId != nil, !scrollViewportFrame.isEmpty else {
            stopAutoScroll()
            return
        }

        if globalY <= scrollViewportFrame.minY + autoScrollHotZoneHeight {
            startAutoScroll(direction: .up, scrollProxy: scrollProxy)
        } else if globalY >= scrollViewportFrame.maxY - autoScrollHotZoneHeight {
            startAutoScroll(direction: .down, scrollProxy: scrollProxy)
        } else {
            stopAutoScroll()
        }
    }

    private func performAutoScrollStep(direction: ToDoAutoScrollDirection, scrollProxy: ScrollViewProxy) {
        guard let draggingItemId,
              let fromIndex = currentDragIndex ?? store.items.firstIndex(where: { $0.id == draggingItemId }) else {
            return
        }

        let targetIndex = direction == .up ? (fromIndex - 1) : (fromIndex + 1)
        guard store.items.indices.contains(targetIndex) else {
            withAnimation(.linear(duration: autoScrollTickInterval)) {
                scrollProxy.scrollTo(draggingItemId.uuidString, anchor: direction.anchor)
            }
            return
        }

        let crossedItemId = store.items[targetIndex].id
        let crossedHeight = rowFrames[crossedItemId]?.height ?? 0
        var moved = false
        withTransaction(Transaction(animation: .linear(duration: autoScrollTickInterval))) {
            moved = store.move(from: fromIndex, to: targetIndex)
        }
        guard moved else {
            stopAutoScroll()
            scrollProxy.scrollTo(draggingItemId.uuidString, anchor: direction.anchor)
            return
        }
        currentDragIndex = targetIndex
        lastChangeItemId = crossedItemId

        if crossedHeight > 0 {
            withTransaction(Transaction(animation: nil)) {
                switch direction {
                case .up:
                    dragDisplayOffsetY -= crossedHeight
                case .down:
                    dragDisplayOffsetY += crossedHeight
                }
            }
        }

        withAnimation(.linear(duration: autoScrollTickInterval)) {
            scrollProxy.scrollTo(draggingItemId.uuidString, anchor: direction.anchor)
        }

        if let latestDragGlobalY {
            checkIntersection(at: latestDragGlobalY)
        }
    }

    private func startAutoScroll(direction: ToDoAutoScrollDirection, scrollProxy: ScrollViewProxy) {
        guard draggingItemId != nil else { return }

        if autoScrollDirection == direction, autoScrollTimer != nil {
            return
        }

        stopAutoScroll()
        autoScrollDirection = direction

        let timer = Timer(timeInterval: autoScrollTickInterval, repeats: true) { _ in
            if NSEvent.pressedMouseButtons == 0 {
                finishReorderDrag()
                return
            }
            performAutoScrollStep(direction: direction, scrollProxy: scrollProxy)
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDirection = nil
    }

    private func finishReorderDrag(animateDrop: Bool = true) {
        stopAutoScroll()
        let droppedItemId = draggingItemId

        pendingDropItemId = animateDrop ? droppedItemId : nil

        withAnimation(.easeOut(duration: 0.14)) {
            draggingItemId = nil
            latestDragGlobalY = nil
            dragDisplayOffsetY = 0
            initialDragIndex = nil
            currentDragIndex = nil
            lastChangeItemId = nil
        }

        guard animateDrop, let droppedItemId else {
            pendingDropItemId = nil
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if pendingDropItemId == droppedItemId, draggingItemId == nil {
                pendingDropItemId = nil
            }
        }
    }
}

private enum ToDoAutoScrollDirection {
    case up
    case down

    var anchor: UnitPoint {
        switch self {
        case .up:
            return .top
        case .down:
            return .bottom
        }
    }
}
