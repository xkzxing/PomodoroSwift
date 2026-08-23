//
//  ToDoView.swift
//  PomodoroSwift
//

import SwiftUI
import Combine

struct ToDoView: View {
    let panel: ToDoPanel
    let containerSize: CGSize
    @StateObject private var store: ToDoStore
    @StateObject private var glassSettings: ToDoGlassSettings
    @EnvironmentObject private var settings: Settings
    @State private var newText: String = ""
    @FocusState private var inputFocused: Bool

    @State private var draggingItemId: UUID?
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

    var glassEffect: Glass
    var listMaxHeight: CGFloat

    @State private var showGlassPicker: Bool = false

    @State private var liveDragOffset: CGSize = .zero
    @State private var liveExtraSize: CGSize = .zero
    @State private var panelOffsetX: Double = 0
    @State private var panelOffsetY: Double = 0
    @State private var panelExtraHeight: Double = 0
    @State private var panelExtraWidth: Double = 0
    @State private var didLoadPanelLayout = false
    @State private var measuredPanelSize: CGSize = .zero
    @State private var dragPreviewOffset: CGSize?
    @State private var isDraggingPanel = false
    @State private var isResizingPanel = false

    private let basePanelWidth: Double = 280
    private let minPanelWidth: Double = 200
    private let defaultExtraWidth: Double = 0
    private let defaultExtraHeight: Double = 0
    private let gridStep: CGFloat = 24
    private let minListHeight: CGFloat = 44
    private let fallbackExpandedPanelHeight: CGFloat = 220
    private let fallbackCollapsedPanelHeight: CGFloat = 56
    private let autoScrollHotZoneHeight: CGFloat = 32
    private let autoScrollTickInterval: TimeInterval = 0.06
    private let swapEdgeBumper: CGFloat = 18

    init(panel: ToDoPanel, containerSize: CGSize, glassEffect: Glass, listMaxHeight: CGFloat = 180) {
        self.panel = panel
        self.containerSize = containerSize
        self.glassEffect = glassEffect
        self.listMaxHeight = listMaxHeight

        self._store = StateObject(wrappedValue: ToDoStore(panelId: panel.id))
        self._glassSettings = StateObject(wrappedValue: ToDoGlassSettings(panelId: panel.id))
    }

    private var effectiveGlass: Glass {
        glassSettings.useCustom ? glassSettings.buildGlass() : glassEffect
    }

    private var widthChangeDuringDrag: CGFloat {
        let currentDisplayWidth = max(basePanelWidth + panelExtraWidth, minPanelWidth)
        let newDisplayWidth = max(basePanelWidth + panelExtraWidth + Double(liveExtraSize.width), minPanelWidth)
        return CGFloat(newDisplayWidth - currentDisplayWidth)
    }

    private var currentDisplayOffsetX: CGFloat {
        CGFloat(panelOffsetX) + liveDragOffset.width + widthChangeDuringDrag / 2
    }

    private var currentDisplayOffsetY: CGFloat {
        CGFloat(panelOffsetY) + liveDragOffset.height
    }

    private var currentDisplayWidth: CGFloat {
        CGFloat(max(basePanelWidth + panelExtraWidth + Double(liveExtraSize.width), minPanelWidth))
    }

    private var currentPanelHeightForPreview: CGFloat {
        measuredPanelSize.height > 0
            ? measuredPanelSize.height
            : (glassSettings.panelExpanded ? fallbackExpandedPanelHeight : fallbackCollapsedPanelHeight)
    }

    private var textColor: Color {
        let isDark = glassSettings.useCustom ? glassSettings.fontDark : !settings.sidebarDarkMode
        return isDark ? .black : .white
    }

    private func snapToGrid(_ value: CGFloat) -> CGFloat {
        (value / gridStep).rounded() * gridStep
    }

    private func snappedDisplayWidth(_ width: CGFloat) -> CGFloat {
        let snapped = snapToGrid(width)
        let snappedMin = ceil(CGFloat(minPanelWidth) / gridStep) * gridStep
        return max(snapped, snappedMin)
    }

    private func snappedListHeight(_ height: CGFloat) -> CGFloat {
        let snapped = snapToGrid(height)
        let snappedMin = ceil(minListHeight / gridStep) * gridStep
        return max(snapped, snappedMin)
    }

    private func clampedOffset(_ proposed: CGSize, panelSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return proposed
        }

        if visibleAreaRatio(of: proposed, panelSize: panelSize) >= 0.5 {
            return proposed
        }

        let minX = -containerSize.width / 2 + panelSize.width / 2
        let maxX = containerSize.width / 2 - panelSize.width / 2
        let minY: CGFloat = 0
        let maxY = containerSize.height - panelSize.height

        let clampedX: CGFloat
        if minX > maxX {
            clampedX = 0
        } else {
            clampedX = min(max(proposed.width, minX), maxX)
        }

        let clampedY: CGFloat
        if maxY < minY {
            clampedY = 0
        } else {
            clampedY = min(max(proposed.height, minY), maxY)
        }

        return CGSize(width: clampedX, height: clampedY)
    }

    private func visibleAreaRatio(of proposed: CGSize, panelSize: CGSize) -> CGFloat {
        guard panelSize.width > 0, panelSize.height > 0 else {
            return 1
        }

        let panelMinX = proposed.width - panelSize.width / 2
        let panelMaxX = proposed.width + panelSize.width / 2
        let panelMinY = proposed.height
        let panelMaxY = proposed.height + panelSize.height

        let containerMinX = -containerSize.width / 2
        let containerMaxX = containerSize.width / 2
        let containerMinY: CGFloat = 0
        let containerMaxY = containerSize.height

        let intersectionWidth = max(0, min(panelMaxX, containerMaxX) - max(panelMinX, containerMinX))
        let intersectionHeight = max(0, min(panelMaxY, containerMaxY) - max(panelMinY, containerMinY))
        let visibleArea = intersectionWidth * intersectionHeight
        let totalArea = panelSize.width * panelSize.height

        guard totalArea > 0 else { return 1 }
        return visibleArea / totalArea
    }

    private func snappedAndClampedOffset(_ proposed: CGSize, panelSize: CGSize) -> CGSize {
        let snapped = CGSize(
            width: snapToGrid(proposed.width),
            height: snapToGrid(proposed.height)
        )
        return clampedOffset(snapped, panelSize: panelSize)
    }

    private func normalizedExtraWidth(_ extraWidth: Double) -> Double {
        let displayWidth = max(basePanelWidth + extraWidth, minPanelWidth)
        let snapped = snappedDisplayWidth(CGFloat(displayWidth))
        return Double(snapped) - basePanelWidth
    }

    private func normalizedExtraHeight(_ extraHeight: Double) -> Double {
        let listHeight = max(listMaxHeight + CGFloat(extraHeight), minListHeight)
        let snapped = snappedListHeight(listHeight)
        return Double(snapped - listMaxHeight)
    }

    private func normalizedPanelSize(
        extraWidth: Double,
        extraHeight: Double
    ) -> CGSize {
        let width = CGFloat(max(basePanelWidth + extraWidth, minPanelWidth))
        let currentListHeight = max(listMaxHeight + CGFloat(panelExtraHeight), minListHeight)
        let targetListHeight = max(listMaxHeight + CGFloat(extraHeight), minListHeight)
        let listDelta = targetListHeight - currentListHeight
        let baseHeight = measuredPanelSize.height > 0
            ? measuredPanelSize.height
            : (glassSettings.panelExpanded ? fallbackExpandedPanelHeight : fallbackCollapsedPanelHeight)
        let minimumPanelHeight = glassSettings.panelExpanded ? (minListHeight + 80) : fallbackCollapsedPanelHeight
        let height = max(baseHeight + listDelta, minimumPanelHeight)
        return CGSize(width: width, height: height)
    }

    private func applyGridAndBoundsNormalization() {
        let snappedExtraWidth = normalizedExtraWidth(panelExtraWidth)
        let snappedExtraHeight = normalizedExtraHeight(panelExtraHeight)
        let targetSize = normalizedPanelSize(
            extraWidth: snappedExtraWidth,
            extraHeight: snappedExtraHeight
        )
        let snappedOffset = snappedAndClampedOffset(
            CGSize(width: panelOffsetX, height: panelOffsetY),
            panelSize: targetSize
        )

        var changed = false
        if panelExtraWidth != snappedExtraWidth {
            panelExtraWidth = snappedExtraWidth
            changed = true
        }
        if panelExtraHeight != snappedExtraHeight {
            panelExtraHeight = snappedExtraHeight
            changed = true
        }
        if panelOffsetX != Double(snappedOffset.width) {
            panelOffsetX = Double(snappedOffset.width)
            changed = true
        }
        if panelOffsetY != Double(snappedOffset.height) {
            panelOffsetY = Double(snappedOffset.height)
            changed = true
        }

        if changed {
            persistPanelLayout()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.85))

                Text(panel.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.9))

                let remaining = store.items.filter { !$0.isDone }.count
                if remaining > 0 {
                    Text("\(remaining)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(textColor.opacity(0.25)))
                }

                Spacer()

                Button(action: { showGlassPicker.toggle() }) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(glassSettings.useCustom ? 0.85 : 0.45))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGlassPicker, arrowEdge: .top) {
                    ToDoGlassPopover(glassSettings: glassSettings, onResetLayout: resetPanelLayout)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.6))
                    .rotationEffect(.degrees(glassSettings.panelExpanded ? 180 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: glassSettings.panelExpanded)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            glassSettings.panelExpanded.toggle()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        isDraggingPanel = true
                        liveDragOffset = value.translation
                        let proposedOffset = CGSize(
                            width: panelOffsetX + value.translation.width,
                            height: panelOffsetY + value.translation.height
                        )
                        let panelSize = CGSize(
                            width: CGFloat(max(basePanelWidth + panelExtraWidth, minPanelWidth)),
                            height: currentPanelHeightForPreview
                        )
                        dragPreviewOffset = snappedAndClampedOffset(proposedOffset, panelSize: panelSize)
                    }
                    .onEnded { value in
                        let proposedOffset = CGSize(
                            width: panelOffsetX + value.translation.width,
                            height: panelOffsetY + value.translation.height
                        )
                        let panelSize = CGSize(
                            width: CGFloat(max(basePanelWidth + panelExtraWidth, minPanelWidth)),
                            height: currentPanelHeightForPreview
                        )
                        let snappedOffset = snappedAndClampedOffset(proposedOffset, panelSize: panelSize)
                        panelOffsetX = Double(snappedOffset.width)
                        panelOffsetY = Double(snappedOffset.height)
                        liveDragOffset = .zero
                        dragPreviewOffset = nil
                        isDraggingPanel = false
                        persistPanelLayout()
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    resetPanelSize()
                }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if glassSettings.panelExpanded {
                Divider().background(.white.opacity(0.15))

                let computedHeight = max(listMaxHeight + CGFloat(panelExtraHeight) + liveExtraSize.height, 44)
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.items) { item in
                                HStack(spacing: 0) {
                                    DragHandle(textColor: textColor) { translationY, globalY in
                                            handleItemDragChanged(
                                                itemId: item.id,
                                                translationY: translationY,
                                                globalY: globalY,
                                                scrollProxy: scrollProxy
                                            )
                                        } onDragEnded: {
                                            finishReorderDrag()
                                        }

                                    ToDoRow(item: item, onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            store.toggle(item)
                                        }
                                    }, onDelete: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if let idx = store.items.firstIndex(where: { $0.id == item.id }) {
                                                store.delete(at: IndexSet(integer: idx))
                                            }
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
                .frame(height: computedHeight)
                .environment(\.todoTextColor, textColor)

                if !store.items.isEmpty {
                    Divider().background(.white.opacity(0.15))
                }

                ZStack(alignment: .bottomTrailing) {
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
                    .padding(.trailing, 20)

                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(textColor.opacity(0.3))
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    isResizingPanel = true
                                    liveExtraSize = value.translation
                                }
                                .onEnded { value in
                                    let oldDisplayWidth = CGFloat(max(basePanelWidth + panelExtraWidth, minPanelWidth))
                                    let oldListHeight = max(listMaxHeight + CGFloat(panelExtraHeight), minListHeight)

                                    let proposedDisplayWidth = oldDisplayWidth + value.translation.width
                                    let snappedWidth = snappedDisplayWidth(proposedDisplayWidth)
                                    let newExtraWidth = Double(snappedWidth) - basePanelWidth

                                    let proposedListHeight = oldListHeight + value.translation.height
                                    let snappedList = snappedListHeight(proposedListHeight)
                                    let newExtraHeight = Double(snappedList - listMaxHeight)

                                    let deltaWidth = Double(snappedWidth - oldDisplayWidth)

                                    panelExtraHeight = newExtraHeight
                                    panelExtraWidth = newExtraWidth
                                    panelOffsetX += deltaWidth / 2

                                    let targetSize = normalizedPanelSize(
                                        extraWidth: panelExtraWidth,
                                        extraHeight: panelExtraHeight
                                    )
                                    let clamped = clampedOffset(
                                        CGSize(width: panelOffsetX, height: panelOffsetY),
                                        panelSize: targetSize
                                    )
                                    panelOffsetX = Double(clamped.width)
                                    panelOffsetY = Double(clamped.height)

                                    liveExtraSize = .zero
                                    isResizingPanel = false
                                    persistPanelLayout()
                                }
                        )
                        .onHover { hovering in
                            if hovering {
                                NSCursor.crosshair.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
            }
        }
        .frame(width: currentDisplayWidth)
        .contentShape(Rectangle())
        .background(.clear)
        .glassEffect(effectiveGlass, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: -4)
        .overlay {
            if let previewOffset = dragPreviewOffset {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        textColor.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .frame(width: currentDisplayWidth, height: currentPanelHeightForPreview)
                    .offset(
                        x: previewOffset.width - currentDisplayOffsetX,
                        y: previewOffset.height - currentDisplayOffsetY
                    )
                    .allowsHitTesting(false)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .offset(
            x: currentDisplayOffsetX,
            y: currentDisplayOffsetY
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
            }
        )
        .onAppear {
            loadPanelLayoutIfNeeded()
        }
        .onPreferenceChange(PanelSizeKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            measuredPanelSize = size
        }
        .onDisappear {
            finishReorderDrag()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetToDoPanel)) { notification in
            if let targetId = notification.userInfo?["panelId"] as? UUID, targetId == panel.id {
                let jitter = Double(panel.id.uuidString.first?.hexDigitValue ?? 0) * 5.0
                withAnimation(.spring()) {
                    panelOffsetX = 60 + jitter
                    panelOffsetY = 100 + jitter
                    panelExtraWidth = defaultExtraWidth
                    panelExtraHeight = defaultExtraHeight
                    liveDragOffset = .zero
                    liveExtraSize = .zero
                }
                applyGridAndBoundsNormalization()
            }
        }
    }

    private func loadPanelLayoutIfNeeded() {
        guard !didLoadPanelLayout else { return }
        panelOffsetX = glassSettings.offsetX
        panelOffsetY = glassSettings.offsetY
        panelExtraHeight = glassSettings.extraHeight
        panelExtraWidth = glassSettings.extraWidth
        didLoadPanelLayout = true
    }

    private func persistPanelLayout() {
        if glassSettings.offsetX != panelOffsetX {
            glassSettings.offsetX = panelOffsetX
        }
        if glassSettings.offsetY != panelOffsetY {
            glassSettings.offsetY = panelOffsetY
        }
        if glassSettings.extraHeight != panelExtraHeight {
            glassSettings.extraHeight = panelExtraHeight
        }
        if glassSettings.extraWidth != panelExtraWidth {
            glassSettings.extraWidth = panelExtraWidth
        }
    }

    private func resetPanelSize() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            panelExtraWidth = defaultExtraWidth
            panelExtraHeight = defaultExtraHeight
            liveExtraSize = .zero
        }
        applyGridAndBoundsNormalization()
    }

    private func resetPanelLayout() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            panelOffsetX = 0
            panelOffsetY = 0
            panelExtraWidth = defaultExtraWidth
            panelExtraHeight = defaultExtraHeight
            liveDragOffset = .zero
            liveExtraSize = .zero
        }
        applyGridAndBoundsNormalization()
    }

    private func handleItemDragChanged(
        itemId: UUID,
        translationY: CGFloat,
        globalY: CGFloat,
        scrollProxy: ScrollViewProxy
    ) {
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
              let currentDragIndex else {
            return
        }

        let intersectedItem = store.items.first { item in
            guard item.id != draggingItemId,
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

        let targetOffset = toIndex > fromIndex ? toIndex + 1 : toIndex
        withAnimation(.easeInOut(duration: 0.14)) {
            store.items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: targetOffset)
        }
        currentDragIndex = toIndex
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
        let targetOffset = targetIndex > fromIndex ? targetIndex + 1 : targetIndex

        withTransaction(Transaction(animation: .linear(duration: autoScrollTickInterval))) {
            store.items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: targetOffset)
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

    private func finishReorderDrag() {
        stopAutoScroll()
        let droppedItemId = draggingItemId

        if droppedItemId != nil {
            pendingDropItemId = droppedItemId
        }

        withAnimation(.easeOut(duration: 0.14)) {
            draggingItemId = nil
            latestDragGlobalY = nil
            dragDisplayOffsetY = 0
            initialDragIndex = nil
            currentDragIndex = nil
            lastChangeItemId = nil
        }

        guard let droppedItemId else {
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
