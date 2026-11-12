import XCTest
import Foundation
import PDFKit
import PaperCore

final class FolderDocumentTests: XCTestCase, @unchecked Sendable {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderDocuments-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func store(_ root: URL, device: String = ".device") throws -> LibraryStore {
        try LibraryStore(root: root.appendingPathComponent(device + "/Records"), indexURL: root.appendingPathComponent(device + "/index.sqlite"), documentsRoot: root)
    }
    func testOneSharedMarkdownAndRootAssetsAcrossNestedPapers() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let subfolder = root.appendingPathComponent("Original layout")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try DemoPaper.create(at: root.appendingPathComponent("one.pdf"))
        try DemoPaper.create(at: subfolder.appendingPathComponent("two.pdf"))
        let library = try store(root)
        let papers = try await library.scanWorkspace()
        XCTAssertEqual(papers.count, 2)
        XCTAssertEqual(library.noteURL(papers[0].id), root.appendingPathComponent("notes.md"))
        XCTAssertEqual(library.noteURL(papers[1].id), library.noteURL(papers[0].id))
        let before = try await library.readNote(papers[0].id)
        _ = try await library.saveNote(papers[0].id, markdown: "Shared **research**", expectedRevision: before.revision)
        let second = try await library.readNote(papers[1].id)
        XCTAssertEqual(second.markdown, "Shared **research**")
        let image = root.appendingPathComponent("input.png"); try Data([1, 2, 3]).write(to: image)
        let asset = try await library.importAsset(papers[1].id, from: image)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(asset)), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".paper-reader").path))
        let markdownFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }
        XCTAssertEqual(markdownFiles.count, 1)
        await library.close()
    }
    func testExistingMarkdownIsOpenedInPlaceAndDeletionDoesNotRecreateIt() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let markdown = root.appendingPathComponent("My research.md")
        let contents = "# Existing\n\n**Bold** and *italic*.\n"
        try Data(contents.utf8).write(to: markdown)
        let library = try store(root)
        _ = try await library.scanWorkspace()
        XCTAssertEqual(library.noteURL(library.sharedNoteID), markdown)
        let snapshot = try await library.readNote(library.sharedNoteID)
        XCTAssertEqual(snapshot.markdown, contents)
        let renamed = root.appendingPathComponent("Renamed note.md")
        try FileManager.default.moveItem(at: markdown, to: renamed)
        _ = try await library.scanWorkspace()
        XCTAssertEqual(library.noteURL(library.sharedNoteID).resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
        try FileManager.default.removeItem(at: renamed)
        _ = try await library.scanWorkspace()
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdown.path))
        do { _ = try await library.saveNote(library.sharedNoteID, markdown: "Local edit", expectedRevision: snapshot.revision); XCTFail("Deleted document overwritten") }
        catch LibraryError.externalChange {}
        await library.close()
    }
    func testLegacyPaperNotesMergeOnceAndKeepCollidingAssetNames() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent(".original.pdf"); try DemoPaper.create(at: original)
        let legacy = try LibraryStore(root: root.appendingPathComponent(".paper-reader"))
        let a = try await legacy.importPDF(from: original), b = try await legacy.importPDF(from: original)
        for (paper, value) in [(a, "First paper"), (b, "Second paper")] {
            let source = SourceReference(paperID: paper.id, page: 0, rect: .init(x: 10, y: 20, width: 30, height: 40), asset: "assets/figure.png")
            try await legacy.addSource(source, image: Data(value.utf8))
            let old = try await legacy.readNote(paper.id)
            _ = try await legacy.saveNote(paper.id, markdown: "# \(value)\n\n![Figure](assets/figure.png)\n\n[Source](\(source.link))\n", expectedRevision: old.revision)
        }
        await legacy.close()
        try Data("# Existing workspace\n".utf8).write(to: root.appendingPathComponent("notes.md"))
        let library = try store(root)
        let papers = try await library.scanWorkspace()
        XCTAssertEqual(Set(papers.map(\.id)), Set([a.id, b.id]))
        let note = try await library.readNote(a.id)
        XCTAssertTrue(note.markdown.contains("Existing workspace"))
        XCTAssertTrue(note.markdown.contains("First paper")); XCTAssertTrue(note.markdown.contains("Second paper"))
        XCTAssertTrue(note.markdown.contains("paperreader://document?"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("assets/\(a.id)/figure.png"), encoding: .utf8), "First paper")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("assets/\(b.id)/figure.png"), encoding: .utf8), "Second paper")
        _ = try await library.scanWorkspace()
        let repeated = try await library.readNote(b.id)
        XCTAssertEqual(repeated.markdown, note.markdown)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.pdfURL(a.id).path))
        XCTAssertFalse(library.pdfURL(a.id).path.contains(".paper-reader"))
        await library.close()
    }
    func testRepeatedLegacyDiscoveryKeepsOnePaperAndPreservesRecoveredContent() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let library = try store(root)
        let initial = try await library.scanWorkspace()
        let paper = try XCTUnwrap(initial.first)
        var duplicate = Paper(title: paper.title, importedAt: paper.importedAt.addingTimeInterval(1))
        duplicate.fileName = paper.fileName; duplicate.sourceRelativePath = paper.sourceRelativePath
        let legacy = root.appendingPathComponent(".paper-reader/" + duplicate.id.uuidString)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try JSONEncoder().encode(duplicate).write(to: legacy.appendingPathComponent("paper.json"))
        try Data("Recovered duplicate contribution.\n".utf8).write(to: legacy.appendingPathComponent("note.md"))
        let annotation = PaperAnnotation(page: 0, kind: .rectangle, rect: .init(x: 40, y: 80, width: 90, height: 60))
        try JSONEncoder().encode([annotation]).write(to: legacy.appendingPathComponent("annotations.json"))
        let scanned = try await library.scanWorkspace()
        XCTAssertEqual(scanned.map(\.id), [paper.id])
        let annotations = try await library.annotations(paper.id)
        XCTAssertEqual(annotations, [annotation])
        let note = try await library.readNote(paper.id)
        XCTAssertTrue(note.markdown.contains("Recovered duplicate contribution."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.root.appendingPathComponent("Recovered Legacy Records/" + duplicate.id.uuidString).path))
        _ = try await library.scanWorkspace()
        let repeated = try await library.readNote(paper.id)
        XCTAssertEqual(repeated.markdown, note.markdown)
        await library.close()
    }
    func testSharedNoteExportIncludesOneMarkdownAndAssets() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let library = try store(root)
        let scanned = try await library.scanWorkspace()
        let paper = try XCTUnwrap(scanned.first)
        let source = SourceReference(paperID: paper.id, page: 0, rect: .init(x: 10, y: 20, width: 30, height: 40), asset: "assets/capture.png")
        try await library.addSource(source, image: Data([1, 2, 3]))
        let output = root.appendingPathComponent(".export")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await library.exportNote(paper.id, to: output)
        let exported = output.appendingPathComponent(paper.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("notes.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("assets/capture.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.appendingPathComponent("paper.json").path))
        await library.close()
    }
    func testCopyingASharedWorkspacePreservesNoteAndAssets() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source"), target = root.appendingPathComponent("Target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try DemoPaper.create(at: source.appendingPathComponent("one.pdf"))
        try DemoPaper.create(at: source.appendingPathComponent("two.pdf"))
        let original = try store(source)
        let papers = try await original.scanWorkspace()
        let reference = SourceReference(paperID: papers[1].id, page: 0, rect: .init(x: 10, y: 20, width: 30, height: 40), asset: "assets/source.png")
        try await original.addSource(reference, image: Data([9, 8, 7]))
        let before = try await original.readNote(papers[0].id)
        let markdown = "# Shared\n\n![Image](assets/source.png)\n\n[PDF](" + (await original.sourceLink(reference)) + ")\n"
        _ = try await original.saveNote(papers[0].id, markdown: markdown, expectedRevision: before.revision)
        let metadata = root.appendingPathComponent(".target-device/Records")
        try await original.copyLibrary(to: metadata)
        let copied = try LibraryStore(root: metadata, indexURL: root.appendingPathComponent(".target-device/index.sqlite"), documentsRoot: target)
        let scanned = try await copied.scanWorkspace()
        XCTAssertEqual(Set(scanned.map(\.id)), Set(papers.map(\.id)))
        let note = try await copied.readNote(papers[0].id)
        XCTAssertEqual(note.markdown, markdown)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("assets/source.png")), Data([9, 8, 7]))
        await original.close(); await copied.close()
    }
    func testPDFSaveUndoAndExternalAnnotationsArePreserved() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("paper.pdf"); try DemoPaper.create(at: pdf)
        try await MainActor.run {
            let document = try XCTUnwrap(PDFDocument(url: pdf))
            let native = PDFAnnotation(bounds: .init(x: 20, y: 30, width: 80, height: 60), forType: .square, withProperties: nil)
            native.contents = "Existing annotation from another editor"
            document.page(at: 0)!.addAnnotation(native)
            XCTAssertTrue(document.write(to: pdf))
        }
        let library = try store(root)
        let scanned = try await library.scanWorkspace()
        let paper = try XCTUnwrap(scanned.first)
        let original = try Data(contentsOf: pdf)
        let record = PaperAnnotation(page: 0, kind: .rectangle, rect: .init(x: 50, y: 100, width: 200, height: 90))
        try await library.saveAnnotations(paper.id, records: [record])
        let saved = try await library.annotations(paper.id)
        XCTAssertEqual(saved, [record]); XCTAssertNotEqual(try Data(contentsOf: pdf), original)
        try await library.saveAnnotations(paper.id, records: [record])
        try await MainActor.run {
            let annotations = try XCTUnwrap(PDFDocument(url: pdf)?.page(at: 0)?.annotations)
            XCTAssertEqual(annotations.count, 2)
            XCTAssertTrue(annotations.contains { $0.contents == "Existing annotation from another editor" })
        }
        try await library.saveAnnotations(paper.id, records: [])
        try await MainActor.run { XCTAssertEqual(PDFDocument(url: pdf)?.page(at: 0)?.annotations.count, 1) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.directory(paper.id).appendingPathComponent("annotations.json").path))
        await library.close()
    }
    func testLegacyAnnotationsMigrateIntoPDFExactlyOnce() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let library = try store(root)
        let scanned = try await library.scanWorkspace()
        let paper = try XCTUnwrap(scanned.first)
        let record = PaperAnnotation(page: 0, kind: .highlight, rect: .init(x: 50, y: 500, width: 120, height: 12))
        let legacy = library.directory(paper.id).appendingPathComponent("annotations.json")
        try JSONEncoder().encode([record]).write(to: legacy)
        let first = try await library.annotations(paper.id), second = try await library.annotations(paper.id)
        XCTAssertEqual(first, [record]); XCTAssertEqual(second, [record])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        await library.close()
    }
    func testStandardPDFAnnotationTypesAndGeometryAreSaved() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let library = try store(root)
        let scanned = try await library.scanWorkspace()
        let paper = try XCTUnwrap(scanned.first)
        let rect = PDFRect(x: 40, y: 100, width: 120, height: 30)
        let records = [PaperAnnotation(page: 0, kind: .highlight, rect: rect),
                       PaperAnnotation(page: 0, kind: .line, rect: rect, points: [.init(x: 45, y: 105), .init(x: 155, y: 125)]),
                       PaperAnnotation(page: 0, kind: .rectangle, rect: rect),
                       PaperAnnotation(page: 0, kind: .ink, rect: rect, points: [.init(x: 45, y: 105), .init(x: 100, y: 120), .init(x: 155, y: 125)])]
        try await library.saveAnnotations(paper.id, records: records)
        let url = library.pdfURL(paper.id)
        try await MainActor.run {
            let annotations = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)?.annotations)
            XCTAssertEqual(Set(annotations.compactMap(\.type)), Set(["Highlight", "Line", "Square", "Ink"]))
            let highlight = try XCTUnwrap(annotations.first { $0.type == "Highlight" })
            XCTAssertEqual(highlight.quadrilateralPoints?.count, 4)
            let line = try XCTUnwrap(annotations.first { $0.type == "Line" })
            XCTAssertEqual(line.startPoint, CGPoint(x: 5, y: 5)); XCTAssertEqual(line.endPoint, CGPoint(x: 115, y: 25))
            let ink = try XCTUnwrap(annotations.first { $0.type == "Ink" })
            XCTAssertEqual(ink.paths?.count, 1)
        }
        await library.close()
    }
    func testFractionalAnnotationGeometrySurvivesPDFNumericRounding() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let library = try store(root)
        let scanned = try await library.scanWorkspace()
        let paper = try XCTUnwrap(scanned.first)
        let rect = PDFRect(x: 208.81244868786868, y: 440.8502463681748, width: 90.55300879005918, height: 4.083780206196479)
        let line = PaperAnnotation(page: 1, kind: .line, rect: rect,
                                   points: [.init(x: rect.x + 2, y: rect.y + 2), .init(x: rect.x + rect.width - 2, y: rect.y + rect.height - 2)])
        try await library.saveAnnotations(paper.id, records: [line])
        let reopened = try await library.annotations(paper.id)
        XCTAssertEqual(reopened, [line])
        await library.close()
    }
    func testEmbeddedRecordSurvivesMissingStandardAnnotationName() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("paper.pdf")
        try DemoPaper.create(at: pdf)
        let record = PaperAnnotation(page: 0, kind: .rectangle, rect: .init(x: 40, y: 60, width: 120, height: 80))
        try await MainActor.run {
            let document = try XCTUnwrap(PDFDocument(url: pdf))
            let annotation = PDFAnnotation(bounds: record.rect.cgRect, forType: .square, withProperties: nil)
            XCTAssertTrue(annotation.setValue(String(decoding: try JSONEncoder().encode(record), as: UTF8.self),
                                              forAnnotationKey: PDFAnnotationKey(rawValue: "/PaperReaderRecord")))
            XCTAssertNil(annotation.value(forAnnotationKey: .name))
            document.page(at: 0)!.addAnnotation(annotation)
            XCTAssertTrue(document.write(to: pdf))
            XCTAssertEqual(try PDFFileAnnotations.read(pdf), [record])
            try PDFFileAnnotations.write(pdf, records: [], expected: [record])
            XCTAssertEqual(PDFDocument(url: pdf)?.page(at: 0)?.annotations.count, 0)
        }
    }
    func testConcurrentPDFEditsRejectStaleWritesWithoutLosingExternalWork() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let a = try store(root, device: ".a"), b = try store(root, device: ".b")
        let scanned = try await a.scanWorkspace()
        let paper = try XCTUnwrap(scanned.first)
        _ = try await b.scanWorkspace(); _ = try await a.annotations(paper.id); _ = try await b.annotations(paper.id)
        let external = PaperAnnotation(page: 0, kind: .rectangle, rect: .init(x: 40, y: 50, width: 80, height: 90))
        try await a.saveAnnotations(paper.id, records: [external])
        let bytes = try Data(contentsOf: a.pdfURL(paper.id))
        do { try await b.saveAnnotations(paper.id, records: []); XCTFail("Stale write accepted") }
        catch LibraryError.pdfAnnotationsChanged {}
        XCTAssertEqual(try Data(contentsOf: a.pdfURL(paper.id)), bytes)
        await a.close(); await b.close()
    }
}
