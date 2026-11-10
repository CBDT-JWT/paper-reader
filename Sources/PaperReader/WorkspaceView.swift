import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum Design {
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
                    Button { model.commands.run(.sidebar) } label: { Image(systemName: "sidebar.left") }.help("文献库")
                    Button { model.commands.run(.open) } label: { Image(systemName: "plus") }.help("导入 PDF")
                }
                ToolbarItem(placement: .principal) {
                    Text(model.currentPaper?.title ?? "Paper Reader").font(Design.body).lineLimit(1)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu { ForEach([CommandID.save, .importMarkdown, .exportMarkdown, .exportPDF, .revealFiles]) { RegisteredCommandButton(registry: model.commands, id: $0) } }
                    label: { Image(systemName: "square.and.arrow.up") }.help("笔记与文件")
                    Button { model.commands.run(.notes) } label: { Image(systemName: "sidebar.right") }.help("笔记")
                }
            }
            .alert("Paper Reader", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}

struct WorkspaceSplit: NSViewControllerRepresentable {
    @ObservedObject var model: AppModel
    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.splitView.autosaveName = "PaperReader.Workspace.v1"
        let library = NSSplitViewItem(viewController: NSHostingController(rootView: LibraryView(model: model)))
        library.minimumThickness = 190; library.maximumThickness = 340; library.canCollapse = true
        library.holdingPriority = .init(260)
        let reader = NSSplitViewItem(viewController: NSHostingController(rootView: ReaderPane(model: model, reader: model.reader)))
        reader.minimumThickness = 360; reader.holdingPriority = .init(200)
        let note = NSSplitViewItem(viewController: NSHostingController(rootView: NotePane(model: model, editor: model.editor)))
        note.minimumThickness = 300; note.maximumThickness = 900; note.canCollapse = true
        note.holdingPriority = .init(250)
        controller.addSplitViewItem(library); controller.addSplitViewItem(reader); controller.addSplitViewItem(note)
        return controller
    }
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        controller.splitViewItems[0].isCollapsed = !model.showSidebar
        controller.splitViewItems[2].isCollapsed = !model.showNotes
    }
}

private struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var sortByTitle = false
    @State private var dropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("文献库").font(Design.title)
                Spacer()
                Menu { Toggle("按标题排序", isOn: $sortByTitle) } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .menuStyle(.borderlessButton).frame(width: 22)
            }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索论文", text: $model.query).textFieldStyle(.plain).font(Design.body)
            }.padding(9).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Design.radius)).padding(.horizontal, 14)
            HStack { Text("所有论文"); Spacer(); Text("\(model.papers.count)").monospacedDigit() }
                .font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(sortByTitle ? model.filteredPapers.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : model.filteredPapers) { paper in
                        Button { Task { await model.select(paper.id) } } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "doc.richtext").font(Design.body).foregroundStyle(model.selectedID == paper.id ? Color.accentColor : .secondary).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(paper.title).font(Design.body).lineLimit(3).multilineTextAlignment(.leading)
                                    Text("PDF · 本地文献").font(Design.small).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.selectedID == paper.id ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: Design.radius))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("打开论文", systemImage: "doc.richtext") { Task { await model.select(paper.id) } }
                            Button("在 Finder 中显示文件", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.pdfURL(paper.id), model.store.noteURL(paper.id)]) }
                        }
                    }
                }.padding(.horizontal, 10)
            }.padding(.top, 3)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Label("拖入 PDF 开始阅读", systemImage: "arrow.down.doc").font(Design.small)
                Text("PDF 与 Markdown，始终在本机。").font(Design.small)
            }.foregroundStyle(.secondary).padding(18)
        }
        .background(dropTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in await model.importPDFs([url]) }
                }
            }
            return true
        }
    }
}

private struct ReaderPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var reader: PDFReaderController
    @State private var pageInput = "1"
    @State private var showSearch = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    tool(.previousPage); Text("\(reader.page + 1) / \(reader.pageCount)").font(Design.small).monospacedDigit().foregroundStyle(.secondary)
                    tool(.nextPage)
                }
                Spacer(minLength: 4)
                tool(.zoomOut)
                Text("\(Int(reader.scale * 100))%").font(Design.small).monospacedDigit().foregroundStyle(.secondary).frame(width: 42)
                tool(.zoomIn); tool(.fit)
                Spacer(minLength: 4)
                tool(.quote); tool(.capture)
                Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).help("搜索原文")
            }.font(Design.body).padding(.horizontal, 20).frame(height: 50).disabled(model.selectedID == nil)
            if showSearch {
                HStack {
                    TextField("搜索论文原文", text: $reader.search).textFieldStyle(.roundedBorder).onSubmit { reader.findNext() }
                    Button("查找下一个") { reader.findNext() }
                    Button { showSearch = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(Design.body).padding(.horizontal, 20).padding(.bottom, 10)
            }
            ZStack {
                NativePDFView(reader: reader)
                if model.selectedID == nil && !model.isOpening {
                    VStack(spacing: 18) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                        Text("给下一篇论文，留一处思考的空间。").font(Design.title)
                        Text("阅读、摘录与笔记，在同一个原生工作台。").font(Design.body).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("导入 PDF…") { model.commands.run(.open) }.buttonStyle(.borderedProminent)
                            Button("打开示例论文") { model.commands.run(.demo) }.buttonStyle(.bordered)
                        }.font(Design.body).padding(.top, 4)
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .underPageBackgroundColor))
                }
                if model.isOpening { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.radius)) }
                if reader.captureMode {
                    VStack { Label("拖动框选 PDF 区域 · Esc 取消", systemImage: "viewfinder").font(Design.small).padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Design.radius)); Spacer() }.padding(.top, 16).allowsHitTesting(false)
                }
            }
            HStack {
                Image(systemName: "doc.richtext"); Text("PDF 原件保持完整")
                Spacer()
                if reader.pageCount > 0 {
                    TextField("页码", text: $pageInput).frame(width: 32).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .onSubmit { if let number = Int(pageInput) { reader.goToPage(number - 1) } }
                    Text("页").foregroundStyle(.secondary)
                }
            }.font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 34)
                .onChange(of: reader.page) { _, value in pageInput = String(value + 1) }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func tool(_ id: CommandID) -> some View {
        Button { model.commands.run(id) } label: { Image(systemName: id.symbol).foregroundStyle(id == .capture && reader.captureMode ? Color.accentColor : .primary) }
            .buttonStyle(.plain).help(id.title + (model.commands.shortcuts[id].map { " (\($0.display))" } ?? ""))
    }
}

private struct NativePDFView: NSViewRepresentable {
    let reader: PDFReaderController
    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        for view in [reader.view, reader.sourceOverlay, reader.capture] {
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
                Label("阅读笔记", systemImage: "square.and.pencil").font(Design.body).fontWeight(.medium)
                Spacer()
                Menu { ForEach([CommandID.save, .importMarkdown, .exportMarkdown, .exportPDF, .insertImage, .revealFiles]) { RegisteredCommandButton(registry: model.commands, id: $0) } }
                label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
            }.padding(.horizontal, 20).frame(height: 50)
            HStack(spacing: 17) {
                Menu {
                    Button("一级标题") { editor.format("h1") }; Button("二级标题") { editor.format("h2") }; Button("三级标题") { editor.format("h3") }
                } label: { Text("H").font(Design.body).fontWeight(.semibold) }.menuStyle(.borderlessButton).frame(width: 27)
                formatButton("bold", "bold", "粗体"); formatButton("italic", "italic", "斜体"); formatButton("highlight", "highlighter", "高亮")
                Menu {
                    Button("无序列表") { editor.format("bullet") }; Button("有序列表") { editor.format("ordered") }; Button("任务列表") { editor.format("task") }
                    Button("引用") { editor.format("quote") }; Button("代码块") { editor.format("code") }; Button("行内代码") { editor.format("inlineCode") }; Button("删除线") { editor.format("strike") }
                } label: { Image(systemName: "list.bullet") }.menuStyle(.borderlessButton).frame(width: 25)
                Menu {
                    Button("行内公式") { editor.format("math") }; Button("块级公式") { editor.format("blockMath") }
                } label: { Image(systemName: "function") }.menuStyle(.borderlessButton).frame(width: 25)
                formatButton("table", "tablecells", "插入表格")
                Button { model.commands.run(.insertImage) } label: { Image(systemName: "photo") }.buttonStyle(.plain).help("插入图片")
                Spacer(minLength: 0)
            }.font(Design.body).foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 38).disabled(model.selectedID == nil)
            ZStack {
                NativeEditorView(editor: editor)
                if model.selectedID == nil {
                    VStack(spacing: 12) {
                        Text("让理解沉淀下来").font(Design.title)
                        Text("每篇论文都有一份独立的 Markdown 笔记。\n摘录和截图可以一键回到原文。").font(Design.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text(model.status).lineLimit(1)
                Spacer(minLength: 0)
                Text("Markdown").foregroundStyle(.tertiary)
            }.font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 34)
        }.background(Color(nsColor: .textBackgroundColor))
        .contextMenu { ForEach([CommandID.capture, .quote, .save, .exportMarkdown, .exportPDF, .insertImage]) { RegisteredCommandButton(registry: model.commands, id: $0) } }
    }
    private func formatButton(_ action: String, _ symbol: String, _ label: String) -> some View {
        Button { editor.format(action) } label: { Image(systemName: symbol) }.buttonStyle(.plain).help(label)
    }
}

private struct NativeEditorView: NSViewRepresentable {
    let editor: EditorController
    func makeNSView(context: Context) -> WKWebView { editor.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

import WebKit
