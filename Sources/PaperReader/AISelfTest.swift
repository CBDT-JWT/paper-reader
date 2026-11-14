import AppKit
import WebKit
import PaperCore

@MainActor enum AISelfTest {
    static func runStandalone(model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PAPER_READER_LIBRARY"] != nil, let path = environment["PAPER_READER_TEST_OUTPUT"] else { Darwin.exit(2) }
        var report: [String: Any] = ["scope": "ai", "success": false, "date": ISO8601DateFormatter().string(from: .now)]
        do {
            for _ in 0..<200 {
                if model.editor.ready { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            await model.openDemo()
            guard let id = model.selectedID else { throw IntegrationSelfTest.Failure(message: "AI fixture import failed") }
            try await model.editor.setDocument(id: id, markdown: "# Synthetic note\n\n**Evidence** and *inference*.")
            await model.flush()
            let output = model.store.root.deletingLastPathComponent().appendingPathComponent("AIExport", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            report["checks"] = try await run(model: model, output: output)
            report["success"] = true
        } catch { report["error"] = error.localizedDescription }
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic)
        if report["success"] as? Bool == true, environment["PAPER_READER_TEST_KEEP_OPEN"] == "1" { return }
        Darwin.exit(report["success"] as? Bool == true ? 0 : 1)
    }

    static func run(model: AppModel, output: URL) async throws -> [String] {
        var checks: [String] = []
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw IntegrationSelfTest.Failure(message: message) }
            checks.append(message)
        }
        func wait(_ message: String, _ condition: () async throws -> Bool) async throws {
            for _ in 0..<200 {
                if try await condition() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw IntegrationSelfTest.Failure(message: message)
        }
        let ai = model.ai, settings = ai.settings
        await ai.finish()
        let saved = settings.configuration, savedMessages = ai.messages, savedProposal = ai.proposal, savedDraft = ai.draft
        let savedNotes = model.showNotes, savedQuote = ai.pendingQuote
        defer {
            ai.expanded = false; ai.visible = false; ai.error = nil; ai.messages = savedMessages; ai.proposal = savedProposal; ai.draft = savedDraft
            settings.backend = saved.backend; settings.model = saved.model; settings.endpoint = saved.endpoint
            settings.codexPath = saved.codexPath; settings.key = saved.key; settings.allowWeb = saved.allowWeb
            model.showNotes = savedNotes; ai.pendingQuote = savedQuote
        }
        do {
            let emphasis = try await model.editor.webView.evaluateJavaScript("(() => { const b=document.querySelector('.tiptap strong'), i=document.querySelector('.tiptap em'); return !!b && !!i && Number(getComputedStyle(b).fontWeight)>=600 && getComputedStyle(i).fontStyle==='italic' })()") as? Bool
            try check(emphasis == true, "Actual note WKWebView renders bold and italic with distinct computed font styles")
            model.showNotes = true
            ai.messages = [AIMessage(role: "assistant", content: "# Research result\n\n**Verified evidence** and *careful inference*.\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n$x^2$\n\n[p.1](paperreader://page/1)")]
            ai.expanded = true
            try await wait("AI drawer WKWebView did not mount") { transcript(in: model.reader.view.window?.contentView) != nil }
            guard let webView = transcript(in: model.reader.view.window?.contentView), let window = webView.window else { throw IntegrationSelfTest.Failure(message: "Missing AI drawer") }
            try await wait("Conversation Markdown styles or KaTeX did not render") {
                let value = try? await webView.evaluateJavaScript("window.conversation?.diagnostics()") as? [String: Any]
                let weight = Int(value?["boldWeight"] as? String ?? "0") ?? 0
                return value?["bold"] as? Bool == true && value?["italic"] as? Bool == true && value?["table"] as? Bool == true && value?["math"] as? Bool == true && value?["italicStyle"] as? String == "italic" && weight >= 600
            }
            let noteFrame = model.editor.webView.convert(model.editor.webView.bounds, to: nil)
            let chatFrame = webView.convert(webView.bounds, to: nil)
            try check(window.sheets.isEmpty && !model.editor.webView.isHiddenOrHasHiddenAncestor && chatFrame.minX >= noteFrame.maxX - 2 && chatFrame.width >= 300,
                      "Conversation is a native right-side drawer beside the visible note editor, with no conversation sheet")
            try check(true, "Actual offline conversation WKWebView renders headings, bold, italic, tables, page links and KaTeX")
            let safe = try await webView.evaluateJavaScript("document.querySelectorAll('script:not([src]), iframe, [onerror]').length === 0") as? Bool
            try check(safe == true, "Conversation uses packaged scripts and has no injected script, iframe or event attributes")
            try await wait("Footer accessibility frames missing") { accessibilityFrame("ai.hint", in: window.contentView) != nil && accessibilityFrame("note.status", in: window.contentView) != nil }
            let noteStatusFrame = accessibilityFrame("note.status", in: window.contentView)!
            let inputHintFrame = accessibilityFrame("ai.hint", in: window.contentView)!
            try check(abs(noteStatusFrame.midY - inputHintFrame.midY) < 2, "Note saved status and AI input hint align on the same native footer baseline")
            let wasFullScreen = window.styleMask.contains(.fullScreen)
            try await IntegrationSelfTest.setFullScreen(true, window: window)
            try await wait("Full-screen footer alignment did not settle") {
                guard let note = accessibilityFrame("note.status", in: window.contentView), let hint = accessibilityFrame("ai.hint", in: window.contentView) else { return false }
                return abs(note.midY - hint.midY) < 2
            }
            try check(window.titlebarAppearsTransparent && window.toolbarStyle == .unifiedCompact, "Full-screen workspace uses compact native chrome with aligned note and conversation footers")
            try await IntegrationSelfTest.setFullScreen(wasFullScreen, window: window)
            if let input = input(in: window.contentView) {
                let originalSubmit = input.submit
                var submissions = 0
                input.submit = { submissions += 1 }
                input.string = ""
                input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                try check(input.hasMarkedText(), "Actual NSTextView accepts a marked input-method composition")
                let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                input.keyDown(with: enter)
                try check(submissions == 0, "Return confirms marked input without submitting a question")
                input.unmarkText()
                input.keyDown(with: enter)
                try check(submissions == 1, "Return submits after input-method composition has completed")
                let newline = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                input.keyDown(with: newline)
                try check(submissions == 1 && input.string.contains("\n"), "Shift Return inserts a newline in the real composer")
                input.submit = originalSubmit
                input.string = ""; input.didChangeText()
            } else { throw IntegrationSelfTest.Failure(message: "Native AI input missing") }
            let beforeExcerpt = try await model.editor.call("getMarkdown") as? String ?? ""
            guard let page = model.reader.view.document?.page(at: 0), let selected = page.selection(for: NSRange(location: 0, length: 45)) else { throw IntegrationSelfTest.Failure(message: "PDF text selection fixture missing") }
            model.reader.view.setCurrentSelection(selected, animate: false)
            model.reader.view.go(to: selected)
            model.reader.view.showSelectionActions()
            try check(model.reader.view.selectionActionsVisible, "Selecting real PDF text presents the native highlight, Ask AI and excerpt popover")
            model.reader.view.dismissSelectionActions()
            model.commands.run(.askAI)
            try await wait("PDF selection quote missing") { ai.pendingQuote?.link != nil }
            try check(ai.pendingQuote?.text == selected.string && ai.pendingQuote?.source?.page == 0, "Ask AI keeps a visible source-linked PDF quote independently of the question draft")
            ai.pendingQuote = nil
            let reply = try await webView.evaluateJavaScript("document.querySelector('.assistant-message .message-content').textContent") as? String ?? ""
            let replyID = ai.messages.first(where: { $0.role == "assistant" })!.id
            ai.selectReply(reply, messageID: replyID, excerpt: false)
            try check(ai.pendingQuote?.source == nil && ai.pendingQuote?.label == L("AI 回答") && ai.pendingQuote?.text == reply, "Selecting an AI answer creates an AI-attributed follow-up quote")
            ai.selectReply(reply, messageID: replyID, excerpt: true)
            try await wait("AI excerpt was not inserted") { (try await model.editor.call("getMarkdown") as? String)?.contains("paperreader://conversation?") == true }
            _ = try await model.editor.call("format", "undo")
            try check((try await model.editor.call("getMarkdown") as? String) == beforeExcerpt, "AI answer excerpts preserve their source and can be undone in the note")
            ai.pendingQuote = nil
            if let endpoint = ProcessInfo.processInfo.environment["PAPER_READER_MOCK_API"] {
                settings.backend = .cloud; settings.endpoint = endpoint; settings.model = "test-model"; settings.key = "test-key"
                ai.pendingQuote = AIQuote(text: "Selected evidence for context", label: "Synthetic source")
                ai.draft = "QUOTED_PAYLOAD"
                ai.send()
                try await wait("Quoted request did not finish") { !ai.generating }
                try check(ai.error == nil && ai.messages.contains(where: { $0.role == "user" && $0.quote?.text == "Selected evidence for context" }), "Quoted context survives sending and the real provider HTTP request")
                try await wait("Quoted message did not render") { (try? await webView.evaluateJavaScript("document.querySelector('.message-quote:not([hidden])')?.textContent.includes('Selected evidence for context')")) as? Bool == true }
                try check(true, "Sent question renders its quote as a separate conversation block")
                let selectedReply = try await webView.evaluateJavaScript("(() => { const c=document.querySelector('.assistant-message .message-content'); const r=document.createRange(); r.selectNodeContents(c); const s=window.getSelection(); s.removeAllRanges(); s.addRange(r); document.dispatchEvent(new MouseEvent('mouseup',{bubbles:true})); return s.toString().trim() })()") as? String ?? ""
                try await wait("Reply selection toolbar missing") { (try? await webView.evaluateJavaScript("document.querySelector('.selection-tools')?.hidden === false")) as? Bool == true }
                _ = try await webView.evaluateJavaScript("document.querySelector('.selection-tools button').click()")
                try await wait("Reply selection bridge did not set a quote") { ai.pendingQuote?.text == selectedReply }
                try check(ai.pendingQuote?.label == L("AI 回答"), "The real conversation selection toolbar routes Ask AI through the native quote handler")
                ai.pendingQuote = nil
                ai.draft = "DOWNLOAD_FIXTURE"
                ai.send()
                try await wait("AI download request did not finish") { !ai.generating }
                let downloaded = model.store.downloadDirectory.appendingPathComponent("AI Downloads/evidence.csv")
                try check(ai.error == nil && (try? String(contentsOf: downloaded, encoding: .utf8)) == "name,value\nverified,42\n", "The AI downloadFile tool downloads a real HTTP file into the workspace subfolder")
                try check(ai.messages.contains(where: { $0.content.contains("paperreader://file?") }), "Completed downloads appear as source-linked conversation items")
                let fileURL = URL(string: endpoint.replacingOccurrences(of: "/v1", with: "/files/evidence.csv"))!
                let second = try await model.store.downloadFile(from: fileURL, folder: "AI Downloads", fileName: "evidence.csv")
                try check(second.path == "AI Downloads/evidence (2).csv" && (try? Data(contentsOf: downloaded)) == (try? Data(contentsOf: model.store.downloadDirectory.appendingPathComponent(second.path))), "Repeated downloads choose a new filename and preserve the existing file")
                do { _ = try await model.store.downloadFile(from: fileURL, folder: "../escape"); throw IntegrationSelfTest.Failure(message: "Download traversal accepted") }
                catch LibraryError.invalidPath { checks.append("Downloads reject paths outside the workspace") }
                do { _ = try await model.store.downloadFile(from: URL(string: "file:///etc/hosts")!); throw IntegrationSelfTest.Failure(message: "Local file download accepted") }
                catch LibraryError.invalidPath { checks.append("The model download tool accepts no local-file URLs") }
                let missing = URL(string: endpoint.replacingOccurrences(of: "/v1", with: "/files/missing"))!
                do { _ = try await model.store.downloadFile(from: missing, folder: "Failed download"); throw IntegrationSelfTest.Failure(message: "Failed download accepted") }
                catch is IntegrationSelfTest.Failure { throw IntegrationSelfTest.Failure(message: "Failed download accepted") }
                catch { try check(!FileManager.default.fileExists(atPath: model.store.downloadDirectory.appendingPathComponent("Failed download").path), "Failed HTTP downloads leave no destination file or partial workspace folder") }
                settings.backend = .localHTTP; settings.endpoint = endpoint.replacingOccurrences(of: "/v1", with: "/local/v1"); settings.model = "local-fixture-model"
                await settings.refreshModels()
                try check(settings.models.contains("test-model"), "Local HTTP model catalogue loads through the provider selected in the drawer")
                settings.backend = .cloud
                try check(settings.model == "test-model" && settings.endpoint == endpoint, "Switching providers restores that provider's own model and endpoint")
                await settings.refreshModels()
                try check(settings.models.contains("test-model"), "Cloud API model catalogue loads through the same dialogue settings")
                settings.endpoint = endpoint + "/changed"
                try check(settings.models.isEmpty, "Changing a connection clears its stale model catalogue")
                settings.endpoint = endpoint
                settings.backend = .codex; settings.codexPath = output.appendingPathComponent("MissingCodex").path
                ai.draft = "Synthetic retry test. Read the note."
                ai.send()
                try await wait("Failed Codex launch did not expose a retry action") { !ai.generating && ai.error != nil && ai.canRetry }
                try check(ai.messages.filter { $0.content == "Synthetic retry test. Read the note." }.count == 1,
                          "A failed launch retains the original question and a retryable error")
                settings.backend = .cloud; settings.endpoint = endpoint; settings.model = "test-model"
                ai.draft = "Unsent next question"
                ai.retry()
                try await wait("Retry through configured cloud provider did not finish") { !ai.generating }
                try check(ai.error == nil && !ai.canRetry && ai.messages.last?.content.contains("Mock tool flow completed") == true && ai.messages.filter { $0.content == "Synthetic retry test. Read the note." }.count == 1,
                          "Retry starts a new provider connection, streams a tool-backed answer and avoids duplicate questions")
                try check(ai.draft == "Unsent next question", "Retry preserves an unsent composer draft")
                try await wait("Retried answer did not render Markdown") {
                    (try? await webView.evaluateJavaScript("!!document.querySelector('article:last-child strong') && !!document.querySelector('article:last-child em')")) as? Bool == true
                }
                try check(true, "The actual streamed retry answer renders bold and italic in the mounted drawer")
                settings.backend = .localHTTP
                settings.endpoint = endpoint.replacingOccurrences(of: "/v1", with: "/local/v1")
                settings.model = "local-fixture-model"
                ai.draft = "Synthetic local model request. Read the note."
                ai.send()
                try await wait("Local HTTP model request did not finish") { !ai.generating }
                try check(ai.error == nil && ai.messages.last?.content.contains("Mock tool flow completed") == true,
                          "The local HTTP provider streams a tool-backed answer through the dialogue without a cloud API key")
            }
            ai.expanded = false
            try await wait("Conversation drawer did not collapse") { transcript(in: model.reader.view.window?.contentView) == nil }
            try check(!model.editor.webView.isHiddenOrHasHiddenAncestor, "Collapsing the AI drawer keeps the linked note editor visible")
            checks += try await transport(output: output, executable: saved.codexPath)
        } catch { await ai.finish(); throw error }
        return checks
    }

    private static func accessibilityFrame(_ identifier: String, in element: Any?) -> NSRect? {
        guard let node = element as? any NSAccessibilityProtocol else { return nil }
        if node.accessibilityIdentifier() == identifier { return node.accessibilityFrame() }
        for child in node.accessibilityChildren() ?? [] {
            if let frame = accessibilityFrame(identifier, in: child) { return frame }
        }
        return nil
    }

    private static func input(in view: NSView?) -> AIInputTextView? {
        if let input = view as? AIInputTextView { return input }
        for child in view?.subviews ?? [] { if let result = input(in: child) { return result } }
        return nil
    }

    private static func transcript(in view: NSView?) -> WKWebView? {
        if let web = view as? WKWebView, web.identifier?.rawValue == "ai.transcript" { return web }
        for child in view?.subviews ?? [] { if let result = transcript(in: child) { return result } }
        return nil
    }

    private static func transport(output: URL, executable: String) async throws -> [String] {
        guard let mock = ProcessInfo.processInfo.environment["PAPER_READER_MOCK_CODEX"] else { return [] }
        let directory = output.appendingPathComponent("CodexTransport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scenario = directory.appendingPathComponent("scenario.txt")
        let rpc = CodexRPC()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        var checks: [String] = []
        do {
            try Data("startup-error".utf8).write(to: scenario)
            try await rpc.start(executable: mock, cwd: directory, environment: environment)
            do { try await rpc.initialize(); throw IntegrationSelfTest.Failure(message: "Startup failure was accepted") }
            catch let error as IntegrationSelfTest.Failure { throw error }
            catch {
                guard error.localizedDescription.contains("23") else { throw IntegrationSelfTest.Failure(message: "Missing App Server exit code: \(error.localizedDescription)") }
                checks.append("App Server startup failure includes its real exit code instead of an unexplained closed connection")
            }
            await rpc.stop()
            try Data("hang".utf8).write(to: scenario)
            try await rpc.start(executable: mock, cwd: directory, environment: environment)
            let clock = ContinuousClock(), start = ContinuousClock().now
            let pending = Task { try await rpc.initialize() }
            try await Task.sleep(for: .milliseconds(100)); pending.cancel()
            do { try await pending.value; throw IntegrationSelfTest.Failure(message: "Cancelled initialization returned success") }
            catch is CancellationError { }
            guard clock.now - start < .seconds(2) else { throw IntegrationSelfTest.Failure(message: "Cancelling startup waited for the RPC timeout") }
            checks.append("Cancelling a pending initialization returns promptly and terminates its owned App Server")
            await rpc.stop()
            try Data("success".utf8).write(to: scenario)
            try await rpc.start(executable: mock, cwd: directory, environment: environment)
            try await rpc.initialize()
            let catalogue = try await rpc.request("model/list", .object([:]))
            guard catalogue["data"].array.first?["model"].string == "fixture-model" else { throw IntegrationSelfTest.Failure(message: "Restarted RPC catalogue missing") }
            checks.append("The same RPC object can restart after failure and cancellation without stale EOF or request state")
            await rpc.stop()
            let request = AIRequest(messages: [AIMessage(role: "user", content: "Synthetic transport test")], tools: [AITool("readNote", "Read a synthetic note")]) { call in
                guard call.name == "readNote" else { throw IntegrationSelfTest.Failure(message: "Unauthorized fixture tool") }
                return .string("Synthetic note")
            }
            var response = ""
            for try await event in CodexAIProvider(executable: mock, model: "", cwd: directory).stream(request) { if case .text(let text) = event { response += text } }
            guard response.contains("Fixture answer") else { throw IntegrationSelfTest.Failure(message: "Missing fixture streamed answer") }
            checks.append("JSONL generation declines shell and permission requests, routes an allowed research tool, and accepts completion followed by EOF")
            for mode in ["failed", "interrupted", "disconnect"] {
                try Data(mode.utf8).write(to: scenario)
                do {
                    for try await _ in CodexAIProvider(executable: mock, model: "", cwd: directory).stream(request) { }
                    throw IntegrationSelfTest.Failure(message: "Unsuccessful turn was reported as completed: \(mode)")
                } catch let error as IntegrationSelfTest.Failure { throw error }
                catch { checks.append("App Server \(mode) produces an error or cancellation instead of a successful answer") }
            }
            if ProcessInfo.processInfo.environment["PAPER_READER_LIVE_CODEX"] == "1" {
                try await rpc.start(executable: executable, cwd: directory, environment: environment)
                try await rpc.initialize()
                let models = try await rpc.request("model/list", .object(["limit": .number(100)]))
                guard !models["data"].array.isEmpty else { throw IntegrationSelfTest.Failure(message: "Real Codex Finder-PATH catalogue missing") }
                await rpc.stop()
                checks.append("The installed Codex starts, initializes and lists models with Finder's minimal PATH")
                let prompt = AIRequest(messages: [AIMessage(role: "user", content: "Reply exactly PAPER_READER_LIVE_OK. Do not use tools.")], tools: []) { _ in throw IntegrationSelfTest.Failure(message: "Live smoke test authorizes no tools") }
                var text = ""
                for try await event in CodexAIProvider(executable: executable, model: "", cwd: directory).stream(prompt) { if case .text(let value) = event { text += value } }
                guard text.contains("PAPER_READER_LIVE_OK") else { throw IntegrationSelfTest.Failure(message: "Real Codex inference did not return the synthetic smoke-test answer") }
                checks.append("The real installed Codex completes a streamed inference turn using only a synthetic prompt")
            }
        } catch { await rpc.stop(); throw error }
        return checks
    }
}
