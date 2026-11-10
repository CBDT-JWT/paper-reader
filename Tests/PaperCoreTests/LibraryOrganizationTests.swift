import XCTest
import PaperCore

final class LibraryOrganizationTests: XCTestCase, @unchecked Sendable {
    func testFilenameNaturalSortIsIndependentOfTitleAndWorksInBothDirections() throws {
        var ten = Paper(title: "A title", importedAt: Date(timeIntervalSince1970: 1)); ten.fileName = "paper10.pdf"
        var two = Paper(title: "Z title", importedAt: Date(timeIntervalSince1970: 2)); two.fileName = "paper2.pdf"
        var one = Paper(title: "M title", importedAt: Date(timeIntervalSince1970: 3)); one.fileName = "Paper1.PDF"
        let records = [ten, one, two]
        XCTAssertEqual(LibrarySort.filename.ordered(records).map(\.id), [one.id, two.id, ten.id])
        XCTAssertEqual(LibrarySort.filename.ordered(records, ascending: false).map(\.id), [ten.id, two.id, one.id])
        XCTAssertEqual(LibrarySort.title.ordered(records).map(\.id), [ten.id, one.id, two.id])
        XCTAssertEqual(LibrarySort.recent.ordered(records).map(\.id), [one.id, two.id, ten.id])
        XCTAssertEqual(Paper(title: "Legacy name").displayFileName, "Legacy name.pdf")
    }
    func testOrganizationLifecyclePersistsAndPreservesFilesAndNewerFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderFolders-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("02_original.PDF"); try DemoPaper.create(at: original)
        let bytes = try Data(contentsOf: original)
        let store = try LibraryStore(root: root.appendingPathComponent("Library"))
        let first = LibraryFolder(name: "Folder 10"), second = LibraryFolder(name: "Folder 2")
        let child = LibraryFolder(name: "Child", parentID: first.id)
        for folder in [first, second, child] { try await store.organize(.createFolder(folder)) }
        var paper = try await store.importPDF(from: original, folderID: child.id)
        XCTAssertEqual(paper.fileName, "02_original.PDF"); XCTAssertEqual(paper.folderID, child.id)
        let note = try await store.readNote(paper.id)
        _ = try await store.saveNote(paper.id, markdown: "# Keep my evidence", expectedRevision: note.revision)
        try await store.organize(.renameFolder(first.id, "Renamed"))
        try await store.organize(.moveFolder(child.id, second.id))
        do { try await store.organize(.moveFolder(second.id, child.id)); XCTFail("Descendant cycles must fail") } catch LibraryError.invalidPath {}
        do { try await store.organize(.createFolder(LibraryFolder(name: "../invalid"))); XCTFail("Invalid names must fail") } catch LibraryError.invalidName {}
        try await store.organize(.renamePaper(paper.id, "Renamed file"))
        try await store.persistReading(paper.id, page: 2, scale: 1.4, point: .init(x: 80, y: 400))
        try await store.persistMetadata(paper.id, metadata: Bibliography(title: "Real metadata title"))
        paper = try await store.papers().first!
        XCTAssertEqual(paper.title, "Renamed file"); XCTAssertEqual(paper.fileName, "Renamed file.pdf"); XCTAssertEqual(paper.folderID, child.id)
        try await store.organize(.removeFolder(second.id))
        let reparented = try await store.folders().first { $0.id == child.id }
        XCTAssertNil(reparented?.parentID)
        try await store.organize(.removeFolder(child.id))
        let records = try await store.papers(); let saved = records.first!
        XCTAssertNil(saved.folderID); XCTAssertEqual(saved.page, 2); XCTAssertEqual(saved.metadata?.title, "Real metadata title")
        XCTAssertEqual(try Data(contentsOf: store.pdfURL(paper.id)), bytes)
        let finalNote = try await store.readNote(paper.id); XCTAssertEqual(finalNote.markdown, "# Keep my evidence")
        await store.close()
        let reopened = try LibraryStore(root: store.root)
        let recovered = try await reopened.papers(); XCTAssertEqual(recovered.first, saved)
        let groups = try await reopened.folders(); XCTAssertEqual(groups.map(\.name), ["Renamed"])
        await reopened.close()
    }
}
