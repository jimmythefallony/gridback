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

    var body: some View {
        GeometryReader { overlay in
            let metrics = model.layout.metrics.clamped
            let chrome = LaunchGridLayout.make(
                overlayWidth: overlay.size.width,
                overlayHeight: overlay.size.height,
                columns: metrics.columns,
                rows: metrics.rows
            )
            let pages = reorder?.preview.pages ?? model.layout.pages
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if reorder == nil {
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
                } else {
                    pageStrip(pages: pages, layout: chrome)
                        .frame(width: chrome.gridWidth, height: chrome.gridHeight)
                        .clipped()
                        .position(
                            x: chrome.originX + chrome.gridWidth / 2,
                            y: chrome.originY + chrome.gridHeight / 2
                        )
                }

                SearchPill(query: model.searchQuery)
                    .position(x: overlay.size.width / 2, y: 58)

                if !model.isSearching && !pages.isEmpty {
                    PageControls(pageCount: pages.count, position: visualPage) { page in
                        turnToPage(page)
                    }
                    .position(x: overlay.size.width / 2, y: overlay.size.height - 58)
                }

                if let reorder {
                    AppIconButton(
                        title: model.appsByID[reorder.appID]?.displayName ?? reorder.appID,
                        image: model.iconImages[reorder.appID],
                        iconSide: chrome.iconSide
                    ) {}
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .position(finger)
                    .allowsHitTesting(false)
                }

                if let warning = model.persistenceWarning {
                    banner(warning, color: Color.orange.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 18)
                }

                if let launchError = model.launchError {
                    banner(launchError, color: Color.red.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 72)
                }
            }
            .coordinateSpace(name: "overlay")
            .simultaneousGesture(reorderGesture(layout: chrome))
            .background {
                ScrollCatcher(isEnabled: reorder == nil && !model.isSearching) { event in
                    handleScroll(event, pageWidth: chrome.gridWidth, pageCount: model.layout.pages.count)
                }
            }
            .onAppear {
                visualPage = CGFloat(model.currentPage)
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

    private func pageStrip(pages: [[String]], layout: LaunchGridLayout) -> some View {
        Color.clear
            .frame(width: layout.gridWidth, height: layout.gridHeight)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        AppGridView(
                            model: model,
                            layout: layout,
                            ids: pages[index],
                            hiddenID: reorder?.appID,
                            blockLaunch: blockLaunch
                        )
                        .frame(width: layout.gridWidth, height: layout.gridHeight)
                    }
                }
                .offset(x: -visualPage * layout.gridWidth)
            }
            .clipped()
    }

    private func reorderGesture(layout: LaunchGridLayout) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("overlay"))
            .onChanged { value in
                guard !model.isSearching, !isSwiping else { return }
                if reorder == nil {
                    guard let id = iconID(at: value.startLocation, layout: layout) else { return }
                    reorder = GridReorderSession(
                        appID: id,
                        layout: model.layout,
                        page: model.currentPage
                    )
                    blockLaunch = true
                }
                finger = value.location
                updateReorder(at: value.location, layout: layout)
            }
            .onEnded { _ in
                if let reorder {
                    model.commitReorder(reorder.preview, page: reorder.page)
                }
                reorder = nil
                DispatchQueue.main.async {
                    blockLaunch = false
                }
            }
    }

    private func updateReorder(at point: CGPoint, layout: LaunchGridLayout) {
        guard var session = reorder else { return }
        let edge = GridDragResolver.pageEdge(x: Double(point.x), overlayWidth: layout.gridWidth + layout.originX * 2)
        let slot = edge == nil ? layout.hitSlot(x: Double(point.x), y: Double(point.y)) : nil
        session.hover(slot: slot, edge: edge)
        reorder = session
    }

    private func iconID(at point: CGPoint, layout: LaunchGridLayout) -> String? {
        guard let slot = layout.hitSlot(x: Double(point.x), y: Double(point.y)) else { return nil }
        let pages = model.layout.pages
        let page = min(model.currentPage, max(pages.count - 1, 0))
        guard pages.indices.contains(page), slot < pages[page].count else { return nil }
        return pages[page][slot]
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

    private func turnToPage(_ page: Int) {
        guard !model.layout.pages.isEmpty else { return }
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
