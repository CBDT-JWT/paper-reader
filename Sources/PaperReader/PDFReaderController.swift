import AppKit
import PDFKit
import Combine
import PaperCore

/// Single ownership transfer: constructed in detached task, used only on MainActor afterwards.
private final class LoadedPDF: @unchecked Sendable {
    let document: PDFDocument
    init?(_ url: URL) { guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }; self.document = document }
}

@MainActor final class PDFReaderController: NSObject, ObservableObject {
    let view = ResearchPDFView()
    let capture = CaptureOverlay()
    let annotations = AnnotationController()
    let focus = FocusController()
    private var position: PDFPoint?
    let sourceOverlay = SourceHighlightOverlay()
    private var highlightTask: Task<Void, Never>?
    @Published var page = 0
    @Published var pageCount = 0
    @Published var scale = 1.0
    @Published var captureMode = false { didSet { capture.isActive = captureMode } }
    @Published var search = ""
    var onCapture: ((Int, PDFRect) -> Void)?
    var onStateChange: ((Int, Double) -> Void)?
    var runCommand: ((CommandID) -> Void)?
    private struct FileStamp: Equatable, Sendable {
        let modified: Date?
        let size: Int?
        let identity: String?
        init(_ url: URL) throws {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey])
            modified = values.contentModificationDate; size = values.fileSize
            identity = values.fileResourceIdentifier.map { String(describing: $0) }
        }
    }
    private var cache: [(URL, PDFDocument, FileStamp)] = []
    private var observers: [NSObjectProtocol] = []
    private var scrollObserver: NSObjectProtocol?
    private var loadToken = UUID()
    override init() {
        super.init()
        view.autoScales = true
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.pageShadowsEnabled = false
        view.displaysPageBreaks = true
        view.backgroundColor = WorkspacePalette.canvasNS
        view.minScaleFactor = 0.15; view.maxScaleFactor = 6
        view.command = { [weak self] in self?.runCommand?($0) }
        capture.pdfView = view
        sourceOverlay.pdfView = view
        annotations.overlay.pdfView = view; focus.overlay.pdfView = view
        view.focusKey = { [weak self] direction in
            guard let self, focus.enabled, focus.keyboard else { return false }; focus.step(direction); return true
        }
        capture.onComplete = { [weak self] page, rect in
            self?.captureMode = false; self?.onCapture?(page, rect)
        }
        capture.onCancel = { [weak self] in self?.captureMode = false }
        for name in [Notification.Name.PDFViewPageChanged, Notification.Name.PDFViewScaleChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stateChanged() }
            })
        }
    }
    private func observeScrolling() {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        guard let clip = view.documentView?.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sourceOverlay.needsDisplay = true; self.annotations.overlay.needsDisplay = true; self.focus.overlay.needsDisplay = true
                self.stateChanged(); self.focus.prepare()
            }
        }
    }

    func load(url: URL, page: Int, scale: Double, readingPoint: PDFPoint? = nil) async throws {
        let token = UUID(); loadToken = token
        let stamp = try await Task.detached { try FileStamp(url) }.value
        let document: PDFDocument
        if let index = cache.firstIndex(where: { $0.0 == url && $0.2 == stamp }) {
            let entry = cache.remove(at: index); cache.append(entry); document = entry.1
        } else {
            guard let loaded = await Task.detached(priority: .userInitiated, operation: { LoadedPDF(url) }).value else { throw LibraryError.invalidPDF }
            guard token == loadToken else { return }
            document = loaded.document; cache.removeAll { $0.0 == url }; cache.append((url, document, stamp))
            if cache.count > 3 { cache.removeFirst() }
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where PDFFileAnnotations.isOwned(annotation) { page.removeAnnotation(annotation) }
        }
        sourceOverlay.source = nil; highlightTask?.cancel()
        view.document = document; pageCount = document.pageCount; observeScrolling()
        view.autoScales = scale <= 0
        if scale > 0 { view.scaleFactor = scale }
        if let target = document.page(at: min(max(page, 0), document.pageCount - 1)) { if let readingPoint { view.go(to: PDFDestination(page: target, at: readingPoint.cgPoint)) } else { view.go(to: target) } }
        focus.load(url: url)
        captureMode = false; stateChanged()
    }
    private func stateChanged() {
        guard let document = view.document else { return }
        let newPage = view.currentPage.map { document.index(for: $0) } ?? 0
        let newPosition = view.currentDestination.map { PDFPoint($0.point) }
        let changed = page != newPage || scale != view.scaleFactor || position != newPosition
        if page != newPage { page = newPage }
        if scale != view.scaleFactor { scale = view.scaleFactor }
        position = newPosition
        sourceOverlay.needsDisplay = true
        if changed { onStateChange?(page, view.autoScales ? 0 : scale) }
    }
    var readingPosition: PDFPoint? { position }
    func goToPage(_ index: Int) {
        guard let target = view.document?.page(at: index) else { return }; view.go(to: target)
    }
    func reveal(_ source: SourceReference) {
        guard let page = view.document?.page(at: source.page) else { return }
        view.go(to: source.rect.cgRect, on: page)
        sourceOverlay.source = source
        sourceOverlay.needsDisplay = true
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.sourceOverlay.source = nil; self?.sourceOverlay.needsDisplay = true
        }
        let selection = page.selection(for: source.rect.cgRect)
        selection?.color = NSColor.systemYellow.withAlphaComponent(0.5)
        view.setCurrentSelection(selection, animate: true)
    }
    func findNext() {
        guard !search.isEmpty, let document = view.document,
              let match = document.findString(search, fromSelection: view.currentSelection, withOptions: [.caseInsensitive]) ?? document.findString(search, withOptions: [.caseInsensitive]).first else { return }
        view.setCurrentSelection(match, animate: true); view.go(to: match)
    }
    func selectionSources(paperID: UUID) -> [SourceReference] {
        guard let selection = view.currentSelection, let document = view.document else { return [] }
        return selection.pages.compactMap { page in
            let lines = selection.selectionsByLine().filter { $0.pages.contains(page) }
            let text = lines.compactMap(\.string).joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            return SourceReference(paperID: paperID, page: document.index(for: page), rect: PDFRect(selection.bounds(for: page)), text: text)
        }
    }
}

@MainActor final class ResearchPDFView: PDFView {
    var command: ((CommandID) -> Void)?
    var commandMenu: (() -> [NSMenuItem])?
    var focusKey: ((Int) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 125, focusKey?(1) == true { return }
        if event.keyCode == 126, focusKey?(-1) == true { return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        if let commandMenu { for item in commandMenu() { menu.addItem(item) }; return menu }
        for (title, id) in [(L("截图到笔记"), CommandID.capture), (L("摘录到笔记"), .quote), (L("适合窗口"), .fit)] {
            let item = NSMenuItem(title: title, action: #selector(performMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = id.rawValue; menu.addItem(item)
        }
        return menu
    }
    @objc private func performMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let id = CommandID(rawValue: raw) { command?(id) }
    }
}

@MainActor final class CaptureOverlay: NSView {
    weak var pdfView: PDFView?
    var isActive = false { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self); if isActive { window?.makeFirstResponder(self) } } }
    var onComplete: ((Int, PDFRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var end: CGPoint?
    private var page: PDFPage?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { isActive ? super.hitTest(point) : nil }
    override func resetCursorRects() { if isActive { addCursorRect(bounds, cursor: .crosshair) } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { start = nil; end = nil; onCancel?(); needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        guard let pdfView else { return }
        let point = convert(event.locationInWindow, from: nil)
        page = pdfView.page(for: convert(point, to: pdfView), nearest: false)
        start = point; end = point; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { end = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil; end = nil; page = nil; needsDisplay = true }
        guard let pdfView, let document = pdfView.document, let page, let start else { onCancel?(); return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y))
        guard rect.width > 4, rect.height > 4 else { onCancel?(); return }
        let pageRect = pdfView.convert(convert(rect, to: pdfView), to: page).intersection(page.bounds(for: .cropBox))
        guard !pageRect.isNull, pageRect.width >= 1, pageRect.height >= 1 else { onCancel?(); return }
        onComplete?(document.index(for: page), PDFRect(pageRect))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard isActive else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.035).setFill(); bounds.fill()
        if let start, let end {
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y))
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill(); rect.fill()
            NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(rect: rect); path.lineWidth = 1.5; path.stroke()
        }
    }
}


/// Visual source feedback is independent of the PDF document, including image-only regions.
@MainActor final class SourceHighlightOverlay: NSView {
    weak var pdfView: PDFView?
    var source: SourceReference?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView, let source, let page = pdfView.document?.page(at: source.page) else { return }
        let rect = convert(pdfView.convert(source.rect.cgRect, from: page), from: pdfView)
        NSColor.systemYellow.withAlphaComponent(0.2).setFill(); rect.fill()
        NSColor.systemOrange.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3); path.lineWidth = 2; path.stroke()
    }
}
