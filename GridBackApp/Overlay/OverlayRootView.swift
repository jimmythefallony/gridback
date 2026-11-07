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
    @State private var dragLayout: LaunchGridLayout?
    @StateObject private var armClock = ArmClock()

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
                        if model.openFolderID != nil {
                            model.closeFolder()
                        } else if reorder == nil {
                            model.hideOverlay()
                        }
                    }

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

                SearchPill(query: searchQueryBinding)
                    .position(x: chrome.contentCenterX, y: chrome.searchCenterY)

                if !model.isSearching && !pages.isEmpty {
                    PageControls(pageCount: pages.count, position: visualPage) { page in
                        turnToPage(page)
                    }
                    .position(x: chrome.contentCenterX, y: chrome.pageControlCenterY)
                }

                if let reorder {
                    draggedTile(reorder.appID, iconSide: chrome.iconSide)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .position(finger)
                        .allowsHitTesting(false)
                }

                if let folderID = model.openFolderID, let folder = model.layout.folder(folderID) {
                    FolderCover(model: model, folder: folder, layout: chrome)
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
                    armedID: armedTarget,
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
                guard !model.isSearching, !isSwiping, model.openFolderID == nil else { return }
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
                    blockLaunch = true
                    armClock.start()
                }
                dragLayout = layout
                finger = value.location
                updateReorder(at: value.location, layout: layout)
            }
            .onEnded { _ in
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
        let hovered = hoveredIcon(slot: slot, point: point, layout: layout, draggedID: session.appID)
        let now = Date().timeIntervalSinceReferenceDate
        if hovered != hoverTarget {
            hoverTarget = hovered
            hoverStarted = hovered == nil ? nil : now
        }
        let dwell = hoverStarted.map { now - $0 } ?? 0
        let draggedIsFolder = model.layout.folder(session.appID) != nil
        switch FolderDrop.decision(
            draggedIsFolder: draggedIsFolder,
            hoveredID: hovered,
            pointerOverIconCenter: hovered != nil,
            dwellSeconds: dwell
        ) {
        case .combine(let targetID):
            armedTarget = targetID
        case .reorder:
            armedTarget = nil
            session.hover(slot: slot, edge: edge)
        }
        reorder = session
    }

    private func hoveredIcon(slot: Int?, point: CGPoint, layout: LaunchGridLayout, draggedID: String) -> String? {
        guard let slot else { return nil }
        guard layout.isOverIconCenter(x: Double(point.x), y: Double(point.y), slot: slot) else { return nil }
        let pages = reorder?.preview.pages ?? model.layout.pages
        let page = reorder?.page ?? model.currentPage
        guard pages.indices.contains(page), slot < pages[page].count else { return nil }
        let id = pages[page][slot].id
        guard id != draggedID else { return nil }
        return id
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
    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { model.closeFolder() }
            VStack(spacing: 18) {
                TextField(AppFolder.defaultName, text: $name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onAppear { name = folder.name }
                    .onDisappear { commitName() }
                let columns = min(max(folder.appIDs.count, 1), 4)
                LazyVGrid(columns: Array(repeating: SwiftUI.GridItem(.fixed(layout.iconSide + 36), spacing: 8), count: columns), spacing: 12) {
                    ForEach(folder.appIDs, id: \.self) { id in
                        AppIconButton(
                            title: model.appsByID[id]?.displayName ?? id,
                            image: model.iconImages[id],
                            iconSide: layout.iconSide,
                            labelWidth: layout.iconSide + 24
                        ) {
                            model.launch(id: id)
                        }
                        .gesture(ejectGesture(id))
                    }
                }
            }
            .padding(28)
            .frame(minWidth: 280)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private func ejectGesture(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .named("overlay"))
            .onEnded { value in
                let travel = hypot(value.translation.width, value.translation.height)
                guard travel > 48 else { return }
                model.returnAppToGrid(id)
            }
    }

    private func commitName() {
        model.renameFolder(folder.id, to: name)
        nameFocused = false
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
