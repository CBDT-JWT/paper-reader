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
            let legacyReferences = try await original.store.sources(id)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderWorkspaceIntegration-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let shared = env["PAPER_READER_TEST_CLOUD_ROOT"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("Shared")
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            await bootstrap.openWorkspace(.init(folder: shared, isCloud: true), copyCurrent: true)
            guard let cloud = bootstrap.model else { throw Failure(message: "Cloud model missing") }
            try check(cloud !== original, "Native bootstrap switches the real workspace without restarting the process")
            try await wait { cloud.editor.ready && cloud.selectedID == id }
            let note = try await cloud.store.readNote(id)
            var expectedNote = originalNote.markdown.replacingOccurrences(of: "](assets/", with: "](assets/" + id.uuidString + "/")
            for reference in legacyReferences { expectedNote = expectedNote.replacingOccurrences(of: reference.link, with: await cloud.store.sourceLink(reference)) }
            let canonicalExpected = try await cloud.editor.call("rewriteImages", ["markdown": expectedNote, "paths": [String: String]()]) as? String ?? ""
            let canonicalActual = try await cloud.editor.call("rewriteImages", ["markdown": note.markdown, "paths": [String: String]()]) as? String ?? ""
            try check(!canonicalExpected.isEmpty && canonicalActual.contains(canonicalExpected.trimmingCharacters(in: .whitespacesAndNewlines)), "Copy-to-iCloud preserves Markdown semantics with migrated assets and portable PDF links")
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
            let remote = try LibraryStore(root: root.appendingPathComponent("SecondDevice/Records"), indexURL: root.appendingPathComponent("SecondDevice/index.sqlite"), documentsRoot: shared)
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
            let noteRoot = folder.deletingLastPathComponent()
            let figures = noteRoot.appendingPathComponent("figures")
            try FileManager.default.createDirectory(at: figures, withIntermediateDirectories: true)
            let originalReferences = try await original.store.sources(id)
            guard let originalImage = originalReferences.first?.asset else { throw Failure(message: "Original capture missing") }
            try FileManager.default.copyItem(at: original.store.noteDirectory(id).appendingPathComponent(originalImage), to: figures.appendingPathComponent("existing.png"))
            try Data("# Existing folder note\n\n![Existing image](figures/existing.png)\n".utf8).write(to: noteRoot.appendingPathComponent("Research.md"))
            await bootstrap.openWorkspace(.init(folder: folder.deletingLastPathComponent(), isCloud: false), copyCurrent: false)
            guard let linked = bootstrap.model else { throw Failure(message: "Folder model missing") }
            try await wait { linked.editor.ready && linked.selectedID != nil }
            let paper = try linked.currentPaper.unwrap()
            try check(linked.store.pdfURL(paper.id).resolvingSymlinksInPath() == pdf.resolvingSymlinksInPath(), "Open Folder reads the existing PDF in place instead of importing a duplicate")
            try check(linked.store.noteURL(paper.id).deletingLastPathComponent().standardizedFileURL == linked.store.documentsRoot?.standardizedFileURL, "Workspace Markdown is an ordinary file at the selected folder root")
            try check(!FileManager.default.fileExists(atPath: linked.store.documentsRoot!.appendingPathComponent(".paper-reader").path), "Opening an ordinary folder creates no hidden document library")
            try check(linked.folders.contains { $0.name == "Circuits" }, "The actual file-tree model reflects existing folder hierarchy")
            try await wait { try await linked.editor.webView.evaluateJavaScript("Array.from(document.querySelectorAll('.tiptap img')).some(i => i.getAttribute('src') === 'figures/existing.png' && i.complete && i.naturalWidth > 0)") as? Bool == true }
            checks.append("Existing Markdown and images stay in their original relative folder")
            let selected = paper.id
            guard await linked.organizeLibrary(.renamePaper(selected, "renamed.pdf")) else { throw Failure(message: "Native rename failed") }
            try check(linked.selectedID == selected && FileManager.default.fileExists(atPath: folder.appendingPathComponent("renamed.pdf").path), "Native rename moves the real PDF while keeping its note identity")
            let newPDF = folder.appendingPathComponent("new.pdf"); try DemoPaper.create(at: newPDF)
            await linked.refreshWorkspace()
            try await wait { linked.papers.count == 2 }
            checks.append("New filesystem PDFs appear through the production refresh path")
            let sharedBefore = try await linked.editor.call("getMarkdown") as? String ?? ""
            try await linked.editor.insert("\n\nShared workspace edit.\n")
            await linked.save()
            guard let secondPaper = linked.papers.first(where: { $0.id != selected }) else { throw Failure(message: "Second PDF missing") }
            await linked.select(secondPaper.id)
            try check((try await linked.editor.call("getMarkdown") as? String)?.contains("Shared workspace edit.") == true, "Switching PDFs keeps the same shared Markdown content")
            try check(linked.store.noteURL(selected) == linked.store.noteURL(secondPaper.id), "All PDFs in the opened folder share one note file")
            let undoSucceeded = try await linked.editor.call("format", "undo") as? Bool == true
            await linked.save()
            let restoredSharedNote = try await linked.editor.call("getMarkdown") as? String ?? ""
            try check(undoSucceeded && restoredSharedNote.trimmingCharacters(in: .whitespacesAndNewlines) == sharedBefore.trimmingCharacters(in: .whitespacesAndNewlines), "Shared-note undo history survives switching PDFs")
            await linked.capture(page: 0, rect: .init(x: 48, y: 210, width: 516, height: 128)); await linked.save()
            let references = try await linked.store.sources(secondPaper.id)
            guard let reference = references.last, let asset = reference.asset else { throw Failure(message: "Shared capture missing") }
            try check(FileManager.default.fileExists(atPath: linked.store.documentsRoot!.appendingPathComponent(asset).path), "Captured images live in the opened folder's assets directory")
            let sourceURL = URL(string: await linked.store.sourceLink(reference))!
            await linked.select(selected)
            await linked.openLink(sourceURL)
            try check(linked.selectedID == secondPaper.id, "Shared-note source links switch back to their original PDF")
            let pageCitation = try await linked.store.anchoringPageLinks("[p.2](paperreader://page/2)", to: secondPaper.id)
            let pageURL = URL(string: String(pageCitation.dropFirst(6).dropLast()))!
            await linked.select(selected)
            await linked.openLink(pageURL)
            try await wait { linked.selectedID == secondPaper.id && linked.reader.page == 1 }
            checks.append("Page-only AI citations switch to the originating paper and requested page")
            let annotation = PaperAnnotation(page: 0, kind: .rectangle, rect: .init(x: 80, y: 200, width: 90, height: 60))
            linked.reader.annotations.add([annotation]); await linked.reader.annotations.flush()
            let actual = try await linked.store.annotations(secondPaper.id)
            try check(actual.contains(annotation), "Workspace annotation saves reopen from the original PDF")
            try check(!FileManager.default.fileExists(atPath: linked.store.directory(secondPaper.id).appendingPathComponent("annotations.json").path), "Workspace annotation persistence uses no sidecar file")
            let beforeExample = try await linked.editor.call("getMarkdown") as? String ?? ""
            await linked.openDemo(); await linked.save()
            let afterExample = try await linked.editor.call("getMarkdown") as? String ?? ""
            try check(afterExample.contains(beforeExample.trimmingCharacters(in: .whitespacesAndNewlines)), "Opening the demo appends its example without replacing the shared workspace note")
            try check(linked.reader.view.pageShadowsEnabled == false, "PDF page shadows are disabled for the flat workspace")
            try check(linked.reader.view.window?.titlebarSeparatorStyle == NSTitlebarSeparatorStyle.none, "Native titlebar has no decorative separator")
            let appearance = linked.editor.webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            let noteBackground = try await linked.editor.webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
            try check(noteBackground == (appearance == .darkAqua ? "rgb(32, 36, 43)" : "rgb(255, 255, 255)"), "Offline editor colors follow the actual native light or dark appearance")
            await bootstrap.useLocalLibrary()
            guard let local = bootstrap.model else { throw Failure(message: "Local workspace missing") }
            try await wait { local.editor.ready && local.selectedID == id }
            try check(local.store.root == AppModel.defaultRoot, "Returning to the original local library restores its original note and PDF")
            if env["PAPER_READER_TEST_KEEP_OPEN"] != "1" { await local.shutdown() }
            let report: [String: Any] = ["success": true, "checks": checks, "date": ISO8601DateFormatter().string(from: .now), "realICloudFolderUsed": env["PAPER_READER_TEST_CLOUD_ROOT"] != nil, "appearance": appearance == .darkAqua ? "dark" : "light"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
            print("WORKSPACE INTEGRATION PASS: \(checks.count) checks. \(output.path)")
            if env["PAPER_READER_TEST_KEEP_OPEN"] == "1" {
                await bootstrap.openWorkspace(.init(folder: noteRoot, isCloud: false), copyCurrent: false, remember: false)
                return
            }
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
