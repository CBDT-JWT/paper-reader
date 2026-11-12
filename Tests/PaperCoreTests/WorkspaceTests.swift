import XCTest
import Foundation
import PaperCore

final class WorkspaceTests: XCTestCase, @unchecked Sendable {
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderWorkspace-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func open(_ folder: URL, device: URL) throws -> LibraryStore {
        try LibraryStore(root: device.appendingPathComponent("Records"), indexURL: device.appendingPathComponent("index.sqlite"), documentsRoot: folder)
    }
    func testOpenExistingHierarchyWithoutCopyAndKeepIdentityAfterReopen() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Papers"), nested = folder.appendingPathComponent("Circuits/Analog")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let pdf = nested.appendingPathComponent("原文 2.pdf"); try DemoPaper.create(at: pdf)
        let original = try Data(contentsOf: pdf)
        let store = try open(folder, device: root.appendingPathComponent("DeviceA"))
        let papers = try await store.scanWorkspace(); let paper = try XCTUnwrap(papers.first)
        XCTAssertEqual(papers.count, 1); XCTAssertEqual(store.pdfURL(paper.id).resolvingSymlinksInPath(), pdf.resolvingSymlinksInPath())
        let folders = try await store.folders(); XCTAssertEqual(folders.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(paper.id).appendingPathComponent("paper.pdf").path))
        let before = try await store.readNote(paper.id)
        _ = try await store.saveNote(paper.id, markdown: "# Note\n\n$E=mc^2$", expectedRevision: before.revision)
        try await store.persistReading(paper.id, page: 2, scale: 1.7, point: .init(x: 50, y: 90))
        let another = try open(folder, device: root.appendingPathComponent("DeviceB"))
        let remote = try await another.scanWorkspace()
        XCTAssertEqual(remote.first?.id, paper.id); XCTAssertEqual(remote.first?.page, 0)
        let remoteNote = try await another.readNote(paper.id); XCTAssertTrue(remoteNote.markdown.contains("$E=mc^2$"))
        XCTAssertEqual(try Data(contentsOf: pdf), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("library.sqlite").path))
        await another.close(); await store.close()
    }
    func testReadingPositionNeverRewritesSharedManifestAndSurvivesMetadataEdit() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("source.pdf"); try DemoPaper.create(at: pdf)
        let store = try open(root, device: root.appendingPathComponent(".device"))
        let scanned = try await store.scanWorkspace(); let paper = try XCTUnwrap(scanned.first)
        let manifest = store.directory(paper.id).appendingPathComponent("paper.json")
        let bytes = try Data(contentsOf: manifest)
        try await store.persistReading(paper.id, page: 2, scale: 1.4, point: nil)
        XCTAssertEqual(try Data(contentsOf: manifest), bytes)
        try await store.organize(.renamePaper(paper.id, "renamed.pdf"))
        let record = try await store.record(paper.id); XCTAssertEqual(record.page, 2); XCTAssertEqual(record.scale, 1.4)
        XCTAssertEqual(store.pdfURL(paper.id).lastPathComponent, "renamed.pdf")
        await store.close()
    }
    func testPhysicalMovesKeepLinkedNoteAndRejectOverwriteAndCycles() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("paper.pdf"); try DemoPaper.create(at: original)
        let store = try open(root, device: root.appendingPathComponent(".device"))
        let scanned = try await store.scanWorkspace(); let paper = try XCTUnwrap(scanned.first)
        let group = LibraryFolder(name: "Research"); try await store.organize(.createFolder(group))
        try await store.organize(.movePaper(paper.id, group.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Research/paper.pdf").path))
        try await store.organize(.renameFolder(group.id, "Renamed"))
        XCTAssertEqual(store.pdfURL(paper.id).resolvingSymlinksInPath(), root.appendingPathComponent("Renamed/paper.pdf").resolvingSymlinksInPath())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.noteURL(paper.id).path))
        let child = LibraryFolder(name: "Child", parentID: group.id); try await store.organize(.createFolder(child))
        do { try await store.organize(.moveFolder(group.id, child.id)); XCTFail("cycle accepted") } catch {}
        do { try await store.organize(.removeFolder(group.id)); XCTFail("nonempty original folder removed") } catch {}
        let collision = root.appendingPathComponent("Renamed/collision.pdf"); try DemoPaper.create(at: collision)
        let bytes = try Data(contentsOf: collision)
        do { try await store.organize(.renamePaper(paper.id, "collision.pdf")); XCTFail("overwrite accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: collision), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.pdfURL(paper.id).path))
        await store.close()
    }
    func testFinderRenameReusesStableIdentityAndTrashDoesNotReimportSource() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("paper.pdf"); try DemoPaper.create(at: pdf)
        let store = try open(root, device: root.appendingPathComponent(".device"))
        let scanned = try await store.scanWorkspace(); let paper = try XCTUnwrap(scanned.first)
        try FileManager.default.moveItem(at: pdf, to: root.appendingPathComponent("from-finder.pdf"))
        let rescanned = try await store.scanWorkspace()
        XCTAssertEqual(rescanned.count, 1); XCTAssertEqual(rescanned.first?.id, paper.id)
        try await store.trash(paper.id)
        let active = try await store.scanWorkspace(); XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("from-finder.pdf").path))
        _ = try await store.restore(paper.id)
        let restored = try await store.scanWorkspace(); XCTAssertEqual(restored.first?.id, paper.id)
        await store.close()
    }
    func testCoordinatedConcurrentEditsPreserveBothVersions() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let a = try open(root, device: root.appendingPathComponent(".a")), b = try open(root, device: root.appendingPathComponent(".b"))
        let scanned = try await a.scanWorkspace(); let paper = try XCTUnwrap(scanned.first); _ = try await b.scanWorkspace()
        let base = try await a.readNote(paper.id)
        _ = try await b.saveNote(paper.id, markdown: "Remote edit", expectedRevision: base.revision)
        do { _ = try await a.saveNote(paper.id, markdown: "Local edit", expectedRevision: base.revision); XCTFail("stale save accepted") } catch LibraryError.externalChange {}
        let current = try await b.readNote(paper.id); XCTAssertEqual(current.markdown, "Remote edit")
        let copies = try FileManager.default.contentsOfDirectory(at: a.directory(paper.id), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("note-conflict-") }
        XCTAssertEqual(copies.count, 1); XCTAssertEqual(try String(contentsOf: copies[0], encoding: .utf8), "Local edit")
        await a.close(); await b.close()
    }
    func testLibraryCopyPreservesUUIDAssetsAndSourceWithoutSyncingDatabaseOrConversations() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.pdf"); try DemoPaper.create(at: original)
        let store = try LibraryStore(root: root.appendingPathComponent("Local"))
        let paper = try await store.importPDF(from: original)
        let source = SourceReference(paperID: paper.id, page: 0, rect: .init(x: 1, y: 2, width: 3, height: 4), asset: "assets/test.png")
        try await store.addSource(source, image: Data([1, 2, 3]))
        try await store.saveSidecar(paper.id, name: "conversation.json", data: Data("private conversation".utf8))
        let target = root.appendingPathComponent("Cloud/.paper-reader")
        try await store.copyLibrary(to: target)
        let copy = try LibraryStore(root: target, indexURL: root.appendingPathComponent("OtherDevice/index.sqlite"))
        let migrated = try await copy.papers(); XCTAssertEqual(migrated.first?.id, paper.id)
        XCTAssertEqual(try Data(contentsOf: copy.pdfURL(paper.id)), try Data(contentsOf: original))
        let references = try await copy.sources(paper.id); XCTAssertEqual(references, [source])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("library.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.directory(paper.id).appendingPathComponent("conversation.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.pdfURL(paper.id).path))
        await copy.close(); await store.close()
    }
    func testRemovingAPaperRetainsTheWorkspaceNote() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let store = try open(root, device: root.appendingPathComponent(".device"))
        let scanned = try await store.scanWorkspace(); let paper = try XCTUnwrap(scanned.first)
        let note = try await store.readNote(paper.id)
        try await store.trash(paper.id)
        _ = try await store.saveNote(paper.id, markdown: "Shared work", expectedRevision: note.revision)
        let current = try await store.readNote(paper.id)
        XCTAssertEqual(current.markdown, "Shared work")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(paper.id).path))
        let remaining = try await store.scanWorkspace(); XCTAssertTrue(remaining.isEmpty)
        await store.close()
    }
    func testBrokenSharedManifestDoesNotCreateDuplicatePaperOrOverwriteNotes() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try DemoPaper.create(at: root.appendingPathComponent("paper.pdf"))
        let store = try open(root, device: root.appendingPathComponent(".device"))
        let scanned = try await store.scanWorkspace(); let paper = try XCTUnwrap(scanned.first)
        let noteBytes = try Data(contentsOf: store.noteURL(paper.id))
        try Data("broken".utf8).write(to: store.directory(paper.id).appendingPathComponent("paper.json"))
        do { _ = try await store.scanWorkspace(); XCTFail("broken workspace accepted") } catch LibraryError.invalidWorkspace {}
        XCTAssertEqual(try Data(contentsOf: store.noteURL(paper.id)), noteBytes)
        let directories = try FileManager.default.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil).filter { UUID(uuidString: $0.lastPathComponent) != nil }
        XCTAssertEqual(directories.count, 1)
        await store.close()
    }
    func testUnhydratedCloudMetadataCannotBeSilentlyRecreated() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let metadata = root.appendingPathComponent(".paper-reader/\(UUID())")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: metadata.appendingPathComponent(".paper.json.icloud"))
        let store = try open(root, device: root.appendingPathComponent(".device"))
        do { _ = try await store.scanWorkspace(); XCTFail("incomplete cloud library accepted") } catch LibraryError.workspaceDownloading {}
        try Data("placeholder".utf8).write(to: store.root.appendingPathComponent(".folders.json.icloud"))
        do { _ = try await store.folders(); XCTFail("evicted folders treated as empty") } catch LibraryError.workspaceDownloading {}
        do { try await store.saveFolders([]); XCTFail("evicted folders overwritten") } catch LibraryError.workspaceDownloading {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.appendingPathComponent("paper.json").path))
        await store.close()
    }
}
