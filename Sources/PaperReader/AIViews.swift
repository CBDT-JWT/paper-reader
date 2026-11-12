import SwiftUI
import AppKit
import PaperCore

struct AIComposer: View {
    @ObservedObject var ai: AIController
    var compact = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                HStack(spacing: 8) {
                    AIConnectionControls(settings: ai.settings, generating: ai.generating)
                    Spacer(minLength: 0)
                    Button { ai.expanded = true } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(WorkspaceIconStyle()).help(L("展开对话")).accessibilityIdentifier("ai.expand")
                    Button { ai.visible = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(WorkspaceIconStyle()).help(L("关闭"))
                }
                if ai.error != nil { AIErrorBanner(ai: ai) }
                else if !ai.generating, let answer = ai.messages.last(where: { $0.role == "assistant" }) {
                    Button { ai.expanded = true } label: {
                        Text((try? AttributedString(markdown: String(answer.content.prefix(600)), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(answer.content))
                            .font(Design.body).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
            if ai.generating || !ai.status.isEmpty {
                HStack(spacing: 8) {
                    if ai.generating { ProgressView().controlSize(.small) }
                    Text(ai.status.isEmpty ? L("正在回答…") : ai.status).font(Design.small).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ChatInput(text: $ai.draft, submit: { ai.send() }, dismiss: { if compact { ai.visible = false } else { ai.expanded = false } })
                    .frame(height: compact ? 52 : 76)
                if ai.generating { Button { ai.cancel() } label: { Image(systemName: "stop.circle.fill") }.buttonStyle(WorkspaceIconStyle()).help(L("停止生成")) }
                else { Button { ai.send() } label: { Image(systemName: "arrow.up.circle.fill").foregroundStyle(WorkspacePalette.accent) }
                    .buttonStyle(WorkspaceIconStyle()).disabled(ai.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(L("发送问题")).accessibilityIdentifier("ai.send") }
            }
            HStack {
                Label(L("论文与笔记"), systemImage: "doc.text").lineLimit(1)
                Spacer()
                Text(L("Enter 发送 · Shift+Enter 换行"))
            }.font(Design.small).foregroundStyle(.tertiary)
        }.padding(14).background(WorkspacePalette.chrome, in: RoundedRectangle(cornerRadius: compact ? 20 : Design.radius))
            .frame(maxWidth: compact ? 600 : .infinity)
    }
}
struct AIConversationView: View {
    @ObservedObject var ai: AIController
    @State private var renderingError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(L("论文对话"), systemImage: "bubble.left.and.text.bubble.right").font(Design.body).fontWeight(.medium)
                Spacer(minLength: 0)
                Button { ai.expanded = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(WorkspaceIconStyle()).help(L("收起对话")).accessibilityIdentifier("ai.close")
            }.padding(.horizontal, 16).frame(height: 50)
            AIConnectionControls(settings: ai.settings, generating: ai.generating).padding(.horizontal, 16).padding(.bottom, 8)
            ZStack {
                AITranscriptView(messages: ai.messages, generating: ai.generating,
                                 onLink: { url in Task { await ai.app?.openLink(url) } }, onError: { renderingError = $0 })
                if ai.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L("从这篇论文开始")).font(Design.title)
                        Text(L("解释选区、梳理方法，或一起整理笔记。")).font(Design.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L("总结论文的方法与结论")) { ai.draft = L("请总结这篇论文的方法、主要结论和局限，并标注原文页码。") }.buttonStyle(.bordered)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 24)
                        .background(WorkspacePalette.paper)
                }
            }
            if let proposal = ai.proposal {
                VStack(alignment: .leading, spacing: 10) {
                    Text(proposal.reason).font(.system(size: 14, weight: .medium))
                    HStack(alignment: .top, spacing: 12) { diffColumn(proposal.before, comparedTo: proposal.after, before: true); diffColumn(proposal.after, comparedTo: proposal.before, before: false) }.frame(height: 170)
                    Text(L("确认后应用，可在笔记中撤销。")).font(Design.small).foregroundStyle(.secondary)
                    HStack { Spacer(); Button(L("拒绝")) { ai.proposal = nil }; Button(L("应用修改")) { Task { await ai.applyProposal() } }.buttonStyle(.borderedProminent) }
                }.padding(14).background(WorkspacePalette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Design.radius)).padding(12)
            }
            if let renderingError { Text(renderingError).font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 14) }
            if ai.error != nil { AIErrorBanner(ai: ai).padding(.horizontal, 12).padding(.top, 8) }
            AIComposer(ai: ai, compact: false).padding(12)
        }.font(Design.body).background(WorkspacePalette.paper).frame(minWidth: 300)
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
            HStack { if settings.refreshing { ProgressView().controlSize(.small) }; Text(settings.status).font(Design.small).foregroundStyle(settings.statusIsError ? Color.red : Color.secondary); Spacer(); Button(L("保存设置")) { settings.save() }.buttonStyle(.borderedProminent) }
        }.textFieldStyle(.roundedBorder).font(.system(size: 14)).padding(24).frame(width: 760, height: 460)
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
        view.setAccessibilityLabel(L("询问论文或当前选区…")); view.setAccessibilityIdentifier("ai.input")
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
        VStack { Spacer(); if ai.visible && !ai.expanded { AIComposer(ai: ai) } }
    }
}
