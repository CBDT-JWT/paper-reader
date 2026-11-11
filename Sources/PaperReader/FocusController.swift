import AppKit
import PDFKit
import Combine
import PaperCore

@MainActor final class FocusController: ObservableObject {
    @Published var enabled = false {
        didSet {
            overlay.enabled = enabled
            if enabled { prepare() }
            else {
                automatic = false
                cancelMotion()
                motion.restoreScrollLimits()
                screenMask.hide()
            }
            refreshMask()
        }
    }
    @Published var above = 1 { didSet { parametersChanged() } }
    @Published var below = 2 { didSet { parametersChanged() } }
    @Published var opacity = 0.48 { didSet { refreshMask() } }
    @Published var feather = UserDefaults.standard.object(forKey: "focus.feather") as? Double ?? 18 {
        didSet { UserDefaults.standard.set(feather, forKey: "focus.feather"); refreshMask() }
    }
    @Published var linesPerMinute = UserDefaults.standard.object(forKey: "focus.linesPerMinute") as? Double ?? 45 {
        didSet { UserDefaults.standard.set(linesPerMinute, forKey: "focus.linesPerMinute") }
    }
    @Published var keyboard = false {
        didSet {
            guard oldValue != keyboard else { return }
            if !keyboard { automatic = false; cancelMotion(); update() }
            else if !automatic { centerCurrent() }
        }
    }
    @Published var automatic = false {
        didSet {
            guard oldValue != automatic else { return }
            if automatic {
                if !enabled { enabled = true }
                keyboard = true
                beginAutomaticReading()
            } else {
                cancelMotion()
                if let entry = overlay.highlights, let anchor = overlay.readingAnchor {
                    page = entry.0
                    lastPoint = anchor
                    currentLineID = overlay.readingLineID
                }
                refreshMask()
            }
        }
    }
    @Published var manualColumn = -1 { didSet { if !updatingAnchor { parametersChanged() } } }
    @Published var manualCount = 2 {
        didSet {
            if manualColumn >= manualCount {
                updatingAnchor = true
                manualColumn = max(0, manualCount - 1)
                updatingAnchor = false
            }
            parametersChanged()
        }
    }
    @Published private(set) var detectedColumns = 0
    @Published private(set) var status = ""
    let overlay = FocusOverlay()
    let screenMask = ScreenFocusMask()
    private lazy var motion = FocusMotion(overlay: overlay)
    private var motionTask: Task<Void, Never>?
    private var geometryObservers: [NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var mouseDownLocation: CGPoint?
    private var layouts: [Int: ReadingLayout] = [:]
    private var loading: Set<Int> = []
    private var failedPages: Set<Int> = []
    private var url: URL?
    private var generation = UUID()
    private var lastPoint: PDFPoint?
    private(set) var currentLineID: Int?
    private var page = 0
    private var updatingAnchor = false
    var isMoving: Bool { motion.isAnimating }
    // A scoped native test driver can isolate desktop activation changes, then
    // restore this observer to test deactivation cancellation independently.
    var pausesWhenInactive = true
    private var selectedColumn: Int? { manualColumn < 0 ? nil : manualColumn }

    init() {
        overlay.onMove = { [weak self] point, page in
            guard let self, !keyboard else { return }
            self.page = page
            lastPoint = point
            currentLineID = nil
            update()
        }
        overlay.onGeometryChanged = { [weak self] in self?.refreshMask() }
        screenMask.onEscape = { [weak self] in self?.enabled = false }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self, self.enabled, let pdfView = self.overlay.pdfView, event.window === pdfView.window else { return event }
            if event.type == .keyDown, self.keyboard, event.keyCode == 125 || event.keyCode == 126 {
                let responder = event.window?.firstResponder as? NSView
                if responder === pdfView || responder?.isDescendant(of: pdfView) == true || responder === self.overlay {
                    self.step(event.keyCode == 125 ? 1 : -1)
                    return nil
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
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let identifier = (notification.object as? NSWindow).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let window = self.overlay.window, identifier == ObjectIdentifier(window) else { return }
                    self.parametersChanged()
                    self.prepare()
                }
            })
        }
        geometryObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pausesWhenInactive else { return }
                self.automatic = false
            }
        })
    }

    private func refreshMask() {
        screenMask.update(regions: overlay.screenRegions, opacity: opacity, enabled: enabled && url != nil,
                          owner: overlay.pdfView?.window, feather: feather, holeVisibility: overlay.holeVisibility)
    }

    func load(url: URL) {
        automatic = false
        cancelMotion()
        generation = UUID()
        self.url = url
        layouts = [:]
        loading = []
        failedPages = []
        detectedColumns = 0
        status = ""
        lastPoint = nil
        currentLineID = nil
        overlay.readingLineID = nil
        overlay.readingAnchor = nil
        page = 0
        keyboard = false
        overlay.highlights = nil
        prepare()
        refreshMask()
    }

    func prepare() {
        guard enabled, let pdfView = overlay.pdfView, let document = pdfView.document, document.pageCount > 0 else { return }
        if !keyboard {
            let pointer = pdfView.window.map { pdfView.convert($0.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }
            let location = pointer.flatMap { pdfView.bounds.contains($0) ? $0 : nil } ?? CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
            if let target = pdfView.page(for: location, nearest: true) {
                page = document.index(for: target)
                lastPoint = PDFPoint(pdfView.convert(location, to: target))
                currentLineID = nil
            }
        }
        let visible = pdfView.currentPage.map { document.index(for: $0) } ?? page
        for index in max(0, visible - 1)...min(visible + 1, document.pageCount - 1) { cache(index) }
        cache(page)
        if !motion.isAnimating { update() }
        refreshMask()
    }

    private func cache(_ page: Int) {
        guard let count = overlay.pdfView?.document?.pageCount, (0..<count).contains(page) else { return }
        guard let url, layouts[page] == nil, !loading.contains(page), !failedPages.contains(page) else { return }
        loading.insert(page)
        let token = generation
        Task {
            do {
                let layout = try await Task.detached(priority: .utility) { try PDFServices.layout(url: url, page: page) }.value
                guard token == generation else { return }
                layouts[page] = layout
                loading.remove(page)
                if self.page == page, !motion.isAnimating {
                    update()
                    if keyboard && !automatic { centerCurrent() }
                }
            } catch {
                guard token == generation else { return }
                status = error.localizedDescription
                failedPages.insert(page)
                loading.remove(page)
            }
        }
    }

    func togglePin(at point: PDFPoint, page: Int) {
        guard enabled else { return }
        automatic = false
        self.page = page
        lastPoint = point
        currentLineID = nil
        if !keyboard, layouts[page]?.figureRegions.contains(where: { $0.cgRect.contains(point.cgPoint) }) == true {
            update()
            return
        }
        keyboard.toggle()
        if !keyboard { update() }
    }

    func step(_ direction: Int) {
        guard enabled, keyboard else { return }
        automatic = false
        cancelMotion()
        motionTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let target = try await nextFrame(direction: direction) else { return }
                setAnchor(target)
                try await motion.animate(to: target, automatic: false, speed: { self.linesPerMinute })
            } catch is CancellationError { }
            catch { status = error.localizedDescription }
        }
    }

    private func beginAutomaticReading() {
        cancelMotion()
        motionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await waitForLayout(page)
                if currentFrame() == nil, let layout = layouts[page], let point = lastPoint,
                   let figure = layout.figureRegions.first(where: { $0.cgRect.contains(point.cgPoint) }),
                   let next = layout.readingOrder().first(where: { line in
                       line.rect.cgRect.midY < figure.y && line.rect.x < figure.cgRect.maxX && line.rect.cgRect.maxX > figure.x
                   }) {
                    currentLineID = next.id
                    lastPoint = PDFPoint(x: next.rect.cgRect.midX, y: next.rect.cgRect.midY)
                }
                guard let initial = currentFrame() else { automatic = false; return }
                try await motion.animate(to: initial, automatic: false, speed: { self.linesPerMinute })
                while enabled && automatic {
                    guard let target = try await nextFrame(direction: 1) else { automatic = false; return }
                    setAnchor(target)
                    try await motion.animate(to: target, automatic: true, speed: { self.linesPerMinute })
                }
            } catch is CancellationError { }
            catch { status = error.localizedDescription; automatic = false }
        }
    }

    private func waitForLayout(_ index: Int) async throws {
        cache(index)
        while layouts[index] == nil && loading.contains(index) {
            try await Task.sleep(for: .milliseconds(30))
        }
        try Task.checkCancellation()
    }

    private func nextFrame(direction: Int) async throws -> FocusFrame? {
        try await waitForLayout(page)
        guard let layout = layouts[page], let current = currentLine(in: layout) else { return nil }
        let order = layout.readingOrder(manualColumn: selectedColumn, manualCount: manualCount)
        guard let index = order.firstIndex(where: { $0.id == current.id }) else { return nil }
        let next = index + (direction > 0 ? 1 : -1)
        if order.indices.contains(next) { return frame(for: order[next], page: page, layout: layout, manualColumn: selectedColumn) }
        if let column = selectedColumn {
            let nextColumn = column + (direction > 0 ? 1 : -1)
            if (0..<manualCount).contains(nextColumn) {
                let nextOrder = layout.readingOrder(manualColumn: nextColumn, manualCount: manualCount)
                if let line = direction > 0 ? nextOrder.first : nextOrder.last {
                    return frame(for: line, page: page, layout: layout, manualColumn: nextColumn)
                }
            }
        }
        let adjacentPage = page + (direction > 0 ? 1 : -1)
        guard let count = overlay.pdfView?.document?.pageCount, (0..<count).contains(adjacentPage) else { return nil }
        try await waitForLayout(adjacentPage)
        guard let adjacent = layouts[adjacentPage] else { return nil }
        let nextColumn = selectedColumn.map { _ in direction > 0 ? 0 : manualCount - 1 }
        let adjacentOrder = adjacent.readingOrder(manualColumn: nextColumn, manualCount: manualCount)
        guard let line = direction > 0 ? adjacentOrder.first : adjacentOrder.last else { return nil }
        return frame(for: line, page: adjacentPage, layout: adjacent, manualColumn: nextColumn)
    }

    private func frame(for line: ReadingLine, page: Int, layout: ReadingLayout, manualColumn: Int?) -> FocusFrame? {
        let point = PDFPoint(x: line.rect.cgRect.midX, y: line.rect.cgRect.midY)
        let padding = max(6, feather / max(overlay.pdfView?.scaleFactor ?? 1, 0.15))
        guard let rectangle = layout.focusRectangle(lineID: line.id, above: above, below: below, manualColumn: manualColumn, manualCount: manualCount, padding: padding) else { return nil }
        let crossesFigure = overlay.highlights?.0 == page && overlay.highlightColumn == line.column && overlay.readingAnchor.map { source in
            layout.figureRegions.contains { region in
                region.y < max(source.y, point.y) && region.cgRect.maxY > min(source.y, point.y) &&
                    region.x < rectangle.cgRect.maxX && region.cgRect.maxX > rectangle.x
            }
        } == true
        return FocusFrame(lineID: line.id, page: page, column: line.column, rectangle: rectangle.cgRect, anchor: point, crossesFigure: crossesFigure)
    }

    private func currentFrame() -> FocusFrame? {
        guard let layout = layouts[page], let line = currentLine(in: layout) else { return nil }
        return frame(for: line, page: page, layout: layout, manualColumn: selectedColumn)
    }

    private func currentLine(in layout: ReadingLayout) -> ReadingLine? {
        if let currentLineID,
           let line = layout.focused(lineID: currentLineID, above: 0, below: 0, manualColumn: selectedColumn, manualCount: manualCount).first {
            return line
        }
        guard let point = lastPoint else { return nil }
        let line = layout.focused(at: point, above: 0, below: 0, manualColumn: selectedColumn, manualCount: manualCount).first
        currentLineID = line?.id
        return line
    }

    private func setAnchor(_ frame: FocusFrame) {
        page = frame.page
        lastPoint = frame.anchor
        currentLineID = frame.lineID
        if selectedColumn != nil, manualColumn != frame.column {
            updatingAnchor = true
            manualColumn = frame.column
            updatingAnchor = false
        }
        cache(page - 1)
        if let count = overlay.pdfView?.document?.pageCount, page + 1 < count { cache(page + 1) }
    }

    private func centerCurrent() {
        guard enabled else { return }
        guard let target = currentFrame() else { cache(page); return }
        cancelMotion()
        motionTask = Task { [weak self] in
            guard let self else { return }
            do { try await motion.animate(to: target, automatic: false, speed: { self.linesPerMinute }) }
            catch is CancellationError { }
            catch { status = error.localizedDescription }
        }
    }

    private func cancelMotion() {
        motionTask?.cancel()
        motionTask = nil
        motion.cancel()
    }

    private func parametersChanged() {
        let resume = automatic
        cancelMotion()
        update()
        if resume { beginAutomaticReading() }
        else if keyboard { centerCurrent() }
    }

    private func update() {
        guard enabled else { return }
        guard let layout = layouts[page] else { cache(page); return }
        detectedColumns = layout.columnCount
        status = layout.lines.isEmpty ? L("扫描页面使用区域聚焦；可手动指定阅读栏。") : ""
        if layout.lines.isEmpty {
            if !layout.figureRegions.isEmpty && manualColumn < 0 {
                overlay.highlights = nil
                refreshMask()
                return
            }
            let count = manualColumn < 0 ? 1 : max(manualCount, 1)
            let width = layout.bounds.width / Double(count)
            let column = manualColumn < 0 ? 0 : min(max(manualColumn, 0), count - 1)
            let center = lastPoint?.y ?? layout.bounds.cgRect.midY
            let region = CGRect(x: layout.bounds.x + Double(column) * width, y: center - Double(below + 1) * 18,
                                width: width, height: Double(above + below + 1) * 18).intersection(layout.bounds.cgRect)
            overlay.highlights = region.isNull ? nil : (page, [region])
        } else if let frame = currentFrame() {
            overlay.highlights = (frame.page, [frame.rectangle])
            overlay.highlightColumn = frame.column
            overlay.readingAnchor = frame.anchor
            overlay.readingLineID = frame.lineID
        } else {
            overlay.highlights = nil
            overlay.readingAnchor = nil
            overlay.readingLineID = nil
        }
        refreshMask()
    }
}
@MainActor final class FocusOverlay: NSView {
    weak var pdfView: PDFView?
    var enabled = false
    var highlights: (Int, [CGRect])?
    var highlightColumn = 0
    var viewportRectangle: CGRect?
    var holeVisibility = 1.0
    var readingAnchor: PDFPoint?
    var readingLineID: Int?
    var onGeometryChanged: (() -> Void)?
    var screenRectangleInPDFView: CGRect? {
        if let viewportRectangle { return viewportRectangle }
        guard let pdfView, let (index, regions) = highlights,
              let rectangle = regions.first, let page = pdfView.document?.page(at: index) else { return nil }
        return pdfView.convert(rectangle, from: page)
    }
    var screenRegions: [CGRect] {
        if enabled, let rectangle = viewportRectangle, let pdfView, let window {
            let visible = rectangle.intersection(pdfView.bounds)
            guard !visible.isNull else { return [] }
            return [window.convertToScreen(pdfView.convert(visible, to: nil))]
        }
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
