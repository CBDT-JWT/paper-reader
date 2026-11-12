import Foundation
import PDFKit
import AppKit

/// Records live inside standard PDF annotations. Temporary request files are never sidecars.
public enum PDFFileAnnotations {
    private static let recordKey = PDFAnnotationKey(rawValue: "PaperReaderRecord")
    private static let nameKey = PDFAnnotationKey(rawValue: "NM")
    public static func isOwned(_ annotation: PDFAnnotation) -> Bool {
        (annotation.value(forAnnotationKey: nameKey) as? String)?.hasPrefix("PaperReader-") == true && annotation.value(forAnnotationKey: recordKey) is String
    }
    @MainActor private static func records(in document: PDFDocument) throws -> [PaperAnnotation] {
        var records: [PaperAnnotation] = []
        for index in 0..<document.pageCount {
            for annotation in document.page(at: index)?.annotations ?? [] where isOwned(annotation) {
                guard let value = annotation.value(forAnnotationKey: recordKey) as? String,
                      let data = value.data(using: .utf8),
                      var record = try? JSONDecoder().decode(PaperAnnotation.self, from: data) else {
                    throw LibraryError.invalidPDF
                }
                record.page = index
                let bounds = PDFRect(annotation.bounds)
                // PDF numeric serialization rounds sub-point coordinates. Preserve exact app
                // geometry unless another editor moved or resized the annotation materially.
                let difference = [abs(bounds.x - record.rect.x), abs(bounds.y - record.rect.y),
                                  abs(bounds.width - record.rect.width), abs(bounds.height - record.rect.height)].max() ?? 0
                if difference > 0.01 { record.rect = bounds }
                records.append(record)
            }
        }
        return records.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    @MainActor public static func read(_ url: URL) throws -> [PaperAnnotation] {
        guard let document = PDFDocument(data: try CoordinatedFiles.read(url)) else { throw LibraryError.invalidPDF }
        return try records(in: document)
    }
    @MainActor public static func write(_ url: URL, records desired: [PaperAnnotation], expected: [PaperAnnotation]?) throws {
        guard Set(desired.map(\.id)).count == desired.count else { throw LibraryError.invalidPDF }
        try CoordinatedFiles.update(url) { bytes in
            guard let bytes, let document = PDFDocument(data: bytes), !document.isLocked, document.allowsCommenting else { throw LibraryError.pdfReadOnly }
            let previous = try records(in: document)
            if let expected, previous != expected.sorted(by: { $0.id.uuidString < $1.id.uuidString }) { throw LibraryError.pdfAnnotationsChanged }
            if previous == desired.sorted(by: { $0.id.uuidString < $1.id.uuidString }) { return bytes }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                for annotation in page.annotations where isOwned(annotation) { page.removeAnnotation(annotation) }
            }
            for record in desired {
                guard let page = document.page(at: record.page), record.rect.width > 0, record.rect.height > 0 else { throw LibraryError.invalidPDF }
                let kind: PDFAnnotationSubtype
                switch record.kind {
                case .highlight: kind = .highlight
                case .line: kind = .line
                case .rectangle: kind = .square
                case .ink: kind = .ink
                }
                let annotation = PDFAnnotation(bounds: record.rect.cgRect, forType: kind, withProperties: nil)
                annotation.color = record.kind == .highlight ? .systemYellow : .systemRed
                if record.kind == .highlight {
                    annotation.quadrilateralPoints = [CGPoint(x: 0, y: record.rect.height), CGPoint(x: record.rect.width, y: record.rect.height),
                                                      CGPoint(x: 0, y: 0), CGPoint(x: record.rect.width, y: 0)].map { NSValue(point: $0) }
                }
                let border = PDFBorder()
                border.lineWidth = record.lineWidth
                annotation.border = border
                annotation.setValue("PaperReader-" + record.id.uuidString, forAnnotationKey: nameKey)
                annotation.setValue(String(decoding: try JSONEncoder().encode(record), as: UTF8.self), forAnnotationKey: recordKey)
                if record.kind == .line, let start = record.points.first, let end = record.points.last {
                    annotation.startPoint = CGPoint(x: start.x - record.rect.x, y: start.y - record.rect.y)
                    annotation.endPoint = CGPoint(x: end.x - record.rect.x, y: end.y - record.rect.y)
                }
                if record.kind == .ink, let first = record.points.first {
                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: first.x - record.rect.x, y: first.y - record.rect.y))
                    for point in record.points.dropFirst() { path.line(to: CGPoint(x: point.x - record.rect.x, y: point.y - record.rect.y)) }
                    annotation.add(path)
                }
                page.addAnnotation(annotation)
            }
            guard let result = document.dataRepresentation(), let verified = PDFDocument(data: result),
                  verified.pageCount == document.pageCount,
                  try records(in: verified) == desired.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else { throw LibraryError.invalidPDF }
            return result
        }
    }
}

public struct PDFAnnotationRequest: Codable, Sendable {
    public let url: URL
    public let records: [PaperAnnotation]?
    public let expected: [PaperAnnotation]?
    public init(url: URL, records: [PaperAnnotation]? = nil, expected: [PaperAnnotation]? = nil) {
        self.url = url; self.records = records; self.expected = expected
    }
}

extension LibraryStore {
    /// PDFKit's serialization runs on a helper's main thread, keeping the reader responsive.
    func performAnnotationRequest(_ request: PDFAnnotationRequest) async throws -> [PaperAnnotation] {
        guard let annotationHelper else {
            return try await MainActor.run {
                if let records = request.records { try PDFFileAnnotations.write(request.url, records: records, expected: request.expected) }
                return try PDFFileAnnotations.read(request.url)
            }
        }
        return try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-PDF-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let input = folder.appendingPathComponent("request.json")
            let output = folder.appendingPathComponent("result.json")
            try JSONEncoder().encode(request).write(to: input)
            let process = Process()
            process.executableURL = annotationHelper
            process.arguments = ["--pdf-annotations", input.path, output.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 3 { throw LibraryError.pdfAnnotationsChanged }
            if process.terminationStatus == 4 { throw LibraryError.pdfReadOnly }
            guard process.terminationStatus == 0 else { throw LibraryError.pdfSaveFailed }
            return try JSONDecoder().decode([PaperAnnotation].self, from: Data(contentsOf: output))
        }.value
    }
}
