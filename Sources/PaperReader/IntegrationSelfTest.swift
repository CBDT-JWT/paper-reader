import AppKit
import PDFKit
import PaperCore

/// Runs inside the real app/window/WKWebView, with an explicitly isolated test library.
@MainActor enum IntegrationSelfTest {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func run(model: AppModel) async {
        var checks: [String] = []
        var metrics: [String: Double] = [:]
        let output = ProcessInfo.processInfo.environment["PAPER_READER_TEST_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("paper-reader-integration.json")
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure(message: name) }; checks.append(name)
        }
        do {
            guard ProcessInfo.processInfo.environment["PAPER_READER_LIBRARY"] != nil else {
                throw Failure(message: "Self-test requires PAPER_READER_LIBRARY pointing to a disposable test directory")
            }
            let clock = ContinuousClock()
            let launch = clock.now
            try await eventually { model.editor.ready }
            metrics["offlineEditorReadyMs"] = milliseconds(launch.duration(to: clock.now))
            checks.append("Real WKWebView loaded bundled Tiptap offline")
            let language = AppLanguage.code
            try check(L("保存笔记") == (language == "en" ? "Save note" : "保存笔记"), "Native commands follow the process system language")
            let webLanguage = try await model.editor.webView.evaluateJavaScript("document.documentElement.lang") as? String
            try check(webLanguage == language, "Web editor uses the same system language as native menus")
            let opened = clock.now
            await model.openDemo()
            guard let firstID = model.selectedID else { throw Failure(message: "PDF import failed: \(model.error ?? "unknown")") }
            try check(model.reader.pageCount == 3, "PDFKit opened a real three-page PDF")
            metrics["fixtureGenerateImportAndOpenMs"] = milliseconds(opened.duration(to: clock.now))
            let originalPDF = try Data(contentsOf: model.store.pdfURL(firstID))
            let markdown = """
            # Research notebook

            A **bold** finding with *emphasis*, ~~revision~~ and ==evidence==.

            Inline $E = mc^2$ stays editable.

            $$
            \\int_0^1 x^2 \\, dx = \\frac{1}{3}
            $$

            - [ ] Replicate experiment
            - [x] Read methodology

            | Method | Accuracy |
            | --- | --- |
            | Ours | 0.95 |

            ```swift
            let paper = "local-first"
            ```

            ```mermaid
            flowchart LR
              Evidence --> Notes
            ```

            [External documentation](https://example.org)
            """
            try await model.editor.setDocument(id: firstID, markdown: markdown)
            try await eventually { (try? await model.editor.webView.evaluateJavaScript("document.querySelector('.mermaid-diagram')?.dataset.ready === 'true' && !!document.querySelector('.mermaid-diagram svg')")) as? Bool == true }
            checks.append("Bundled Mermaid rendered a real SVG offline in WKWebView")
            var diagnostics = try await model.editor.call("diagnostics") as? [String: Any] ?? [:]
            try check(diagnostics["mathCount"] as? Int == 2, "KaTeX rendered inline and block equations in WKWebView")
            // Click the real rendered formula, edit the actual source field, submit the UI form.
            _ = try await model.editor.webView.evaluateJavaScript("document.querySelector('[data-type=\"inline-math\"]').click()")
            let latex = try await model.editor.webView.evaluateJavaScript("document.querySelector('#math-input').value") as? String
            try check(latex == "E = mc^2", "Clicking a rendered equation reopens editable LaTeX")
            _ = try await model.editor.webView.evaluateJavaScript("document.querySelector('#math-input').value = 'E^2 = p^2c^2 + m^2c^4'; document.querySelector('#math-form').dispatchEvent(new Event('submit', {bubbles:true,cancelable:true})); true")
            var current = try await model.editor.call("getMarkdown") as? String ?? ""
            try check(current.contains("$E^2 = p^2c^2 + m^2c^4$"), "Formula source edits serialize back to standard Markdown")
            _ = try await model.editor.call("format", "undo")
            current = try await model.editor.call("getMarkdown") as? String ?? ""
            try check(current.contains("$E = mc^2$"), "Formula editing is undoable")
            try await model.editor.insert("\n\nPersisted from the live WebKit editor.\n\n")
            await model.flush()
            let saved = try await model.store.readNote(firstID)
            try check(saved.markdown.contains("Persisted from the live WebKit editor."), "Real JS bridge autosaved a complete Markdown note")
            try check(saved.markdown.contains("\\frac{1}{3}") && saved.markdown.contains("[x]") && saved.markdown.contains("| Method"), "Save preserved equations, tasks and table content")
            // Programmatic capture uses the same PDF-space render/persist/insert path as the drag tool.
            await model.capture(page: 1, rect: .init(x: 48, y: 210, width: 516, height: 128))
            let sources = try await model.store.sources(firstID)
            let source = try unwrap(sources.last, "Capture source missing")
            try check(source.page == 1 && source.rect.width == 516, "Capture sidecar stores paper ID, page and PDF rectangle")
            let imagePath = try unwrap(source.asset, "Capture image missing")
            try check(FileManager.default.fileExists(atPath: model.store.directory(firstID).appendingPathComponent(imagePath).path), "High resolution PNG persisted beside Markdown")
            try await eventually {
                (try? await model.editor.webView.evaluateJavaScript("Array.from(document.querySelectorAll('.tiptap img')).every(i => i.complete && i.naturalWidth > 0)")) as? Bool == true
            }
            diagnostics = try await model.editor.call("diagnostics") as? [String: Any] ?? [:]
            try check(diagnostics["imageCount"] as? Int == 1, "WKWebView resolved a relative local screenshot image")
            model.reader.goToPage(0)
            _ = try await model.editor.webView.evaluateJavaScript("document.querySelector('.tiptap img').click(); true")
            try await eventually {
                guard model.reader.sourceOverlay.source?.id == source.id,
                      let page = model.reader.view.document?.page(at: source.page) else { return false }
                let visibleRect = model.reader.view.convert(source.rect.cgRect, from: page)
                return visibleRect.intersects(model.reader.view.bounds)
            }
            checks.append("Clicking a note screenshot reveals its original PDF page and region")
            try check(try Data(contentsOf: model.store.pdfURL(firstID)) == originalPDF, "Capture and navigation did not modify the original PDF")
            // Detect unsupported imports before changing the current note.
            let beforeRejectedImport = try await model.editor.call("getMarkdown") as? String
            do { try await model.editor.validate("---\ntitle: unsupported\n---\n"); throw Failure(message: "Unsafe import accepted") }
            catch is EditorError { checks.append("Unsupported Markdown import is rejected before mutation") }
            try check(try await model.editor.call("getMarkdown") as? String == beforeRejectedImport, "Rejected import left the existing editor content intact")
            // A second real PDF tests note association and undo isolation.
            await model.openDemo()
            let secondID = try unwrap(model.selectedID, "Second import failed")
            try check(secondID != firstID, "Imports use independent stable UUIDs")
            _ = try await model.editor.call("format", "undo")
            current = try await model.editor.call("getMarkdown") as? String ?? ""
            try check(!current.contains("Persisted from the live WebKit editor."), "Undo history does not cross paper boundaries")
            try await model.editor.insert("\n\nSecond paper only.\n\n")
            await model.flush()
            // Import a real .md plus its relative image into the second paper.
            let importFolder = model.store.root.deletingLastPathComponent().appendingPathComponent("MarkdownImport")
            try FileManager.default.createDirectory(at: importFolder.appendingPathComponent("assets"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: model.store.directory(firstID).appendingPathComponent(imagePath), to: importFolder.appendingPathComponent("assets/figure.png"))
            let importedFile = importFolder.appendingPathComponent("imported.md")
            try Data("# Imported note\n\nImported $x^2$ with a relative image.\n\n![Figure](assets/figure.png)\n".utf8).write(to: importedFile)
            try await model.replaceNote(secondID, from: importedFile, confirmReplacement: false)
            let importedNote = try await model.store.readNote(secondID)
            try check(importedNote.markdown.contains("# Imported note") && importedNote.markdown.contains("$x^2$"), "Native Markdown file import preserved editable text and math")
            let importedAnalysis = try await model.editor.call("inspectMarkdown", importedNote.markdown) as? [String: Any]
            let importedImage = try unwrap((importedAnalysis?["images"] as? [String])?.first, "Imported image reference missing")
            try check(importedImage != "assets/figure.png" && FileManager.default.fileExists(atPath: model.store.directory(secondID).appendingPathComponent(importedImage).path), "Markdown import copied relative images with collision-free paths")
            let switched = clock.now
            await model.select(firstID)
            metrics["cachedPaperSwitchMs"] = milliseconds(switched.duration(to: clock.now))
            current = try await model.editor.call("getMarkdown") as? String ?? ""
            try check(current.contains("Persisted from the live WebKit editor.") && !current.contains("Second paper only."), "Switching papers restored the correct independent note")
            // Export package includes ordinary Markdown and relative resources.
            let export = model.store.root.deletingLastPathComponent().appendingPathComponent("Export")
            try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
            try await model.store.exportNote(firstID, to: export)
            try check(FileManager.default.fileExists(atPath: export.appendingPathComponent(firstID.uuidString).appendingPathComponent(imagePath).path), "Markdown package export includes its relative image assets")
            // Real PDFKit extraction and sidecar annotation controller/export paths.
            let originalURL = model.store.pdfURL(firstID)
            let layout = try await Task.detached { try PDFServices.layout(url: originalURL, page: 0) }.value
            try check(layout.columnCount == 2, "Real PDFKit text extraction identified the fixture's two columns")
            let focusLines = layout.focused(at: .init(x: 80, y: 595), above: 1, below: 2)
            try check(!focusLines.isEmpty && focusLines.allSatisfy { $0.rect.cgRect.maxX < 310 }, "Focus window on a real PDF stays in the left column")
            model.reader.goToPage(0); model.reader.focus.enabled = true
            try await eventually { model.reader.focus.detectedColumns == 2 }
            try check(model.reader.focus.overlay.highlights?.1.isEmpty == false, "Native focus overlay uses cached line regions")
            try await eventually { model.reader.focus.screenMask.coversEveryScreen }
            checks.append("Native mouse-transparent focus windows cover every connected display, including menu bar and Dock")
            model.reader.focus.togglePin(at: .init(x: 80, y: 595), page: 0)
            let pinned = model.reader.focus.overlay.highlights?.1
            model.reader.focus.overlay.onMove?(.init(x: 400, y: 595), 0)
            try check(model.reader.focus.keyboard && model.reader.focus.overlay.highlights?.1 == pinned, "Clicking pins the current PDF line against mouse movement")
            model.reader.focus.step(1)
            try check(model.reader.focus.overlay.highlights?.1 != pinned, "Arrow navigation advances a pinned line in reading order")
            model.reader.focus.togglePin(at: .init(x: 400, y: 595), page: 0)
            try check(!model.reader.focus.keyboard && model.reader.focus.overlay.highlights?.1.allSatisfy { $0.minX > 300 } == true, "Clicking again follows the mouse in the right column only")
            model.reader.focus.keyboard = true
            let visibleHoles = model.reader.focus.overlay.highlights
            model.reader.focus.overlay.highlights = nil
            model.reader.focus.overlay.onGeometryChanged?()
            try check(model.reader.focus.screenMask.coversEveryScreen, "Dark field remains active when the pinned line is outside the viewport")
            model.reader.focus.overlay.highlights = visibleHoles
            model.reader.focus.overlay.onGeometryChanged?()
            model.reader.focus.enabled = false
            let record = PaperAnnotation(page: 0, kind: .rectangle, rect: .init(x: 48, y: 210, width: 516, height: 128))
            model.reader.annotations.add([record]); model.reader.annotations.undo()
            try check(model.reader.annotations.records.isEmpty, "Native annotation undo restores the previous sidecar state")
            model.reader.annotations.redo(); await model.reader.annotations.flush()
            let persistedAnnotations = try await model.store.annotations(firstID)
            try check(persistedAnnotations == [record], "Annotation redo persists an independent sidecar")
            let annotatedURL = export.appendingPathComponent("annotated.pdf")
            try await PDFServices.exportAnnotated(original: originalURL, destination: annotatedURL, annotations: [record])
            let annotated = try unwrap(PDFDocument(url: annotatedURL), "Cannot read annotated export")
            try check(annotated.page(at: 0)?.annotations.isEmpty == false, "Annotated PDF export contains actual PDFKit annotations")
            try check(try Data(contentsOf: originalURL) == originalPDF, "Drawing and annotated export preserve the original PDF bytes")
            // A proposal goes through the production diff approval path and remains undoable.
            let beforeAI = try await model.editor.call("getMarkdown") as? String ?? ""
            model.ai.proposal = NoteProposal(paperID: firstID, before: beforeAI, after: beforeAI + "\n\nApproved AI edit.\n", reason: "Integration test")
            try check(try await model.editor.call("getMarkdown") as? String == beforeAI, "Proposing an AI edit leaves the note unchanged")
            await model.ai.applyProposal()
            let applied = try await model.editor.call("getMarkdown") as? String ?? ""
            try check(applied.contains("Approved AI edit."), "Explicit diff approval applies the proposed note change")
            _ = try await model.editor.call("format", "undo")
            let undone = try await model.editor.call("getMarkdown") as? String ?? ""
            try check(!undone.contains("Approved AI edit."), "Approved AI note edits can be undone")
            let stale = try await model.editor.call("replaceMarkdown", ["id": firstID.uuidString, "expected": "stale note", "markdown": "must not overwrite"]) as? [String: Any]
            try check(stale?["ok"] as? Bool == false, "AI edits with a stale note revision are rejected")
            await model.save()
            // Session history is stored as ordinary sidecar JSON and can be restored.
            let history = [AIMessage(role: "user", content: "A persisted research question"), AIMessage(role: "assistant", content: "A persisted answer [p.1](paperreader://page/1)")]
            try await model.store.saveSidecar(firstID, name: "conversation.json", data: JSONEncoder().encode(history))
            await model.ai.load(firstID)
            try check(model.ai.messages == history, "AI conversation history restores for the matching paper")
            if let endpoint = ProcessInfo.processInfo.environment["PAPER_READER_MOCK_API"], let url = URL(string: endpoint) {
                let provider = CloudAIProvider(baseURL: url, model: "test-model", key: "test-key")
                let toolCounter = ToolCounter()
                let request = AIRequest(messages: [AIMessage(role: "user", content: "Read note")], tools: [AITool("readNote", "Read the test note")]) { call in
                    guard call.name == "readNote" else { throw Failure(message: "Unexpected tool") }; await toolCounter.increment(); return .string("A real tool result")
                }
                var response = ""
                for try await event in provider.stream(request) { if case .text(let text) = event { response += text } }
                try check(response.contains("Mock tool flow completed"), "Cloud provider consumes a real HTTP SSE response")
                try check(await toolCounter.count == 1, "Cloud provider routes a streamed function call through the constrained tool handler")
                let image = try Data(contentsOf: model.store.directory(firstID).appendingPathComponent(imagePath))
                let visionRequest = AIRequest(messages: [AIMessage(role: "user", content: "Inspect this test image")], images: [AIImage(data: image)], tools: []) { _ in throw Failure(message: "No tool expected") }
                var vision = ""
                for try await event in provider.stream(visionRequest) { if case .text(let text) = event { vision += text } }
                try check(vision.contains("Mock image context received"), "Cloud provider sends PDF image context using the multimodal API contract")
            }
            if ProcessInfo.processInfo.environment["PAPER_READER_LIVE_TESTS"] == "1" {
                let metadata = try await MetadataService.fetch(doi: "10.1038/nature14539")
                try check(metadata.title.lowercased().contains("deep learning") && !metadata.authors.isEmpty, "Live Crossref lookup returned verified publication metadata")
                let catalogue = AISettings(); catalogue.backend = .codex
                await catalogue.refreshModels()
                try check(!catalogue.models.isEmpty, "Live Codex App Server returned a selectable model catalogue")
                let working = export.appendingPathComponent("CodexTest", isDirectory: true)
                try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
                let provider = CodexAIProvider(executable: model.ai.settings.codexPath, model: "", cwd: working)
                let request = AIRequest(messages: [AIMessage(role: "user", content: "Reply with exactly PAPER_READER_LIVE_OK. Do not use any tools.")], tools: []) { _ in throw Failure(message: "No tools authorized in live smoke test") }
                var response = ""
                for try await event in provider.stream(request) { if case .text(let text) = event { response += text } }
                try check(response.contains("PAPER_READER_LIVE_OK"), "Live Codex App Server generated streamed text with shell disabled")
                let image = try Data(contentsOf: model.store.directory(firstID).appendingPathComponent(imagePath))
                let visionRequest = AIRequest(messages: [AIMessage(role: "user", content: "If the attached figure contains a blue curve, reply exactly PAPER_READER_VISION_OK. Otherwise reply IMAGE_MISSING. Do not use tools.")], images: [AIImage(data: image)], tools: []) { _ in throw Failure(message: "No tools authorized") }
                var vision = ""
                for try await event in provider.stream(visionRequest) { if case .text(let text) = event { vision += text } }
                try check(vision.contains("PAPER_READER_VISION_OK"), "Live Codex App Server inspected a real PDF-rendered figure")
            }
            // Exercise genuine native multipage printing, including math, table, code and image.
            let longNote = current + "\n\n" + (1...70).map { "## Section \($0)\n\nLong paragraph \($0). Evidence remains readable in the exported research notebook. The print engine must paginate and preserve content.\n" }.joined(separator: "\n")
            try await model.editor.setDocument(id: firstID, markdown: longNote)
            try await Task.sleep(for: .milliseconds(600))
            let pdfURL = export.appendingPathComponent("note.pdf")
            try check(try await model.editor.exportPDF(to: pdfURL), "Native WebKit print operation exported a PDF without external software")
            let exportedPDF = try unwrap(PDFDocument(url: pdfURL), "Exported PDF cannot be opened")
            try check(exportedPDF.pageCount > 1, "Native PDF export paginated a long notebook")
            try check(exportedPDF.string?.contains("Long paragraph 70") == true, "PDF export includes the final section without truncation")
            metrics["exportedNotePages"] = Double(exportedPDF.pageCount)
            for index in [0, exportedPDF.pageCount - 1] {
                let bounds = exportedPDF.page(at: index)!.bounds(for: .cropBox)
                let rendered = try await Task.detached {
                    try PDFRegionRenderer.render(url: pdfURL, page: index, rect: PDFRect(bounds), scale: 2)
                }.value
                try rendered.png.write(to: export.appendingPathComponent("note-page-\(index + 1).png"))
            }
            // Restore the persisted note so self-test does not leave unsaved synthetic content.
            try await model.editor.setDocument(id: firstID, markdown: current)
            await model.select(firstID)
            await model.shutdown()
            try writeResult(output, success: true, checks: checks, metrics: metrics, error: nil)
            print("INTEGRATION PASS: \(checks.count) checks. Report: \(output.path)")
            Darwin.exit(0)
        } catch {
            if let details = try? await model.editor.call("diagnostics") { print("Editor diagnostics: \(details)") }
            try? writeResult(output, success: false, checks: checks, metrics: metrics, error: error.localizedDescription)
            print("INTEGRATION FAIL: \(error.localizedDescription). Report: \(output.path)")
            Darwin.exit(1)
        }
    }
    private static func eventually(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure(message: "Timed out waiting for live app state")
    }
    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure(message: message) }; return value
    }
    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
    private static func writeResult(_ url: URL, success: Bool, checks: [String], metrics: [String: Double], error: String?) throws {
        var json: [String: Any] = ["success": success, "checks": checks, "metrics": metrics, "date": ISO8601DateFormatter().string(from: .now), "os": ProcessInfo.processInfo.operatingSystemVersionString]
        if let error { json["error"] = error }
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}

private actor ToolCounter { var count = 0; func increment() { count += 1 } }
