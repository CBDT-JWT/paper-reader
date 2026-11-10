import AppKit
import PaperCore

@MainActor enum WorkspaceSelfTest {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    static func run(bootstrap: AppBootstrap) async {
        var checks: [String] = []
        let env = ProcessInfo.processInfo.environment
        let output = URL(fileURLWithPath: env["PAPER_READER_TEST_OUTPUT"] ?? "/tmp/paper-reader-workspace-integration.json")
        func check(_ condition: Bool, _ message: String) throws { guard condition else { throw Failure(message: message) }; checks.append(message) }
        func wait(_ condition: () async throws -> Bool) async throws {
            for _ in 0..<200 { if try await condition() { return }; try await Task.sleep(for: .milliseconds(100)) }
            throw Failure(message: "Timed out waiting for real workspace/editor state")
        }
        do {
            guard let original = bootstrap.model, env["PAPER_READER_LIBRARY"] != nil else { throw Failure(message: "Isolated test library required") }
            try await wait { original.editor.ready }
            await original.openDemo(); await original.save()
            guard let id = original.selectedID else { throw Failure(message: "Demo paper missing") }
            await original.capture(page: 0, rect: .init(x: 48, y: 210, width: 516, height: 128)); await original.save()
            let saved = try await original.store.readNote(id)
            let crashJournal = NoteDraftJournal(deviceDirectory: original.store.deviceDirectory)
            try await crashJournal.stage(id, markdown: saved.markdown + "\nRecovered local draft.\n", baseRevision: saved.revision, sequence: 1)
            await original.select(id)
            let recovered = try await original.store.readNote(id)
            try check(recovered.markdown.contains("Recovered local draft."), "Reopening a paper restores and saves its independent local draft in the real editor")
            await original.save()
            let originalNote = try await original.store.readNote(id)
            let originalBytes = try Data(contentsOf: original.store.pdfURL(id))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderWorkspaceIntegration-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let shared = env["PAPER_READER_TEST_CLOUD_ROOT"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("Shared")
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            await bootstrap.openWorkspace(.init(folder: shared, isCloud: true), copyCurrent: true)
            guard let cloud = bootstrap.model else { throw Failure(message: "Cloud model missing") }
            try check(cloud !== original, "Native bootstrap switches the real workspace without restarting the process")
            try await wait { cloud.editor.ready && cloud.selectedID == id }
            let note = try await cloud.store.readNote(id)
            try check(note.markdown == originalNote.markdown, "Copy-to-iCloud retains the exact Markdown and stable paper UUID")
            try check(try Data(contentsOf: cloud.store.pdfURL(id)) == originalBytes, "Migration preserves original PDF bytes")
            try check(FileManager.default.fileExists(atPath: original.store.noteURL(id).path), "Original local library remains intact after switching")
            try check(!FileManager.default.fileExists(atPath: cloud.store.root.appendingPathComponent("library.sqlite").path) && !cloud.store.deviceDirectory.path.hasPrefix(shared.path), "SQLite and device data stay outside the shared folder")
            let bookmark = try bootstrap.preferences.data(forKey: WorkspaceLocation.bookmarkKey).unwrap()
            let restored = try WorkspaceLocation.resolve(bookmark: bookmark, cloud: true)
            try check(restored.folder.resolvingSymlinksInPath().standardizedFileURL.path == shared.resolvingSymlinksInPath().standardizedFileURL.path, "Workspace bookmark resolves to the selected directory")
            let bookmarkFile = root.appendingPathComponent("workspace.bookmark")
            try bookmark.write(to: bookmarkFile, options: .atomic)
            let verifier = Process(); verifier.executableURL = Bundle.main.executableURL
            verifier.arguments = ["--verify-workspace-bookmark", bookmarkFile.path, shared.path]
            try verifier.run()
            let bookmarkStatus = await Task.detached { verifier.waitUntilExit(); return verifier.terminationStatus }.value
            try check(bookmarkStatus == 0, "A fresh application process resolves the persisted workspace bookmark")
            try await wait { (try? await cloud.editor.call("diagnostics") as? [String: Any])?["imageCount"] as? Int == 1 }
            checks.append("Real WKWebView resolves migrated relative screenshot assets")
            let remote = try LibraryStore(root: cloud.store.root, indexURL: root.appendingPathComponent("SecondDevice/index.sqlite"), documentsRoot: shared)
            _ = try await remote.scanWorkspace()
            let base = try await remote.readNote(id)
            _ = try await remote.saveNote(id, markdown: base.markdown + "\n\nExternal workspace edit.\n", expectedRevision: base.revision)
            await cloud.refreshWorkspace()
            try await wait { (try? await cloud.editor.call("getMarkdown") as? String)?.contains("External workspace edit.") == true }
            checks.append("An independent store's coordinated note edit reloads in the actual editor")
            await remote.close()
            let folder = root.appendingPathComponent("Existing/Circuits")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pdf = folder.appendingPathComponent("paper.pdf"); try DemoPaper.create(at: pdf)
            await bootstrap.openWorkspace(.init(folder: folder.deletingLastPathComponent(), isCloud: false), copyCurrent: false)
            guard let linked = bootstrap.model else { throw Failure(message: "Folder model missing") }
            try await wait { linked.editor.ready && linked.selectedID != nil }
            let paper = try linked.currentPaper.unwrap()
            try check(linked.store.pdfURL(paper.id).resolvingSymlinksInPath() == pdf.resolvingSymlinksInPath(), "Open Folder reads the existing PDF in place instead of importing a duplicate")
            try check(linked.folders.contains { $0.name == "Circuits" }, "The actual file-tree model reflects existing folder hierarchy")
            let selected = paper.id
            guard await linked.organizeLibrary(.renamePaper(selected, "renamed.pdf")) else { throw Failure(message: "Native rename failed") }
            try check(linked.selectedID == selected && FileManager.default.fileExists(atPath: folder.appendingPathComponent("renamed.pdf").path), "Native rename moves the real PDF while keeping its note identity")
            let newPDF = folder.appendingPathComponent("new.pdf"); try DemoPaper.create(at: newPDF)
            await linked.refreshWorkspace()
            try await wait { linked.papers.count == 2 }
            checks.append("New filesystem PDFs appear through the production refresh path")
            await bootstrap.useLocalLibrary()
            guard let local = bootstrap.model else { throw Failure(message: "Local workspace missing") }
            try await wait { local.editor.ready && local.selectedID == id }
            try check(local.store.root == AppModel.defaultRoot, "Returning to the original local library restores its original note and PDF")
            await local.shutdown()
            let report: [String: Any] = ["success": true, "checks": checks, "date": ISO8601DateFormatter().string(from: .now), "realICloudFolderUsed": env["PAPER_READER_TEST_CLOUD_ROOT"] != nil]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
            print("WORKSPACE INTEGRATION PASS: \(checks.count) checks. \(output.path)")
            exit(0)
        } catch {
            let report: [String: Any] = ["success": false, "checks": checks, "error": error.localizedDescription]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(to: output)
            print("WORKSPACE INTEGRATION FAIL: \(error)")
            exit(1)
        }
    }
}
private extension Optional {
    func unwrap() throws -> Wrapped { guard let self else { throw WorkspaceSelfTest.Failure(message: "Missing required workspace value") }; return self }
}
