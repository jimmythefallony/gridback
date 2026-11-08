import GridBackCore
import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var model: GridBackModel
    @State private var reorder: GridReorderSession?
    @State private var finger: CGPoint = .zero
    @State private var blockLaunch = false
    @State private var visualPage: CGFloat = 0
    @State private var isSwiping = false
    @State private var suppressPageAnimation = false
    @State private var swipe = PageDragTracker()
    @State private var hoverTarget: String?
    @State private var hoverStarted: TimeInterval?
    @State private var armedTarget: String?
    @State private var highlightTarget: String?
    @State private var dragLayout: LaunchGridLayout?
    @StateObject private var armClock = ArmClock()
    @StateObject private var pointerHandoff = PointerHandoff()
    @State private var folderDragID: String?
    @State private var folderHandoff = false
    @State private var dragSettled = false
    @State private var folderPanel = CGRect.zero
    @State private var folderIconFrames: [String: CGRect] = [:]
    @State private var gridChromeVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { overlay in
            let metrics = model.layout.metrics.clamped
            let chrome = LaunchGridLayout.make(
                overlayWidth: overlay.size.width,
                overlayHeight: overlay.size.height,
                columns: metrics.columns,
                rows: metrics.rows,
                reserve: model.screenReserve
            )
            let pages = reorder?.preview.pages ?? model.layout.pages
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.openFolderID == nil && reorder == nil && folderDragID == nil {
                            model.hideOverlay()
                        }
                    }

                Group {
                    if model.isScanning && model.appsByID.isEmpty {
                        Text(String(localized: "Looking for apps…"))
                            .font(.title3)
                            .foregroundStyle(.white)
                    } else if pages.isEmpty && !model.isSearching {
                        Text(String(localized: "No apps found in Applications, System Applications, or your home Applications folder."))
                            .font(.title3)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    } else if model.isSearching {
                        SearchResultsView(model: model, layout: chrome)
                            .padding(.top, chrome.topChrome)
                            .padding(.bottom, chrome.bottomChrome)
                            .padding(.leading, chrome.originX)
                            .padding(.trailing, max(0, chrome.pageWidth - chrome.originX - chrome.gridWidth))
                    } else {
                        pageStrip(pages: pages, layout: chrome)
                            .frame(width: chrome.pageWidth, height: chrome.gridHeight)
                            .position(
                                x: overlay.size.width / 2,
                                y: chrome.originY + chrome.gridHeight / 2
                            )
                    }
                }
                .opacity(gridChromeVisible ? 1 : 0)

                SearchPill(query: searchQueryBinding)
                    .position(x: chrome.contentCenterX, y: chrome.searchCenterY)
                    .opacity(gridChromeVisible ? 1 : 0)

                if !model.isSearching && !pages.isEmpty {
                    PageControls(pageCount: pages.count, position: visualPage) { page in
                        turnToPage(page)
                    }
                    .position(x: chrome.contentCenterX, y: chrome.pageControlCenterY)
                    .opacity(gridChromeVisible ? 1 : 0)
                }

                if let folderID = model.openFolderID, let folder = model.layout.folder(folderID) {
                    FolderCover(
                        model: model,
                        folder: folder,
                        layout: chrome,
                        tileCenter: folderTileCenter(folderID, layout: chrome, overlaySize: overlay.size),
                        reduceMotion: reduceMotion,
                        collapse: folderHandoff,
                        suppressLaunch: blockLaunch,
                        gridChromeVisible: $gridChromeVisible,
                        iconFrames: $folderIconFrames,
                        panelFrame: $folderPanel,
                        hiddenID: folderDragID
                    )
                }

                if reorder != nil || folderDragID != nil {
                    draggedTile((reorder?.appID ?? folderDragID) ?? "", iconSide: chrome.iconSide)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .position(finger)
                        .allowsHitTesting(false)
                }

                if let warning = model.persistenceWarning {
                    banner(warning, color: Color.orange.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(18, model.screenReserve.top + 8))
                }

                if let launchError = model.launchError {
                    banner(launchError, color: Color.red.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, max(72, model.screenReserve.bottom + 24))
                }
            }
            .coordinateSpace(name: "overlay")
            .simultaneousGesture(reorderGesture(layout: chrome))
            .background {
                ScrollCatcher(isEnabled: reorder == nil && !model.isSearching && model.openFolderID == nil) { event in
                    handleScroll(event, pageWidth: chrome.pageWidth, pageCount: model.layout.pages.count)
                }
            }
            .onAppear {
                visualPage = CGFloat(model.currentPage)
            }
            .onChange(of: armClock.tick) { _, _ in
                guard reorder != nil, let dragLayout else { return }
                updateReorder(at: finger, layout: dragLayout)
            }
            .onChange(of: displayedPage) { _, newPage in
                guard !isSwiping, !suppressPageAnimation else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    visualPage = CGFloat(newPage)
                }
            }
            .onChange(of: model.openFolderID) { _, id in
                if id == nil {
                    gridChromeVisible = true
                }
            }
        }
    }

    private var displayedPage: Int {
        reorder?.page ?? model.currentPage
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { model.searchQuery },
            set: { model.setSearchQuery($0) }
        )
    }

    private func pageStrip(pages: [[GridBackCore.GridItem]], layout: LaunchGridLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(pages.indices, id: \.self) { index in
                AppGridView(
                    model: model,
                    layout: layout,
                    items: pages[index],
                    hiddenID: reorder?.appID,
                    hiddenFolderID: model.openFolderID,
                    armedID: highlightTarget,
                    blockLaunch: blockLaunch
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: -visualPage * layout.pageWidth)
        .frame(width: layout.pageWidth, height: layout.gridHeight, alignment: .leading)
    }

    private func reorderGesture(layout: LaunchGridLayout) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("overlay"))
            .onChanged { value in
                if folderHandoff {
                    finger = value.location
                    dragLayout = layout
                    updateReorder(at: value.location, layout: layout)
                    return
                }
                if model.openFolderID != nil {
                    trackFolderDrag(value, layout: layout)
                    return
                }
                guard !model.isSearching, !isSwiping else { return }
                if reorder == nil {
                    guard let id = iconID(at: value.startLocation, layout: layout) else { return }
                    reorder = GridReorderSession(
                        appID: id,
                        layout: model.layout,
                        page: model.currentPage
                    )
                    hoverTarget = nil
                    hoverStarted = nil
                    armedTarget = nil
                    highlightTarget = nil
                    blockLaunch = true
                    armClock.start()
                }
                dragLayout = layout
                finger = value.location
                updateReorder(at: value.location, layout: layout)
            }
            .onEnded { _ in
                if folderDragID != nil && !folderHandoff {
                    clearFolderDrag()
                    return
                }
                if folderHandoff {
                    if pointerHandoff.isTracking { return }
                    finishHandoff()
                    return
                }
                armClock.stop()
                if let reorder {
                    if let armedTarget {
                        model.group(draggedAppID: reorder.appID, targetID: armedTarget)
                    } else {
                        model.commitReorder(reorder.preview, page: reorder.page)
                    }
                }
                reorder = nil
                hoverTarget = nil
                hoverStarted = nil
                armedTarget = nil
                highlightTarget = nil
                DispatchQueue.main.async {
                    blockLaunch = false
                }
            }
    }

    private func updateReorder(at point: CGPoint, layout: LaunchGridLayout) {
        guard var session = reorder else { return }
        let edge = GridDragResolver.pageEdge(
            x: Double(point.x),
            overlayWidth: layout.pageWidth,
            leading: model.screenReserve.left,
            trailing: model.screenReserve.right
        )
        let slot = edge == nil ? layout.hitSlot(x: Double(point.x), y: Double(point.y)) : nil
        let pageItems = session.preview.pages.indices.contains(session.page) ? session.preview.pages[session.page] : []
        let occupant = slot.flatMap { slot -> String? in
            guard pageItems.indices.contains(slot) else { return nil }
            let id = pageItems[slot].id
            return id == session.appID ? nil : id
        }
        let now = Date().timeIntervalSinceReferenceDate
        if occupant != hoverTarget {
            hoverTarget = occupant
            hoverStarted = occupant == nil ? nil : now
        }
        let dwell = hoverStarted.map { now - $0 } ?? 0
        let overCenter = slot.map { layout.isOverIconCenter(x: Double(point.x), y: Double(point.y), slot: $0) } ?? false
        if edge != nil {
            highlightTarget = nil
            armedTarget = nil
            hoverTarget = nil
            hoverStarted = nil
            session.hover(slot: nil, edge: edge)
        } else {
            switch DragArbitration.resolve(
                draggedID: session.appID,
                draggedIsFolder: model.layout.folder(session.appID) != nil,
                items: pageItems,
                slot: slot,
                overIconCenter: overCenter,
                dwellSeconds: dwell
            ) {
            case .hold(let targetID, let armed):
                highlightTarget = targetID
                armedTarget = armed ? targetID : nil
            case .reorder:
                highlightTarget = nil
                armedTarget = nil
                let reorderSlot = slot ?? layout.insertionSlot(
                    x: Double(point.x),
                    y: Double(point.y),
                    itemCount: pageItems.count
                )
                session.hover(slot: reorderSlot, edge: nil)
            }
        }
        reorder = session
    }

    private func iconID(at point: CGPoint, layout: LaunchGridLayout) -> String? {
        guard let slot = layout.hitSlot(x: Double(point.x), y: Double(point.y)) else { return nil }
        let pages = model.layout.pages
        let page = min(model.currentPage, max(pages.count - 1, 0))
        guard pages.indices.contains(page), slot < pages[page].count else { return nil }
        return pages[page][slot].id
    }

    private func handleScroll(_ event: NSEvent, pageWidth: Double, pageCount: Int) -> Bool {
        guard model.isOverlayVisible, !model.isSearching, reorder == nil, pageCount > 0 else {
            swipe.reset()
            return false
        }
        guard event.hasPreciseScrollingDeltas else { return false }
        if event.momentumPhase != [] {
            return true
        }
        let phase = event.phase
        if phase.contains(.cancelled) {
            swipe.reset()
            settle(on: model.currentPage)
            return true
        }
        if phase.contains(.began) {
            swipe.reset()
            isSwiping = true
        }
        if phase.contains(.began) || phase.contains(.changed) || phase.contains(.stationary) {
            swipe.add(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY), time: event.timestamp)
            guard swipe.isMostlyHorizontal || abs(swipe.translationX) > 12 else { return true }
            isSwiping = true
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visualPage = PageSnap.visualPage(
                    currentPage: model.currentPage,
                    pageCount: pageCount,
                    translationX: swipe.translationX,
                    pageWidth: pageWidth
                )
            }
            return true
        }
        if phase.contains(.ended) {
            let destination = swipe.isMostlyHorizontal
                ? PageSnap.destination(
                    currentPage: model.currentPage,
                    pageCount: pageCount,
                    translationX: swipe.translationX,
                    velocityX: swipe.velocityX(),
                    pageWidth: pageWidth
                )
                : model.currentPage
            swipe.reset()
            settle(on: destination)
            return true
        }
        return false
    }

    private func trackFolderDrag(_ value: DragGesture.Value, layout: LaunchGridLayout) {
        if folderDragID == nil {
            guard let id = folderIconFrames.first(where: { $0.value.contains(value.startLocation) })?.key else { return }
            folderDragID = id
            dragSettled = false
            blockLaunch = true
            pointerHandoff.onMove = { [self] point in
                finger = point
                dragLayout = layout
                if folderHandoff {
                    updateReorder(at: point, layout: layout)
                } else {
                    beginFolderHandoffIfNeeded(at: point, layout: layout)
                }
            }
            pointerHandoff.onUp = { [self] _ in
                if folderHandoff {
                    finishHandoff()
                } else {
                    clearFolderDrag()
                }
            }
            pointerHandoff.start()
        }
        finger = value.location
        dragLayout = layout
        beginFolderHandoffIfNeeded(at: value.location, layout: layout)
    }

    private func beginFolderHandoffIfNeeded(at point: CGPoint, layout: LaunchGridLayout) {
        guard let id = folderDragID, !folderHandoff, folderPanel != .zero else { return }
        let left = FolderPanelExit.hasLeft(
            x: Double(point.x),
            y: Double(point.y),
            minX: Double(folderPanel.minX),
            minY: Double(folderPanel.minY),
            maxX: Double(folderPanel.maxX),
            maxY: Double(folderPanel.maxY)
        )
        guard left else { return }
        let page = min(model.currentPage, max(model.layout.pages.count - 1, 0))
        let count = model.layout.pages.indices.contains(page) ? model.layout.pages[page].count : 0
        let slot = layout.insertionSlot(x: Double(point.x), y: Double(point.y), itemCount: count) ?? count
        let extracted = FolderEditing.moveAppOut(layout: model.layout, appID: id, toPage: page, toSlot: slot)
        folderHandoff = true
        reorder = GridReorderSession(appID: id, layout: extracted, page: page)
        updateReorder(at: point, layout: layout)
    }

    private func finishHandoff() {
        guard folderHandoff, !dragSettled else { return }
        dragSettled = true
        pointerHandoff.stop()
        if let reorder {
            model.commitReorder(reorder.preview, page: reorder.page)
        }
        reorder = nil
        clearFolderDrag()
        armClock.stop()
    }

    private func clearFolderDrag() {
        folderDragID = nil
        folderHandoff = false
        pointerHandoff.stop()
        DispatchQueue.main.async {
            blockLaunch = false
        }
    }

    private func folderTileCenter(_ id: String, layout: LaunchGridLayout, overlaySize: CGSize) -> CGPoint {
        guard let path = model.layout.indexPath(of: id), path.page == model.currentPage else {
            return CGPoint(x: overlaySize.width / 2, y: overlaySize.height / 2)
        }
        let pageLeft = overlaySize.width / 2 - layout.pageWidth / 2
        let pageTop = layout.originY
        let iconLift = (layout.labelHeight + layout.iconLabelGap) / 2
        return CGPoint(
            x: pageLeft + layout.originX + layout.columnCenter(path.slot),
            y: pageTop + layout.rowCenter(path.slot) - iconLift
        )
    }

    private func draggedTile(_ id: String, iconSide: CGFloat) -> some View {
        if let folder = model.layout.folder(id) {
            return AnyView(
                FolderTile(
                    name: folder.name,
                    icons: folder.appIDs.prefix(9).map { model.iconImages[$0] },
                    iconSide: iconSide,
                    labelWidth: iconSide + 24,
                    armed: false
                ) {}
            )
        }
        return AnyView(
            AppIconButton(
                title: model.appsByID[id]?.displayName ?? id,
                image: model.iconImages[id],
                iconSide: iconSide
            ) {}
        )
    }

    private func turnToPage(_ page: Int) {
        guard model.openFolderID == nil, !model.layout.pages.isEmpty else { return }
        let clamped = min(max(page, 0), model.layout.pages.count - 1)
        isSwiping = false
        swipe.reset()
        model.selectPage(clamped)
    }

    private func settle(on page: Int) {
        withAnimation(.easeOut(duration: 0.35)) {
            visualPage = CGFloat(page)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            suppressPageAnimation = true
            isSwiping = false
            model.selectPage(page)
            visualPage = CGFloat(page)
            DispatchQueue.main.async {
                suppressPageAnimation = false
            }
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color, in: Capsule())
            .shadow(radius: 8, y: 2)
    }
}

private final class PointerHandoff: ObservableObject {
    var onMove: ((CGPoint) -> Void)?
    var onUp: ((CGPoint) -> Void)?
    private var monitor: Any?
    var isTracking: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let window = event.window else { return event }
            let height = window.contentView?.bounds.height ?? window.frame.height
            let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
            if event.type == .leftMouseUp {
                self.onUp?(point)
                self.stop()
            } else {
                self.onMove?(point)
            }
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private final class ArmClock: ObservableObject {
    @Published private(set) var tick = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick += 1
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private struct FolderCover: View {
    @ObservedObject var model: GridBackModel
    var folder: AppFolder
    var layout: LaunchGridLayout
    var tileCenter: CGPoint
    var reduceMotion: Bool
    var collapse: Bool
    var suppressLaunch: Bool
    @Binding var gridChromeVisible: Bool
    @Binding var iconFrames: [String: CGRect]
    @Binding var panelFrame: CGRect
    var hiddenID: String?
    @State private var name: String = ""
    @State private var revealed = false
    @State private var titleShown = false
    @State private var closing = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        GeometryReader { overlay in
            let center = CGPoint(x: overlay.size.width / 2, y: overlay.size.height / 2)
            let metrics = FolderPanelMetrics.openMetrics(
                overlayWidth: overlay.size.width,
                preferredIcon: layout.iconSide,
                appCount: folder.appIDs.count
            )
            let progress = revealed ? 1.0 : 0.0
            let shape = FolderPanelMetrics.shape(
                progress: progress,
                tileSide: layout.iconSide,
                tileCenterX: tileCenter.x,
                tileCenterY: tileCenter.y,
                open: metrics,
                openCenterX: center.x,
                openCenterY: center.y
            )
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { beginClose() }
                card(metrics: metrics, shape: shape, progress: progress)
                    .position(x: shape.centerX, y: shape.centerY)
                title
                    .position(x: center.x, y: center.y - metrics.height / 2 - 28)
                    .opacity(titleShown ? 1 : 0)
            }
            .allowsHitTesting(!collapse)
        }
        .onChange(of: collapse) { _, shouldCollapse in
            if shouldCollapse { beginClose() }
        }
        .onAppear {
            name = folder.name
            guard !closing else { return }
            if reduceMotion {
                revealed = true
                titleShown = true
                gridChromeVisible = false
            } else {
                withAnimation(.easeOut(duration: 0.42)) {
                    revealed = true
                }
                withAnimation(.easeOut(duration: 0.3)) {
                    titleShown = true
                    gridChromeVisible = false
                }
            }
        }
    }

    private var title: some View {
        TextField(AppFolder.defaultName, text: $name)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(maxWidth: 280)
            .focused($nameFocused)
            .onSubmit { commitName() }
            .onDisappear { commitName() }
    }

    private func card(metrics: FolderOpenMetrics, shape: FolderContainerShape, progress: Double) -> some View {
        let radius = shape.cornerRadius
        return ZStack(alignment: .topLeading) {
            ForEach(Array(folder.appIDs.enumerated()), id: \.element) { index, id in
                let icon = FolderPanelMetrics.iconBox(
                    index: index,
                    appCount: folder.appIDs.count,
                    progress: progress,
                    tileSide: layout.iconSide,
                    open: metrics
                )
                let shown = id != hiddenID && (index < 9 || progress > 0.01)
                Button {
                    guard hiddenID == nil, !suppressLaunch else { return }
                    model.launch(id: id)
                } label: {
                    iconImage(model.iconImages[id], side: icon.side)
                }
                .buttonStyle(GridPlainButtonStyle())
                .position(x: icon.centerX, y: icon.centerY)
                .opacity(shown ? 1 : 0)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: FolderIconFramesKey.self,
                            value: [id: geo.frame(in: .named("overlay"))]
                        )
                    }
                }
                Text(model.appsByID[id]?.displayName ?? id)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: max(icon.side + 12, 64))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .position(x: icon.centerX, y: icon.centerY + icon.side / 2 + 18)
                    .opacity(id == hiddenID ? 0 : progress)
            }
        }
        .frame(width: shape.width, height: shape.height)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.24))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: FolderPanelFrameKey.self,
                    value: geo.frame(in: .named("overlay"))
                )
            }
        }
        .onPreferenceChange(FolderIconFramesKey.self) { iconFrames = $0 }
        .onPreferenceChange(FolderPanelFrameKey.self) { panelFrame = $0 }
    }

    private func iconImage(_ image: NSImage?, side: Double) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: side * 0.55))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: side, height: side)
    }

    private func beginClose() {
        guard !closing else { return }
        closing = true
        if reduceMotion {
            gridChromeVisible = true
            model.closeFolder()
            return
        }
        let showGridWhileClosing = collapse
        withAnimation(.easeInOut(duration: 0.46), completionCriteria: .logicallyComplete) {
            revealed = false
            titleShown = false
            if showGridWhileClosing {
                gridChromeVisible = true
            }
        } completion: {
            gridChromeVisible = true
            model.closeFolder()
        }
    }

    private func commitName() {
        model.renameFolder(folder.id, to: name)
        nameFocused = false
    }
}

private struct FolderIconFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct FolderPanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct ScrollCatcher: NSViewRepresentable {
    var isEnabled: Bool
    var onEvent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.isEnabled = isEnabled
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ view: ScrollCatcherView, context: Context) {
        view.isEnabled = isEnabled
        view.onEvent = onEvent
    }
}

private final class ScrollCatcherView: NSView {
    var isEnabled = true
    var onEvent: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isEnabled, let onEvent = self.onEvent, onEvent(event) else {
                return event
            }
            return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
