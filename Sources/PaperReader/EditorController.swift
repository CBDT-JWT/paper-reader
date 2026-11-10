import AppKit
import WebKit
import Combine
import PaperCore

@MainActor
final class EditorController: NSObject, ObservableObject {
    let webView: WKWebView
    private let resources: EditorResourceHandler
    private let bridge = EditorMessageBridge()
    private var printJob: PrintCompletion?
    @Published private(set) var ready = false
    private var document: (id: UUID, markdown: String)?
    var onChange: ((UUID, String) -> Void)?
    var onLink: ((URL) -> Void)?
    var onError: ((String) -> Void)?

    init(library: URL) {
        resources = EditorResourceHandler(library: library)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(resources, forURLScheme: "paperreader-resource")
        configuration.userContentController.add(bridge, name: "editor")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        bridge.owner = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: URL(string: "paperreader-resource://editor/index.html")!))
    }
    func setDocument(id: UUID, markdown: String) async throws {
        document = (id, markdown)
        resources.activePaperID = id
        if ready { try await loadDocument() }
    }
    private func loadDocument() async throws {
        guard let document else { return }
        let result = try await call("setDocument", ["id": document.id.uuidString, "markdown": document.markdown]) as? [String: Any]
        if result?["ok"] as? Bool == false {
            throw EditorError.message(result?["error"] as? String ?? "编辑器无法读取这份笔记。")
        }
    }
    func receive(_ message: Any) {
        guard let body = message as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            Task { do { try await loadDocument() } catch { onError?(error.localizedDescription) } }
        case "change":
            guard let rawID = body["paperID"] as? String, let id = UUID(uuidString: rawID),
                  id == document?.id, let markdown = body["markdown"] as? String else { return }
            document = (id, markdown); onChange?(id, markdown)
        case "link":
            if let string = body["url"] as? String, let url = URL(string: string) { onLink?(url) }
        case "error": onError?(body["message"] as? String ?? "编辑器错误")
        default: break
        }
    }
    func call(_ method: String, _ argument: Any? = nil) async throws -> Any? {
        let allowed = ["setDocument", "validate", "insertMarkdown", "format", "getMarkdown", "diagnostics", "snapshot", "inspectMarkdown", "rewriteImages"]
        guard allowed.contains(method) else { throw EditorError.message("不支持的编辑器操作") }
        let argumentJSON: String
        if let argument {
            argumentJSON = String(data: try JSONSerialization.data(withJSONObject: argument, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)!
        } else { argumentJSON = "" }
        return try await webView.evaluateJavaScript("window.paperEditor.\(method)(\(argumentJSON))")
    }
    func insert(_ markdown: String) async throws {
        guard ready else { throw EditorError.message("编辑器尚未就绪") }
        guard try await call("insertMarkdown", markdown) as? Bool == true else { throw EditorError.message("无法插入笔记，请先打开可编辑的论文笔记。") }
    }
    func format(_ action: String) {
        Task { do { _ = try await call("format", action) } catch { onError?(error.localizedDescription) } }
    }
    func validate(_ markdown: String) async throws {
        let result = try await call("validate", markdown) as? [String: Any]
        guard result?["ok"] as? Bool == true else { throw EditorError.message(result?["error"] as? String ?? "Markdown 验证失败") }
    }
    /// Native WebKit pagination, asynchronous printing, and atomic destination replacement.
    func exportPDF(to url: URL) async throws -> Bool {
        guard let window = webView.window, printJob == nil, ready else { throw EditorError.message("笔记窗口尚未准备好，或另一个导出仍在进行。") }
        var assetsReady = false
        for _ in 0..<50 {
            let loaded = try await webView.evaluateJavaScript("document.fonts.status === 'loaded' && Array.from(document.querySelectorAll('.tiptap img')).every(i => i.complete && i.naturalWidth > 0)") as? Bool
            if loaded == true { assetsReady = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard assetsReady else { throw EditorError.message("图片或字体尚未加载完成，请检查笔记资源后重试。") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-export-\(UUID()).pdf")
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.topMargin = 48; info.bottomMargin = 48; info.leftMargin = 48; info.rightMargin = 48
        info.horizontalPagination = .fit
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        let operation = webView.printOperation(with: info)
        operation.canSpawnSeparateThread = true
        operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        let completion = PrintCompletion()
        printJob = completion
        let success = await withCheckedContinuation { continuation in
            completion.continuation = continuation
            operation.runModal(for: window, delegate: completion,
                               didRun: #selector(PrintCompletion.didRun(_:success:contextInfo:)), contextInfo: nil)
        }
        printJob = nil
        guard success else { try? FileManager.default.removeItem(at: temporary); return false }
        try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: temporary) }
            let data = try Data(contentsOf: temporary)
            try data.write(to: url, options: .atomic)
        }.value
        return true
    }
}

@MainActor private final class PrintCompletion: NSObject {
    var continuation: CheckedContinuation<Bool, Never>?
    @objc nonisolated func didRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor [weak self] in
            self?.continuation?.resume(returning: success); self?.continuation = nil
        }
    }
}

extension EditorController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.request.url?.scheme == "paperreader-resource" { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        onError?("编辑器进程已重新启动，正在从最近的编辑内容恢复。")
        webView.reload()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }
}

@MainActor private final class EditorMessageBridge: NSObject, WKScriptMessageHandler {
    weak var owner: EditorController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message.body)
    }
}

enum EditorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let string) = self { return string }; return nil }
}

@MainActor final class EditorResourceHandler: NSObject, WKURLSchemeHandler {
    let library: URL
    var activePaperID: UUID?
    private var jobs: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(library: URL) { self.library = library }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url else { return }
        do {
            let file: URL
            if url.host == "editor" {
                let root = Bundle.module.url(forResource: "Editor", withExtension: nil)!
                file = try LibraryStore.containedURL(String(url.path.dropFirst()), in: root)
            } else if url.host == "paper" {
                let parts = url.pathComponents.filter { $0 != "/" }
                guard parts.count >= 2, let id = UUID(uuidString: parts[0]), id == activePaperID,
                      parts[1] == "assets" else { throw LibraryError.invalidPath }
                file = try LibraryStore.containedURL(parts.dropFirst().joined(separator: "/"), in: library.appendingPathComponent(id.uuidString))
            } else { throw LibraryError.invalidPath }
            let mime = ["html": "text/html", "js": "application/javascript", "css": "text/css", "png": "image/png",
                        "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
                        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf"][file.pathExtension] ?? "application/octet-stream"
            jobs[key] = Task {
                do {
                    let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: file) }.value
                    guard !Task.isCancelled else { return }
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
                    urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
                } catch { if !Task.isCancelled { urlSchemeTask.didFailWithError(error) } }
                jobs.removeValue(forKey: key)
            }
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        jobs.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
