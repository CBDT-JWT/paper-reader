import AppKit
import PDFKit
import Combine
import PaperCore

enum ReaderTool: String, CaseIterable, Identifiable { case select, line, rectangle, ink, laser; var id: String { rawValue }
    var command: CommandID { switch self { case .select: .selectText; case .line: .drawLine; case .rectangle: .drawRectangle; case .ink: .drawing; case .laser: .laser } }
    var title: String { switch self { case .select: L("选择文字"); case .line: L("直线"); case .rectangle: L("矩形"); case .ink: L("自由绘制"); case .laser: L("激光笔") } }
    var symbol: String { switch self { case .select: "cursorarrow"; case .line: "line.diagonal"; case .rectangle: "rectangle"; case .ink: "pencil.tip"; case .laser: "laser.burst" } }
}
@MainActor final class AnnotationController: ObservableObject {
    @Published var tool: ReaderTool = .select { didSet { overlay.tool = tool; overlay.window?.makeFirstResponder(tool == .select ? overlay.pdfView : overlay) } }
    @Published private(set) var records: [PaperAnnotation] = []
    let overlay = AnnotationOverlay()
    private var undoStack: [[PaperAnnotation]] = [], redoStack: [[PaperAnnotation]] = []
    private var paperID: UUID?
    private var pending: (UUID, [PaperAnnotation])?
    private var worker: Task<Void, Never>?
    var hasUnsavedChanges: Bool { pending != nil || worker != nil }
    var store: LibraryStore?
    var onError: ((String) -> Void)?
    init() { overlay.onDraw = { [weak self] in self?.add([$0]) }; overlay.onCancel = { [weak self] in self?.tool = .select } }
    func load(_ id: UUID) async throws {
        guard await flush() else { throw LibraryError.pdfSaveFailed }
        paperID = id; records = try await store?.annotations(id) ?? []
        undoStack = []; redoStack = []; tool = .select; refresh()
    }
    func reloadFromFile() async throws {
        if let worker { await worker.value }
        guard let paperID else { return }
        let latest = try await store?.annotations(paperID) ?? []
        undoStack.append(records); redoStack = []
        pending = nil; records = latest; refresh()
    }
    func add(_ values: [PaperAnnotation]) {
        guard !values.isEmpty else { return }; undoStack.append(records); redoStack = []; records += values; changed()
    }
    func undo() { guard let old = undoStack.popLast() else { return }; redoStack.append(records); records = old; changed() }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(records); records = next; changed() }
    private func refresh() { overlay.records = records; overlay.needsDisplay = true }
    private func changed() {
        refresh(); guard let paperID else { return }; pending = (paperID, records)
        if worker == nil { worker = Task { [weak self] in await self?.writePending() } }
    }
    private func writePending() async {
        while let (id, snapshot) = pending {
            pending = nil
            do { try await store?.saveAnnotations(id, records: snapshot) }
            catch {
                if pending == nil { pending = (id, snapshot) }
                onError?(error.localizedDescription)
                break
            }
        }
        worker = nil
    }
    @discardableResult func flush() async -> Bool {
        if let worker { await worker.value }
        else if pending != nil { await writePending() }
        return pending == nil
    }
}
@MainActor final class AnnotationOverlay: NSView {
    weak var pdfView: PDFView?
    var records: [PaperAnnotation] = []
    var tool: ReaderTool = .select { didSet { window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var onDraw: ((PaperAnnotation) -> Void)?
    var onCancel: (() -> Void)?
    private var points: [PDFPoint] = []
    private var pageIndex: Int?
    private var laserTask: Task<Void, Never>?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { tool == .select ? nil : super.hitTest(point) }
    override func resetCursorRects() { if tool != .select { addCursorRect(bounds, cursor: .crosshair) } }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { points = []; pageIndex = nil; onCancel?(); needsDisplay = true } }
    override func mouseDown(with event: NSEvent) {
        guard let pdfView, let document = pdfView.document else { return }
        let location = convert(convert(event.locationInWindow, from: nil), to: pdfView)
        guard let page = pdfView.page(for: location, nearest: false) else { return }
        laserTask?.cancel(); pageIndex = document.index(for: page); points = [PDFPoint(pdfView.convert(location, to: page))]; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let pdfView, let index = pageIndex, let page = pdfView.document?.page(at: index) else { return }
        let point = pdfView.convert(convert(convert(event.locationInWindow, from: nil), to: pdfView), to: page)
        guard page.bounds(for: .cropBox).contains(point) else { return }
        points.append(PDFPoint(point)); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if tool == .laser {
            laserTask = Task { [weak self] in try? await Task.sleep(for: .milliseconds(700)); guard !Task.isCancelled else { return }; self?.points = []; self?.needsDisplay = true }
        } else {
            if let record = currentRecord() { onDraw?(record) }
            points = []; pageIndex = nil; needsDisplay = true
        }
    }
    private func currentRecord() -> PaperAnnotation? {
        guard let page = pageIndex, points.count > 1, let first = points.first, let last = points.last else { return nil }
        let used = tool == .ink || tool == .laser ? points : [first, last]
        let xs = used.map(\.x), ys = used.map(\.y)
        let rect = PDFRect(x: xs.min()! - 2, y: ys.min()! - 2, width: max(4, xs.max()! - xs.min()! + 4), height: max(4, ys.max()! - ys.min()! + 4))
        let kind: AnnotationKind = tool == .rectangle ? .rectangle : tool == .line ? .line : .ink
        return PaperAnnotation(page: page, kind: kind, rect: rect, points: used)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView, let document = pdfView.document else { return }
        for record in records + (currentRecord().map { [$0] } ?? []) {
            guard let page = document.page(at: record.page) else { continue }
            let rect = convert(pdfView.convert(record.rect.cgRect, from: page), from: pdfView)
            guard rect.intersects(bounds) else { continue }
            if record.kind == .highlight { NSColor.systemYellow.withAlphaComponent(0.3).setFill(); rect.fill(); continue }
            NSColor.systemRed.withAlphaComponent(tool == .laser ? 0.8 : 0.9).setStroke()
            let path = NSBezierPath(); path.lineWidth = record.lineWidth * pdfView.scaleFactor; path.lineCapStyle = .round; path.lineJoinStyle = .round
            if record.kind == .rectangle { path.appendRect(rect) }
            else {
                for (index, point) in record.points.enumerated() {
                    let point = convert(pdfView.convert(point.cgPoint, from: page), from: pdfView)
                    if index == 0 { path.move(to: point) } else { path.line(to: point) }
                }
            }
            path.stroke()
        }
    }
}
