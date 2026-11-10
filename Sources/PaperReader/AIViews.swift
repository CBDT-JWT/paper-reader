import SwiftUI
import AppKit
import PaperCore

struct AIComposer: View {
    @ObservedObject var ai: AIController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ai.generating || !ai.status.isEmpty {
                HStack { if ai.generating { ProgressView().controlSize(.small) }; Text(L(ai.status.isEmpty ? L("正在回答…") : ai.status)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2); Spacer(); Button(L("展开对话")) { ai.expanded = true }.font(.system(size: 12)) }
            } else if let answer = ai.messages.last(where: { $0.role == "assistant" }) {
                Button { ai.expanded = true } label: { Text(answer.content).font(.system(size: 14)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            }
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(.secondary)
                ChatInput(text: $ai.draft, submit: { ai.send() }, dismiss: { ai.visible = false }).frame(minHeight: 34, maxHeight: 70)
                if ai.generating { Button { ai.cancel() } label: { Image(systemName: "stop.circle.fill") }.buttonStyle(WorkspaceIconStyle()).help(L("停止生成")) }
                else { Button { ai.send() } label: { Image(systemName: "arrow.up.circle.fill") }.buttonStyle(WorkspaceIconStyle()).disabled(ai.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Button { ai.visible = false } label: { Image(systemName: "xmark") }.buttonStyle(WorkspaceIconStyle()).help(L("关闭"))
            }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.07)))
            .frame(maxWidth: 600)
    }
}
struct AIConversationView: View {
    @ObservedObject var ai: AIController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(L("论文对话")).font(.system(size: 20, weight: .semibold)); Spacer(); Button(L("完成")) { dismiss() } }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(ai.messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(message.role == "user" ? L("你") : "AI").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                Text(.init(message.content)).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.id(message.id)
                        }
                    }.padding(.vertical, 12)
                }.onChange(of: ai.messages.last?.content) { _, _ in if let id = ai.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if let proposal = ai.proposal {
                VStack(alignment: .leading, spacing: 10) {
                    Text(proposal.reason).font(.system(size: 14, weight: .medium))
                    HStack(alignment: .top, spacing: 16) { diffColumn(proposal.before, comparedTo: proposal.after, before: true); diffColumn(proposal.after, comparedTo: proposal.before, before: false) }.frame(height: 210)
                    HStack { Text(L("确认后应用，可在笔记中撤销。")).font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Button(L("拒绝")) { ai.proposal = nil }; Button(L("应用修改")) { Task { await ai.applyProposal() } }.buttonStyle(.borderedProminent) }
                }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            AIComposer(ai: ai)
        }.font(.system(size: 14)).padding(24).frame(minWidth: 740, minHeight: 680)
            .environment(\.openURL, OpenURLAction { url in Task { await ai.app?.openLink(url) }; return .handled })
    }
    private func diffColumn(_ text: String, comparedTo other: String, before: Bool) -> some View {
        let lines = text.components(separatedBy: "\n"), otherLines = other.components(separatedBy: "\n")
        let difference = before ? otherLines.difference(from: lines) : lines.difference(from: otherLines)
        let changed: Set<Int> = Set(difference.compactMap { change in switch change { case .remove(let offset, _, _): return before ? offset : nil; case .insert(let offset, _, _): return before ? nil : offset } })
        return VStack(alignment: .leading, spacing: 6) {
            Text(before ? L("修改前") : L("修改后")).font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) { VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in Text(lines[index].isEmpty ? " " : lines[index]).font(.system(size: 12, design: .monospaced)).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading).background(changed.contains(index) ? (before ? Color.red : Color.green).opacity(0.12) : .clear) }
            } }.frame(maxWidth: .infinity)
        }
    }
}
struct AISettingsView: View {
    @ObservedObject var settings: AISettings
    var body: some View {
        Form {
            Picker(L("服务提供方"), selection: $settings.backend) { ForEach(AIBackend.allCases) { Text($0.title).tag($0) } }
            if settings.backend == .codex {
                TextField(L("Codex 路径"), text: $settings.codexPath)
                Text(L("使用本机 Codex 登录；模型推理可能在云端。Shell、文件写入和外部插件不向 AI 开放。")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else { TextField(L("API 基础地址"), text: $settings.endpoint); if settings.backend == .cloud { SecureField(L("API 密钥"), text: $settings.key) } }
            HStack {
                TextField(L("模型（Codex 可留空）"), text: $settings.model)
                Menu(L("选择模型")) {
                    if settings.backend == .codex { Button(L("使用默认模型")) { settings.model = "" } }
                    ForEach(settings.models, id: \.self) { name in Button(name) { settings.model = name } }
                }.disabled(settings.models.isEmpty)
                Button(L("读取模型")) { Task { await settings.refreshModels() } }.disabled(settings.refreshing)
            }
            Text(L("公式与图表识别需要支持视觉的模型。")).font(.system(size: 12)).foregroundStyle(.secondary)
            Toggle(L("允许外部学术检索"), isOn: $settings.allowWeb)
            Text(L("联网检索使用 Crossref 的真实出版物信息。笔记修改始终需要差异确认。API Key 仅保存在 macOS Keychain。")).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack { Text(L(settings.status)).font(.system(size: 12)); Spacer(); Button(L("保存设置")) { settings.save() }.buttonStyle(.borderedProminent) }
        }.textFieldStyle(.roundedBorder).font(.system(size: 14)).padding(24).frame(width: 760, height: 460)
            .onChange(of: settings.backend) { _, backend in
                settings.models = []
                if backend == .localHTTP && settings.endpoint == "https://api.openai.com/v1" { settings.endpoint = "http://127.0.0.1:11434/v1" }
                else if backend == .cloud && settings.endpoint == "http://127.0.0.1:11434/v1" { settings.endpoint = "https://api.openai.com/v1" }
            }
    }
}
private struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var dismiss: () -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.autohidesScrollers = true
        let view = InputView(); view.isRichText = false; view.font = .systemFont(ofSize: 14); view.drawsBackground = false; view.textContainerInset = NSSize(width: 3, height: 7); view.isVerticallyResizable = true; view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.submit = submit; view.dismiss = dismiss; scroll.documentView = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { guard let view = scroll.documentView as? InputView else { return }; if view.string != text { view.string = text }; view.submit = submit; view.dismiss = dismiss; context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput; init(parent: ChatInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
    @MainActor final class InputView: NSTextView {
        var submit: (() -> Void)?; var dismiss: (() -> Void)?
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty { (L("询问论文或当前选区…") as NSString).draw(at: NSPoint(x: 4, y: 7), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor]) }
        }
        override func didChangeText() { super.didChangeText(); needsDisplay = true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, !event.modifierFlags.contains(.shift) { submit?(); return }
            if event.keyCode == 53 { dismiss?(); return }; super.keyDown(with: event)
        }
    }
}

struct AIReaderOverlay: View {
    @ObservedObject var ai: AIController
    var body: some View {
        VStack { Spacer(); if ai.visible { AIComposer(ai: ai) } }
            .sheet(isPresented: $ai.expanded) { AIConversationView(ai: ai) }
    }
}
