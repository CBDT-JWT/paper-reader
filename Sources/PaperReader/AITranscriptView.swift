import AppKit
import SwiftUI
import WebKit
import PaperCore

struct AITranscriptView: NSViewRepresentable {
    let messages: [AIMessage]
    let generating: Bool
    let onLink: (URL) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(EditorResourceHandler(library: FileManager.default.temporaryDirectory), forURLScheme: "paperreader-resource")
        configuration.userContentController.add(context.coordinator, name: "conversation")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.identifier = NSUserInterfaceItemIdentifier("ai.transcript")
        view.setAccessibilityIdentifier("ai.transcript")
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        view.load(URLRequest(url: URL(string: "paperreader-resource://editor/conversation.html?lang=\(AppLanguage.code)")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render()
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "conversation")
        view.stopLoading()
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var parent: AITranscriptView?
        var ready = false
        var task: Task<Void, Never>?
        var revision = 0
        func render() {
            revision += 1
            guard ready, task == nil else { return }
            task = Task {
                defer { task = nil }
                do {
                    while true {
                        try await Task.sleep(for: .milliseconds(45))
                        guard let parent, let webView else { return }
                        let rendered = revision
                        let messages = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parent.messages))
                        _ = try await webView.callAsyncJavaScript("return window.conversation.render(payload)", arguments: ["payload": ["messages": messages, "generating": parent.generating]], in: nil, contentWorld: .page)
                        if rendered == revision { return }
                    }
                } catch is CancellationError { }
                catch { if !Task.isCancelled { parent?.onError(error.localizedDescription) } }
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready": ready = true; render()
            case "link":
                if let raw = body["url"] as? String, let url = URL(string: raw), ["https", "http", "paperreader"].contains(url.scheme ?? "") { parent?.onLink(url) }
            case "copy":
                guard let raw = body["id"] as? String, let id = UUID(uuidString: raw), let text = parent?.messages.first(where: { $0.id == id })?.content else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            default: break
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.request.url?.scheme == "paperreader-resource", action.request.url?.host == "editor" { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; webView.reload() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent?.onError(error.localizedDescription) }
    }
}
