import XCTest
import Foundation
import PaperCore

final class LibraryStoreTests: XCTestCase, @unchecked Sendable {
    func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testStableIdentityCopySafetyAtomicNotesAndRecovery() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.pdf")
        try DemoPaper.create(at: original)
        let originalBytes = try Data(contentsOf: original)
        let library = root.appendingPathComponent("Library")
        let store = try LibraryStore(root: library)
        var paper = try await store.importPDF(from: original)
        let first = try await store.readNote(paper.id)
        let markdown = "# Research\n\n$E=mc^2$\n\n![Figure](assets/figure.png)\n"
        let revision = try await store.saveNote(paper.id, markdown: markdown, expectedRevision: first.revision)
        XCTAssertEqual(revision, LibraryStore.revision(markdown))
        let saved = try await store.readNote(paper.id)
        XCTAssertEqual(saved.markdown, markdown)
        XCTAssertEqual(try String(contentsOf: store.directory(paper.id).appendingPathComponent("note.previous.md"), encoding: .utf8), first.markdown)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertEqual(try Data(contentsOf: store.pdfURL(paper.id)), originalBytes)
        paper.title = "Renamed paper"; paper.page = 2; paper.scale = 1.5
        try await store.persist(paper)
        await store.close()
        // Simulate index loss. Files and manifests reconstruct the catalog.
        try FileManager.default.removeItem(at: library.appendingPathComponent("library.sqlite"))
        let reopened = try LibraryStore(root: library)
        let recovered = try await reopened.papers()
        XCTAssertEqual(recovered, [paper])
        let recoveredNote = try await reopened.readNote(paper.id)
        XCTAssertEqual(recoveredNote.markdown, markdown)
        await reopened.close()
    }
    func testExternalModificationCreatesConflictWithoutOverwritingExternalNote() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("source.pdf"); try DemoPaper.create(at: pdf)
        let store = try LibraryStore(root: root.appendingPathComponent("Library"))
        let paper = try await store.importPDF(from: pdf)
        let snapshot = try await store.readNote(paper.id)
        try Data("external version".utf8).write(to: store.noteURL(paper.id), options: .atomic)
        do {
            _ = try await store.saveNote(paper.id, markdown: "my version", expectedRevision: snapshot.revision)
            XCTFail("Expected a conflict")
        } catch LibraryError.externalChange {} catch { throw error }
        let external = try await store.readNote(paper.id)
        XCTAssertEqual(external.markdown, "external version")
        let files = try FileManager.default.contentsOfDirectory(at: store.directory(paper.id), includingPropertiesForKeys: nil)
        let conflict = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("note-conflict-") })
        XCTAssertEqual(try String(contentsOf: conflict, encoding: .utf8), "my version")
        await store.close()
    }
    func testSourceIndexAndExportPreserveRelativeAssets() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("source.pdf"); try DemoPaper.create(at: pdf)
        let store = try LibraryStore(root: root.appendingPathComponent("Library"))
        let paper = try await store.importPDF(from: pdf)
        let source = SourceReference(paperID: paper.id, page: 1, rect: .init(x: 20, y: 30, width: 100, height: 80), asset: "assets/crop.png")
        let bytes = Data([1, 2, 3, 4]); try await store.addSource(source, image: bytes)
        let sources = try await store.sources(paper.id); XCTAssertEqual(sources, [source])
        let destination = root.appendingPathComponent("Export")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await store.exportNote(paper.id, to: destination)
        let exported = destination.appendingPathComponent(paper.id.uuidString)
        XCTAssertEqual(try Data(contentsOf: exported.appendingPathComponent("assets/crop.png")), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("note.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.appendingPathComponent("paper.pdf").path))
        await store.close()
    }
    func testResourceContainmentRejectsTraversalAbsolutePathsAndSymlinks() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try LibraryStore.containedURL("../secret", in: root))
        XCTAssertThrowsError(try LibraryStore.containedURL("/etc/passwd", in: root))
        XCTAssertThrowsError(try LibraryStore.containedURL("https://example.com/a", in: root))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try LibraryStore.containedURL("escape/secret", in: root))
        XCTAssertEqual(try LibraryStore.containedURL("assets/figure.png", in: root), root.appendingPathComponent("assets/figure.png"))
    }
}
