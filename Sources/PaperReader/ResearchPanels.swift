import SwiftUI
import AppKit
import PDFKit
import PaperCore

struct MetadataPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = Bibliography()
    @State private var authors = ""
    @State private var year = ""
    @State private var loading = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(L("文献信息")).font(.system(size: 20, weight: .semibold)); Spacer(); Text(value.origin == "manual" ? L("手动录入") : value.origin).font(.system(size: 12)).foregroundStyle(.secondary) }
            Form {
                TextField(L("标题"), text: $value.title)
                TextField(L("作者（分号分隔）"), text: $authors)
                TextField(L("年份"), text: $year)
                TextField(L("期刊 / 会议"), text: $value.venue)
                HStack { TextField("DOI", text: $value.doi); Button(L("查询 Crossref")) { Task { await lookup() } }.disabled(loading || value.doi.isEmpty && (value.arxivID ?? "").isEmpty) }
                TextField("arXiv ID", text: Binding(get: { value.arxivID ?? "" }, set: { value.arxivID = $0.isEmpty ? nil : $0 }))
                HStack { TextField(L("卷"), text: $value.volume); TextField(L("期"), text: $value.issue); TextField(L("页码"), text: $value.pages) }
                TextField(L("类型"), text: $value.kind)
            }.textFieldStyle(.roundedBorder)
            Text(L("摘要")).font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $value.abstract).frame(height: 100).padding(6).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            if !error.isEmpty { Text(L(error)).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Menu(L("复制引用")) { ForEach(Bibliography.Style.allCases, id: \.self) { style in Button(style.rawValue) { updateFields(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value.citation(style), forType: .string) } } }
                Spacer(); Button(L("取消")) { dismiss() }; Button(L("保存")) { updateFields(); Task { await model.updateMetadata(value); dismiss() } }.buttonStyle(.borderedProminent)
            }
        }.font(.system(size: 14)).padding(24).frame(width: 660)
        .onAppear { value = model.currentPaper?.metadata ?? model.selectedID.flatMap { model.metadataCandidates[$0] } ?? Bibliography(title: model.currentPaper?.title ?? ""); authors = value.authors.joined(separator: "; "); year = value.year.map(String.init) ?? "" }
    }
    private func updateFields() { value.authors = authors.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }; value.year = Int(year) }
    private func lookup() async {
        loading = true; defer { loading = false }
        do { value = value.doi.isEmpty ? try await MetadataService.fetchArxiv(id: value.arxivID ?? "") : try await MetadataService.fetch(doi: value.doi); authors = value.authors.joined(separator: "; "); year = value.year.map(String.init) ?? ""; error = "" }
        catch { self.error = error.localizedDescription }
    }
}
struct ReadingToolsPanel: View {
    @ObservedObject var annotations: AnnotationController
    @ObservedObject var focus: FocusController
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("阅读工具")).font(.system(size: 20, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(ReaderTool.allCases) { tool in Button { model.commands.run(tool.command) } label: { Image(systemName: tool.symbol) }.buttonStyle(WorkspaceIconStyle(selected: annotations.tool == tool)).help(tool.title) }
                Button { model.commands.run(.highlight) } label: { Image(systemName: "highlighter") }.buttonStyle(WorkspaceIconStyle()).help(L("高亮选中文字"))
            }
            HStack { Button(L("撤销批注")) { model.commands.run(.undoAnnotation) }; Button(L("重做批注")) { model.commands.run(.redoAnnotation) } }
            Divider()
            Text(L("聚焦设置")).font(Design.body).fontWeight(.medium)
            Text(L("整屏变暗。单击锁定阅读行，↑/↓移动；再次单击跟随鼠标。Esc 退出。")).font(.system(size: 12)).foregroundStyle(.secondary)
            Stepper(L("上方行数：\(focus.above)"), value: $focus.above, in: 0...10)
            Stepper(L("下方行数：\(focus.below)"), value: $focus.below, in: 0...10)
            HStack { Text(L("遮罩强度")); Slider(value: $focus.opacity, in: 0.1...0.8) }
            Toggle(L("锁定阅读行（↑ / ↓移动）"), isOn: $focus.keyboard)
            Picker(L("阅读栏"), selection: $focus.manualColumn) {
                Text(L("自动识别")).tag(-1)
                ForEach(0..<focus.manualCount, id: \.self) { Text(L("第 \($0 + 1) 栏")).tag($0) }
            }
            Stepper(L("手动分栏数：\(focus.manualCount)"), value: $focus.manualCount, in: 1...4)
            if focus.detectedColumns > 0 { Text(L("检测到 \(focus.detectedColumns) 栏")).font(.system(size: 12)).foregroundStyle(.secondary) }
            if !focus.status.isEmpty { Text(L(focus.status)).font(.system(size: 12)).foregroundStyle(.secondary) }
            Text(L("自动识别不准时可手动指定栏。扫描 PDF 暂无 OCR。")).font(.system(size: 12)).foregroundStyle(.secondary)
        }.font(.system(size: 14)).padding(22).frame(width: 340)
    }
}
@MainActor enum OutlineWindow {
    private static var controller: NSWindowController?
    static func show(model: AppModel) {
        let root = model.reader.view.document?.outlineRoot
        var items: [(String, PDFDestination?, Int)] = []
        func append(_ outline: PDFOutline, depth: Int) { for i in 0..<outline.numberOfChildren { if let child = outline.child(at: i) { items.append((child.label ?? "", child.destination, depth)); append(child, depth: depth + 1) } } }
        if let root { append(root, depth: 0) }
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(L("论文目录")).font(.system(size: 20, weight: .semibold))
            if items.isEmpty { Text(L("这份 PDF 没有内嵌目录。")).font(.system(size: 14)).foregroundStyle(.secondary) }
            ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(items.indices, id: \.self) { index in Button(items[index].0) { if let destination = items[index].1 { model.reader.view.go(to: destination) } }.buttonStyle(.plain).font(.system(size: 14)).padding(.leading, CGFloat(items[index].2) * 14) } } }
        }.padding(24).frame(minWidth: 360, minHeight: 440)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content)); window.title = L("论文目录"); window.styleMask = [.titled, .closable, .resizable]
        controller = NSWindowController(window: window); controller?.showWindow(nil)
    }
}
@MainActor enum NoteWindow {
    private static var sessions: [UUID: NoteReaderSession] = [:]
    static func show(model: AppModel) {
        guard let paper = model.currentPaper else { return }
        if let session = sessions[paper.id] { session.window?.makeKeyAndOrderFront(nil); return }
        let session = NoteReaderSession(model: model, paper: paper); sessions[paper.id] = session
        session.onClose = { sessions.removeValue(forKey: paper.id) }; session.showWindow(nil)
    }
}
@MainActor private final class NoteReaderSession: NSWindowController, NSWindowDelegate {
    let editor: EditorController
    var onClose: (() -> Void)?
    private var poll: Task<Void, Never>?
    init(model: AppModel, paper: Paper) {
        editor = EditorController(library: model.store.root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 800), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window); window.title = paper.title + L(" — 笔记"); window.center(); window.delegate = self; window.contentView = editor.webView
        editor.onLink = { url in Task { await model.select(paper.id); await model.openLink(url) } }
        poll = Task { [weak self] in
            var revision = ""
            while !Task.isCancelled {
                do {
                    guard let self else { return }
                    if editor.ready {
                        let note = try await model.store.readNote(paper.id)
                        if note.revision != revision { try await editor.setDocument(id: paper.id, markdown: note.markdown); _ = try await editor.call("setReadOnly", true); revision = note.revision }
                    }
                    try await Task.sleep(for: .milliseconds(700))
                } catch is CancellationError { return } catch { return }
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { poll?.cancel(); onClose?() }
}
