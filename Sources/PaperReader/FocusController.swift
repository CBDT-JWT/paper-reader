import AppKit
import PDFKit
import Combine
import PaperCore

@MainActor final class FocusController: ObservableObject {
    @Published var enabled = false { didSet { overlay.enabled = enabled; if enabled { prepare() } else { screenMask.hide() }; refreshMask(); overlay.needsDisplay = true } }
    @Published var above = 1 { didSet { update() } }
    @Published var below = 2 { didSet { update() } }
    @Published var opacity = 0.48 { didSet { refreshMask(); overlay.needsDisplay = true } }
    @Published var keyboard = false
    @Published var manualColumn = -1 { didSet { update() } }
    @Published var manualCount = 2 { didSet { update() } }
    @Published private(set) var detectedColumns = 0
    @Published private(set) var status = ""
    let overlay = FocusOverlay()
    let screenMask = ScreenFocusMask()
    private var geometryObservers: [NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var mouseDownLocation: CGPoint?
    private var layouts: [Int: ReadingLayout] = [:]
    private var loading: Set<Int> = []
    private var url: URL?
    private var generation = UUID()
    private var lastPoint: PDFPoint?
    private var page = 0
    init() {
        overlay.onMove = { [weak self] point, page in
            guard let self, !keyboard else { return }; self.page = page; lastPoint = point; update()
        }
        overlay.onGeometryChanged = { [weak self] in self?.refreshMask() }
        screenMask.onEscape = { [weak self] in self?.enabled = false }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self, self.enabled, let pdfView = self.overlay.pdfView, event.window === pdfView.window else { return event }
            if event.type == .keyDown, self.keyboard, event.keyCode == 125 || event.keyCode == 126 {
                let responder = event.window?.firstResponder as? NSView
                if responder === pdfView || responder?.isDescendant(of: pdfView) == true || responder === self.overlay {
                    self.step(event.keyCode == 125 ? 1 : -1); return nil
                }
            }
            let point = pdfView.convert(event.locationInWindow, from: nil)
            guard pdfView.bounds.contains(point) else { self.mouseDownLocation = nil; return event }
            if event.type == .leftMouseDown { self.mouseDownLocation = point }
            else if event.type == .leftMouseUp {
                defer { self.mouseDownLocation = nil }
                if let down = self.mouseDownLocation, hypot(point.x - down.x, point.y - down.y) < 4,
                   let document = pdfView.document, let page = pdfView.page(for: point, nearest: false) {
                    self.togglePin(at: PDFPoint(pdfView.convert(point, to: page)), page: document.index(for: page))
                }
            }
            return event
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didEndLiveResizeNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let identifier = (notification.object as? NSWindow).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let window = self.overlay.window, identifier == ObjectIdentifier(window) else { return }
                    self.refreshMask()
                }
            })
        }
    }
    private func refreshMask() {
        let regions = overlay.screenRegions
        screenMask.update(regions: regions, opacity: opacity, enabled: enabled && url != nil)
    }
    func load(url: URL) { generation = UUID(); self.url = url; layouts = [:]; loading = []; lastPoint = nil; keyboard = false; overlay.highlights = nil; prepare(); refreshMask() }
    func prepare() {
        guard enabled, let pdfView = overlay.pdfView, let document = pdfView.document, document.pageCount > 0 else { return }
        // Start at the pointer if it is over the PDF; otherwise use the visible viewport.
        // A restored scroll position must never anchor the hole to an off-screen first line.
        if !keyboard {
            let pointer = pdfView.window.map { pdfView.convert($0.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }
            let location = pointer.flatMap { pdfView.bounds.contains($0) ? $0 : nil } ?? CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
            if let target = pdfView.page(for: location, nearest: true) {
                page = document.index(for: target); lastPoint = PDFPoint(pdfView.convert(location, to: target))
            }
        }
        let visible = pdfView.currentPage.map { document.index(for: $0) } ?? page
        for index in max(0, visible - 1)...min(visible + 1, document.pageCount - 1) { cache(index) }
        cache(page); update(); refreshMask()
    }
    private func cache(_ page: Int) {
        guard let url, layouts[page] == nil, !loading.contains(page) else { return }
        loading.insert(page); let token = generation
        Task {
            do {
                let layout = try await Task.detached(priority: .utility) { try PDFServices.layout(url: url, page: page) }.value
                guard token == generation else { return }
                layouts[page] = layout; loading.remove(page)
                if self.page == page { update() }
            } catch { status = error.localizedDescription; loading.remove(page) }
        }
    }
    func togglePin(at point: PDFPoint, page: Int) {
        guard enabled else { return }
        self.page = page; lastPoint = point; keyboard.toggle(); update()
    }
    func step(_ direction: Int) {
        guard enabled, keyboard, let layout = layouts[page], !layout.lines.isEmpty else { return }
        let point = lastPoint ?? PDFPoint(x: layout.lines[0].rect.x, y: layout.lines[0].rect.y)
        let focused = layout.focused(at: point, above: 0, below: 0, manualColumn: manualColumn < 0 ? nil : manualColumn, manualCount: manualCount)
        guard let current = focused.first else { return }
        let column = layout.readingOrder(manualColumn: manualColumn < 0 ? nil : manualColumn, manualCount: manualCount)
        guard let index = column.firstIndex(where: { $0.id == current.id }) else { return }
        let offset = index + direction
        if offset < 0 || offset >= column.count {
            let targetPage = page + (direction > 0 ? 1 : -1)
            if let adjacent = layouts[targetPage], let next = direction > 0 ? adjacent.readingOrder(manualColumn: manualColumn < 0 ? nil : manualColumn, manualCount: manualCount).first : adjacent.readingOrder(manualColumn: manualColumn < 0 ? nil : manualColumn, manualCount: manualCount).last {
                page = targetPage; lastPoint = .init(x: next.rect.x + next.rect.width / 2, y: next.rect.y + next.rect.height / 2)
                update()
                if let view = overlay.pdfView, let pdfPage = view.document?.page(at: page) { view.go(to: next.rect.cgRect, on: pdfPage) }
            }
            return
        }
        let next = column[offset]
        lastPoint = .init(x: next.rect.x + next.rect.width/2, y: next.rect.y + next.rect.height/2); update()
        if let view = overlay.pdfView, let pdfPage = view.document?.page(at: page), !view.bounds.insetBy(dx: 0, dy: 24).contains(view.convert(next.rect.cgRect, from: pdfPage)) { view.go(to: next.rect.cgRect, on: pdfPage) }
    }
    private func update() {
        guard enabled else { return }; guard let layout = layouts[page] else { cache(page); return }
        detectedColumns = layout.columnCount
        status = layout.lines.isEmpty ? L("扫描页面使用区域聚焦；可手动指定阅读栏。") : ""
        if layout.lines.isEmpty {
            let count = manualColumn < 0 ? 1 : max(manualCount, 1)
            let width = layout.bounds.width / Double(count)
            let column = manualColumn < 0 ? 0 : min(max(manualColumn, 0), count - 1)
            let center = lastPoint?.y ?? layout.bounds.y + layout.bounds.height / 2
            let region = CGRect(x: layout.bounds.x + Double(column) * width, y: center - Double(below + 1) * 18, width: width, height: Double(above + below + 1) * 18).intersection(layout.bounds.cgRect)
            overlay.highlights = region.isNull ? nil : (page, [region])
            refreshMask(); overlay.needsDisplay = true; return
        }
        let point = lastPoint ?? layout.lines.first.map { PDFPoint(x: $0.rect.x + 2, y: $0.rect.y + 2) } ?? .init(x: 0, y: 0)
        let target = layout.focused(at: point, above: above, below: below, manualColumn: manualColumn < 0 ? nil : manualColumn, manualCount: manualCount)
        overlay.highlights = target.isEmpty ? nil : (page, target.map { $0.rect.cgRect.insetBy(dx: -3, dy: -1) })
        refreshMask(); overlay.needsDisplay = true
    }
}
@MainActor final class FocusOverlay: NSView {
    weak var pdfView: PDFView?
    var enabled = false
    var highlights: (Int, [CGRect])?
    var onGeometryChanged: (() -> Void)?
    var screenRegions: [CGRect] {
        guard enabled, let pdfView, let (index, regions) = highlights, let page = pdfView.document?.page(at: index), let window else { return [] }
        return regions.compactMap { region in
            let visible = pdfView.convert(region, from: page).intersection(pdfView.bounds)
            guard !visible.isNull else { return nil }
            return window.convertToScreen(convert(convert(visible, from: pdfView), to: nil))
        }
    }
    var onMove: ((PDFPoint, Int) -> Void)?
    private var tracking: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved], owner: self)
        addTrackingArea(area); tracking = area; window?.acceptsMouseMovedEvents = true
    }
    override func mouseMoved(with event: NSEvent) {
        guard enabled, let pdfView, let document = pdfView.document else { return }
        let location = convert(convert(event.locationInWindow, from: nil), to: pdfView)
        guard let page = pdfView.page(for: location, nearest: false) else { return }
        onMove?(PDFPoint(pdfView.convert(location, to: page)), document.index(for: page))
    }
    // PDF scrolling invalidates this tracking view. The actual mask is drawn in screen-space
    // windows, avoiding a second dark layer inside the PDF pane.
    override func draw(_ dirtyRect: NSRect) { onGeometryChanged?() }
}
