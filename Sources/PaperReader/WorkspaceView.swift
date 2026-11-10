import PaperCore
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Design {
    static let radius: CGFloat = 8
    static let small = Font.system(size: 12)
    static let body = Font.system(size: 14)
    static let title = Font.system(size: 20, weight: .semibold)
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        WorkspaceSplit(model: model)
            .frame(minWidth: 1060, minHeight: 650)
            .font(Design.body)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { model.commands.run(.sidebar) } label: { Image(systemName: "sidebar.left") }.help(L("文献库"))
                    Button { model.commands.run(.open) } label: { Image(systemName: "plus") }.help(L("导入 PDF"))
                }
                ToolbarItem(placement: .principal) {
                    Text(model.currentPaper?.title ?? "Paper Reader").font(Design.body).lineLimit(1)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu { ForEach([CommandID.save, .importMarkdown, .exportMarkdown, .exportPDF, .exportAnnotated, .metadata, .outline, .noteWindow, .revealFiles]) { RegisteredCommandButton(registry: model.commands, id: $0) } }
                    label: { Image(systemName: "square.and.arrow.up") }.menuIndicator(.hidden).help(L("笔记与文件"))
                    Button { model.commands.run(.notes) } label: { Image(systemName: "sidebar.right") }.help(L("笔记"))
                }
            }
            .alert("Paper Reader", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(L("好"), role: .cancel) { model.error = nil }
            } message: { Text(L(model.error ?? "")) }
            .sheet(item: $model.libraryNameRequest) { request in LibraryNameSheet(model: model, request: request) }
            .sheet(isPresented: $model.metadataPresented) { MetadataPanel(model: model) }
    }
}

struct WorkspaceSplit: NSViewControllerRepresentable {
    @ObservedObject var model: AppModel
    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.splitView.autosaveName = "PaperReader.Workspace.v1"
        let library = NSSplitViewItem(viewController: NSHostingController(rootView: LibraryTreeView(model: model)))
        library.minimumThickness = 190; library.maximumThickness = 340; library.canCollapse = true
        library.holdingPriority = .init(260)
        let reader = NSSplitViewItem(viewController: NSHostingController(rootView: ReaderPane(model: model, reader: model.reader)))
        reader.minimumThickness = 360; reader.holdingPriority = .init(200)
        let note = NSSplitViewItem(viewController: NSHostingController(rootView: NotePane(model: model, editor: model.editor)))
        note.minimumThickness = 300; note.maximumThickness = 760; note.canCollapse = true
        note.holdingPriority = .init(250)
        controller.addSplitViewItem(library); controller.addSplitViewItem(reader); controller.addSplitViewItem(note)
        return controller
    }
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        controller.splitViewItems[0].isCollapsed = !model.showSidebar
        controller.splitViewItems[2].isCollapsed = !model.showNotes
    }
}

private struct ReaderPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var reader: PDFReaderController
    @State private var pageInput = "1"
    @State private var showSearch = false
    @State private var showTools = false
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                readerToolbar(compact: false)
                readerToolbar(compact: true)
            }.font(Design.body).padding(.horizontal, 12).frame(height: 48).disabled(model.selectedID == nil)
            if showSearch {
                HStack {
                    TextField(L("搜索论文原文"), text: $reader.search).textFieldStyle(.roundedBorder).onSubmit { reader.findNext() }
                    Button(L("查找下一个")) { reader.findNext() }
                    Button { showSearch = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(Design.body).padding(.horizontal, 20).padding(.bottom, 10)
            }
            ZStack {
                NativePDFView(reader: reader)
                if model.selectedID == nil && !model.isOpening {
                    VStack(spacing: 18) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                        Text(L("给下一篇论文，留一处思考的空间。")).font(Design.title)
                        Text(L("阅读、摘录与笔记，在同一个原生工作台。")).font(Design.body).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button(L("导入 PDF…")) { model.commands.run(.open) }.buttonStyle(.borderedProminent)
                            Button(L("打开示例论文")) { model.commands.run(.demo) }.buttonStyle(.bordered)
                        }.font(Design.body).padding(.top, 4)
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .underPageBackgroundColor))
                }
                if model.isOpening { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.radius)) }
                AIReaderOverlay(ai: model.ai).padding(.horizontal, 18).padding(.bottom, 18)
                if reader.captureMode {
                    VStack { Label(L("拖动框选 PDF 区域 · Esc 取消"), systemImage: "viewfinder").font(Design.small).padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Design.radius)); Spacer() }.padding(.top, 16).allowsHitTesting(false)
                }
            }
            HStack {
                Button { model.commands.run(.askAI) } label: { Label(L("询问 AI"), systemImage: "sparkle") }.buttonStyle(.plain)
                Text("·").foregroundStyle(.tertiary)
                Text("PDF")
                Spacer()
                if reader.pageCount > 0 {
                    TextField(L("页码"), text: $pageInput).frame(width: 32).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .onSubmit { if let number = Int(pageInput) { reader.goToPage(number - 1) } }
                    Text(L("页")).foregroundStyle(.secondary)
                }
            }.font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 34)
                .onChange(of: reader.page) { _, value in pageInput = String(value + 1) }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func readerToolbar(compact: Bool) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                tool(.previousPage)
                Text("\(reader.page + 1) / \(reader.pageCount)").font(Design.small).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 46)
                tool(.nextPage)
            }.fixedSize()
            Spacer(minLength: 8)
            if !compact {
                HStack(spacing: 2) { tool(.zoomOut); Text("\(Int(reader.scale * 100))%").font(Design.small).monospacedDigit().foregroundStyle(.secondary).frame(width: 44); tool(.zoomIn); tool(.fit) }.fixedSize()
                Spacer(minLength: 8)
            }
            if !compact { tool(.quote) }; tool(.capture)
            FocusToggleButton(focus: reader.focus, registry: model.commands)
            Button { showTools.toggle() } label: { Image(systemName: "pencil.and.outline") }.buttonStyle(WorkspaceIconStyle()).help(L("阅读工具"))
                .popover(isPresented: $showTools) { ReadingToolsPanel(annotations: reader.annotations, focus: reader.focus, model: model) }
            if compact {
                Menu {
                    Button(L("搜索原文")) { showSearch.toggle() }
                    ForEach([CommandID.quote, .zoomIn, .zoomOut, .fit, .outline, .metadata, .askAI]) { RegisteredCommandButton(registry: model.commands, id: $0) }
                }
                label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if !compact { Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(WorkspaceIconStyle()).help(L("搜索原文")) }
        }
    }
    private func tool(_ id: CommandID) -> some View {
        Button { model.commands.run(id) } label: { Image(systemName: id.symbol).foregroundStyle(id == .capture && reader.captureMode ? Color.accentColor : .primary) }
            .buttonStyle(WorkspaceIconStyle()).help(id.title + (model.commands.shortcuts[id].map { " (\($0.display))" } ?? ""))
    }
}

private struct FocusToggleButton: View {
    @ObservedObject var focus: FocusController
    @ObservedObject var registry: CommandRegistry
    var body: some View {
        Button { registry.run(.focus) } label: {
            Label(L("聚焦"), systemImage: CommandID.focus.symbol).font(Design.body).padding(.horizontal, 9).frame(height: 30)
                .foregroundStyle(focus.enabled ? Color.accentColor : .primary)
                .background(focus.enabled ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: Design.radius))
        }.buttonStyle(.plain).fixedSize().accessibilityIdentifier("reader.focus")
            .help(L("全屏暗场聚焦") + (registry.shortcuts[.focus].map { " (\($0.display))" } ?? ""))
            .accessibilityLabel(L("全屏暗场聚焦"))
            .accessibilityAddTraits(focus.enabled ? [.isSelected] : [])
    }
}

private struct NativePDFView: NSViewRepresentable {
    let reader: PDFReaderController
    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        for view in [reader.view, reader.annotations.overlay, reader.focus.overlay, reader.sourceOverlay, reader.capture] {
            view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor), view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        }
        return host
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct NotePane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: EditorController
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L("阅读笔记"), systemImage: "square.and.pencil").font(Design.body).fontWeight(.medium)
                Spacer()
                Menu { ForEach([CommandID.save, .importMarkdown, .exportMarkdown, .exportPDF, .insertImage, .noteWindow, .revealFiles]) { RegisteredCommandButton(registry: model.commands, id: $0) } }
                label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30, height: 30)
            }.padding(.horizontal, 20).frame(height: 50)
            HStack(spacing: 4) {
                Menu {
                    Button(L("一级标题")) { editor.format("h1") }; Button(L("二级标题")) { editor.format("h2") }; Button(L("三级标题")) { editor.format("h3") }
                } label: { Text("H").font(Design.body).fontWeight(.semibold) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30, height: 30)
                formatButton("bold", "bold", L("粗体")); formatButton("italic", "italic", L("斜体")); formatButton("highlight", "highlighter", L("高亮"))
                Menu {
                    Button(L("无序列表")) { editor.format("bullet") }; Button(L("有序列表")) { editor.format("ordered") }; Button(L("任务列表")) { editor.format("task") }
                    Button(L("引用")) { editor.format("quote") }; Button(L("代码块")) { editor.format("code") }; Button(L("行内代码")) { editor.format("inlineCode") }; Button(L("删除线")) { editor.format("strike") }
                } label: { Image(systemName: "list.bullet") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30, height: 30)
                Menu {
                    Button(L("行内公式")) { editor.format("math") }; Button(L("块级公式")) { editor.format("blockMath") }
                } label: { Image(systemName: "function") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30, height: 30)
                formatButton("table", "tablecells", L("插入表格"))
                Button { model.commands.run(.insertImage) } label: { Image(systemName: "photo") }.buttonStyle(.plain).help(L("插入图片"))
                Spacer(minLength: 0)
            }.font(Design.body).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 40).disabled(model.selectedID == nil)
            ZStack {
                NativeEditorView(editor: editor)
                if model.selectedID == nil {
                    VStack(spacing: 12) {
                        Text(L("让理解沉淀下来")).font(Design.title)
                        Text(L("每篇论文都有一份独立的 Markdown 笔记。\n摘录和截图可以一键回到原文。")).font(Design.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text(L(model.status)).lineLimit(1)
                Spacer(minLength: 0)
                Text("Markdown").foregroundStyle(.tertiary)
            }.font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 34)
        }.background(Color(nsColor: .textBackgroundColor))
        .contextMenu { ForEach([CommandID.capture, .quote, .save, .exportMarkdown, .exportPDF, .insertImage]) { RegisteredCommandButton(registry: model.commands, id: $0) } }
    }
    private func formatButton(_ action: String, _ symbol: String, _ label: String) -> some View {
        Button { editor.format(action) } label: { Image(systemName: symbol) }.buttonStyle(WorkspaceIconStyle()).help(label)
    }
}

private struct NativeEditorView: NSViewRepresentable {
    let editor: EditorController
    func makeNSView(context: Context) -> WKWebView { editor.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

import WebKit
