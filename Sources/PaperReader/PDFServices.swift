import AppKit
import PDFKit
import PaperCore

struct PaperPageText: Codable, Sendable { let page: Int; let text: String }
enum PDFServices {
    static func text(url: URL) throws -> [PaperPageText] {
        guard let document = PDFDocument(url: url) else { throw LibraryError.invalidPDF }
        return (0..<document.pageCount).map { .init(page: $0, text: document.page(at: $0)?.string ?? "") }
    }
    static func pageImage(url: URL, page index: Int) throws -> Data {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: index + 1) else { throw LibraryError.invalidPDF }
        return try PDFRegionRenderer.render(url: url, page: index, rect: PDFRect(page.getBoxRect(.cropBox)), scale: 2).png
    }
    static func layout(url: URL, page index: Int) throws -> ReadingLayout {
        guard let document = PDFDocument(url: url), let page = document.page(at: index) else { throw LibraryError.invalidPDF }
        let bounds = page.bounds(for: .cropBox)
        let selections = page.selection(for: bounds)?.selectionsByLine() ?? []
        let lines = selections.enumerated().compactMap { index, selection -> ReadingLine? in
            let rect = selection.bounds(for: page).intersection(bounds)
            guard !rect.isNull, rect.width > 0, let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ReadingLine(id: index, text: text, rect: PDFRect(rect))
        }
        return ReadingLayout(bounds: PDFRect(bounds), lines: lines)
    }
    /// PDFKit's annotation adaptor requires main-thread construction, serialization and destruction.
    /// Use a short-lived helper process so large exports cannot stall the reader's main thread.
    static func exportAnnotated(original: URL, destination: URL, annotations: [PaperAnnotation]) async throws {
        let request = AnnotationExportRequest(original: original, destination: destination, annotations: annotations)
        let executable = Bundle.main.executableURL!
        try await Task.detached(priority: .userInitiated) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-Export-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            try JSONEncoder().encode(request).write(to: file, options: .atomic)
            let process = Process(); process.executableURL = executable
            process.arguments = ["--export-annotations", file.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw LibraryError.invalidPDF }
        }.value
    }
    @MainActor static func writeAnnotated(_ request: AnnotationExportRequest) throws {
        guard let document = PDFDocument(url: request.original) else { throw LibraryError.invalidPDF }
        let annotations = request.annotations
        for record in annotations {
            guard let page = document.page(at: record.page) else { continue }
            let type: PDFAnnotationSubtype
            switch record.kind { case .highlight: type = .highlight; case .line: type = .line; case .rectangle: type = .square; case .ink: type = .ink }
            let annotation = PDFAnnotation(bounds: record.rect.cgRect, forType: type, withProperties: nil)
            annotation.color = record.kind == .highlight ? .systemYellow : .systemRed
            let border = PDFBorder(); border.lineWidth = record.lineWidth; annotation.border = border
            if record.kind == .line, let start = record.points.first, let end = record.points.last {
                annotation.startPoint = CGPoint(x: start.x - record.rect.x, y: start.y - record.rect.y)
                annotation.endPoint = CGPoint(x: end.x - record.rect.x, y: end.y - record.rect.y)
            }
            if record.kind == .ink, let first = record.points.first {
                let path = NSBezierPath(); path.move(to: CGPoint(x: first.x-record.rect.x, y: first.y-record.rect.y))
                for point in record.points.dropFirst() { path.line(to: CGPoint(x: point.x-record.rect.x, y: point.y-record.rect.y)) }
                annotation.add(path)
            }
            page.addAnnotation(annotation)
        }
        guard let data = document.dataRepresentation() else { throw LibraryError.invalidPDF }
        try data.write(to: request.destination, options: .atomic)
    }
}

struct AnnotationExportRequest: Codable, Sendable {
    let original: URL
    let destination: URL
    let annotations: [PaperAnnotation]
}
