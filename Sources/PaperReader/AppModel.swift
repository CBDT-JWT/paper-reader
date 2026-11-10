import AppKit
import Combine
import UniformTypeIdentifiers
import PaperCore

@MainActor final class AppModel: ObservableObject {
    var openWorkspaceURLAction: ((URL) -> Void)?
    var openWorkspaceAction: (() -> Void)?
    var workspaceIsCloud = false
    @Published var cloudStatus = L("等待 iCloud Drive")
    private var activeDocumentJobs = 0
    private var waitingForPaper: UUID?
    private var workspacePresenter: WorkspacePresenter?
    private var isRefreshingWorkspace = false
    var isChangingWorkspace = false
    var canLeaveWorkspace: Bool { pending.isEmpty && blocked.isEmpty }
    let drafts: NoteDraftJournal
    private var draftSequence: UInt64 = 0
    private var draftTasks: [UUID: Task<Void, Error>] = [:]
    let store: LibraryStore
    let reader = PDFReaderController()
    let editor: EditorController
    let commands: CommandRegistry
    let ai: AIController
    @Published var libraryNameRequest: LibraryNameRequest?
    @Published var activeFolderID: UUID?
    @Published var librarySort = LibrarySort(rawValue: UserDefaults.standard.string(forKey: "library.sort") ?? "filename") ?? .filename {
        didSet { UserDefaults.standard.set(librarySort.rawValue, forKey: "library.sort") }
    }
    @Published var librarySortAscending = UserDefaults.standard.object(forKey: "library.sortAscending") as? Bool ?? true {
        didSet { UserDefaults.standard.set(librarySortAscending, forKey: "library.sortAscending") }
    }
    @Published var folders: [LibraryFolder] = []
    @Published var metadataPresented = false
    @Published var metadataCandidates: [UUID: Bibliography] = [:]
    private var externalWatcher: Task<Void, Never>?
    @Published var papers: [Paper] = []
    @Published var selectedID: UUID?
    @Published var isOpening = false
    @Published var status = L("本地保存 · 无需账户")
    @Published var error: String?
    @Published var query = ""
    @Published var showSidebar = UserDefaults.standard.object(forKey: "showSidebar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSidebar, forKey: "showSidebar") }
    }
    @Published var showNotes = UserDefaults.standard.object(forKey: "showNotes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showNotes, forKey: "showNotes") }
    }
    private var revisions: [UUID: String] = [:]
    private var pending: [UUID: String] = [:]
    private var blocked: Set<UUID> = []
    private var debounce: Task<Void, Never>?
    private var saveWorker: (id: UUID, task: Task<Void, Never>)?
    private var stateDebounce: Task<Void, Never>?
    private var selectionToken = UUID()
    var currentPaper: Paper? { papers.first { $0.id == selectedID } }
    var filteredPapers: [Paper] { query.isEmpty ? papers : papers.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.displayFileName.localizedCaseInsensitiveContains(query) } }
    static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["PAPER_READER_LIBRARY"] { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PaperReader/Library", isDirectory: true)
    }
    init(store: LibraryStore, commands: CommandRegistry) {
        self.store = store; self.commands = commands
        drafts = NoteDraftJournal(deviceDirectory: store.deviceDirectory)
        ai = AIController(store: store)
        editor = EditorController(library: store.root)
        commands.handler = { [weak self] in self?.run($0) }
        reader.runCommand = { [weak self] in self?.commands.run($0) }
        reader.view.commandMenu = { [weak commands] in commands?.menuItems([.askAI, .quote, .capture, .highlight, .selectText, .drawLine, .drawRectangle, .drawing, .laser, .focus, .undoAnnotation, .redoAnnotation, .fit, .exportAnnotated]) ?? [] }
        reader.onCapture = { [weak self] page, rect in
            Task { await self?.capture(page: page, rect: rect) }
        }
        reader.onStateChange = { [weak self] page, scale in self?.remember(page: page, scale: scale) }
        editor.onChange = { [weak self] id, markdown in self?.noteChanged(id, markdown: markdown) }
        editor.onLink = { [weak self] url in Task { await self?.openLink(url) } }
        editor.onError = { [weak self] in self?.error = $0 }
        ai.app = self; reader.annotations.store = store
        reader.annotations.onError = { [weak self] in self?.error = $0 }
    }
    func start() async {
        workspacePresenter = WorkspacePresenter(url: store.documentsRoot ?? store.root) { [weak self] in
            Task { @MainActor in await self?.refreshWorkspace() }
        }
        externalWatcher = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await self?.refreshWorkspace()
            }
        }
        do {
            papers = try await store.scanWorkspace()
            folders = try await store.folders()
            let previous = UserDefaults.standard.string(forKey: "lastPaper").flatMap(UUID.init(uuidString:))
            if let id = papers.first(where: { $0.id == previous })?.id ?? papers.first?.id { await select(id) }
        } catch { self.error = error.localizedDescription }
    }
    func select(_ id: UUID) async {
        guard !isChangingWorkspace else { return }
        let token = UUID(); selectionToken = token; isOpening = true
        await synchronizeEditor()
        await flush()
        guard token == selectionToken else { return }
        do {
            guard let paper = papers.first(where: { $0.id == id }) else { throw LibraryError.missingPaper }
            let recovered = try await store.recoverCloudNoteVersions(id)
            if !recovered.isEmpty { error = L("iCloud 冲突版本已保留为独立副本，可在笔记所在文件夹查看。") }
            let snapshot = try await store.readNote(id)
            var markdown = snapshot.markdown
            try await draftTasks[id]?.value
            if let draft = try await drafts.read(id) {
                if draft.markdown == snapshot.markdown { try await drafts.clear(id, matching: draft.markdown) }
                else if draft.baseRevision == snapshot.revision { markdown = draft.markdown }
                else {
                    let recovery = try await drafts.archive(id, draft: draft, current: snapshot.markdown)
                    let alert = NSAlert(); alert.messageText = L("发现未保存的本机草稿")
                    alert.informativeText = L("文件版本与本机草稿不同。两份内容已分别备份，可选择要继续编辑的版本。")
                    alert.addButton(withTitle: L("恢复本机草稿")); alert.addButton(withTitle: L("使用文件版本"))
                    alert.addButton(withTitle: L("查看备份"))
                    let result = alert.runModal()
                    if result == .alertFirstButtonReturn { markdown = draft.markdown }
                    else if result == .alertThirdButtonReturn { NSWorkspace.shared.open(recovery) }
                    try await drafts.clear(id, matching: draft.markdown)
                }
            }
            guard token == selectionToken else { return }
            // State callbacks from the old document must not overwrite the new paper's reading position.
            reader.onStateChange = nil
            let pdf = store.pdfURL(id)
            if workspaceIsCloud && !FileManager.default.fileExists(atPath: pdf.path) { _ = try? await Task.detached { try CoordinatedFiles.requestDownload(pdf) }.value; throw LibraryError.workspaceDownloading }
            if await Task.detached(operation: { CoordinatedFiles.needsDownload(pdf) }).value { throw LibraryError.workspaceDownloading }
            try await reader.load(url: store.pdfURL(id), page: paper.page, scale: paper.scale, readingPoint: paper.readingPoint)
            guard token == selectionToken else { return }
            selectedID = id; activeFolderID = paper.folderID; revisions[id] = snapshot.revision; blocked.remove(id)
            try await editor.setDocument(id: id, markdown: markdown)
            if markdown != snapshot.markdown { noteChanged(id, markdown: markdown); await flush() }
            try await reader.annotations.load(id)
            await ai.load(id)
            commands.hasPaper = true
            if !ProcessInfo.processInfo.arguments.contains("--self-test") { UserDefaults.standard.set(id.uuidString, forKey: "lastPaper") }
            status = L("已保存到本机")
            waitingForPaper = nil
        } catch LibraryError.workspaceDownloading {
            waitingForPaper = id; status = L("iCloud 文件正在下载或暂不可用，请联网后稍候重试。")
        } catch {
            if workspaceIsCloud && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains((error as NSError).code) {
                waitingForPaper = id; status = L("iCloud 文件正在下载或暂不可用，请联网后稍候重试。")
            } else { waitingForPaper = nil; self.error = error.localizedDescription }
        }
        guard token == selectionToken else { return }
        reader.onStateChange = { [weak self] page, scale in self?.remember(page: page, scale: scale) }
        isOpening = false
    }
    @discardableResult
    func importPDFs(_ urls: [URL], into folderID: UUID? = nil) async -> [Paper] {
        guard !isChangingWorkspace else { return [] }
        activeDocumentJobs += 1; defer { activeDocumentJobs -= 1 }
        var imported: [Paper] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let valid = await Task.detached { PDFValidation.isValid(url) }.value
                guard valid else { throw LibraryError.invalidPDF }
                let paper = try await store.importPDF(from: url, folderID: folderID)
                papers.insert(paper, at: 0); imported.append(paper); await select(paper.id)
                Task { await self.lookupMetadata(paperID: paper.id) }
            } catch { self.error = error.localizedDescription }
        }
        return imported
    }
    func openPanel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = true
        let folder = activeFolderID
        panel.begin { [weak self] response in
            if response == .OK { Task { await self?.importPDFs(panel.urls, into: folder) } }
        }
    }
    func openDemo() async {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Paper Reader — Demo.pdf")
            try await Task.detached { try DemoPaper.create(at: url) }.value
            let imported = await importPDFs([url])
            if let paper = imported.first, selectedID == paper.id {
                let id = paper.id
                let sample = AppLanguage.code == "en" ? #"""
                # Reading notes

                > Start with evidence. Keep your understanding in your own notes.

                ## About this example

                This three-page document is generated locally. Select PDF text to quote it, or capture a graph and click the image to return to its source.

                ## Equations and ideas

                Click an equation to edit its LaTeX source: $E = mc^2$.

                $$
                \int_0^1 x^2 \, dx = \frac{1}{3}
                $$

                ## Next steps

                - [x] Open a paper and its linked note
                - [ ] Quote a passage
                - [ ] Capture a figure and return to its source

                """# : #"""
                # 阅读笔记

                > 从证据出发，把理解留在自己的笔记里。

                ## 关于这个示例

                这篇本地生成的三页文档，用来体验阅读与记录。可以选择 PDF 原文摘录，也可以框选下方曲线，插入带有来源的截图。

                ## 公式与想法

                公式可以直接点击，重新编辑 LaTeX：$E = mc^2$。

                $$
                \int_0^1 x^2 \, dx = \frac{1}{3}
                $$

                ## 下一步

                - [x] 打开论文与关联笔记
                - [ ] 摘录一段原文
                - [ ] 截取图表并回到来源

                """#
                try await editor.setDocument(id: id, markdown: sample)
                noteChanged(id, markdown: sample); await flush()
            }
        } catch { self.error = error.localizedDescription }
    }
    private func noteChanged(_ id: UUID, markdown: String) {
        guard let revision = revisions[id] else { return }
        draftSequence += 1
        let sequence = draftSequence
        draftTasks[id] = Task { [weak self, drafts] in
            do { try await drafts.stage(id, markdown: markdown, baseRevision: revision, sequence: sequence) }
            catch { self?.error = error.localizedDescription; throw error }
        }
        guard !blocked.contains(id) else { return }
        pending[id] = markdown; status = L("正在保存…")
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await self?.flush()
        }
    }
    /// One worker owns revision transitions, even across awaited saves and document switches.
    func flush() async {
        debounce?.cancel(); debounce = nil
        if let saveWorker {
            await saveWorker.task.value
            if self.saveWorker?.id == saveWorker.id { self.saveWorker = nil }
            if !pending.isEmpty { await flush() }
            return
        }
        let workerID = UUID()
        let worker = Task { [weak self] in
            guard let self else { return }
            while let (id, markdown) = pending.first {
                pending.removeValue(forKey: id)
                guard let revision = revisions[id], !blocked.contains(id) else { continue }
                do {
                    try await draftTasks[id]?.value
                    revisions[id] = try await store.saveNote(id, markdown: markdown, expectedRevision: revision)
                    try await drafts.clear(id, matching: markdown)
                    status = L("已保存到本机")
                } catch {
                    blocked.insert(id); pending.removeValue(forKey: id)
                    let retained = (try? await drafts.read(id)) != nil
                    status = retained ? L("文件保存失败 · 本机草稿已保留") : L("保存失败 · 请保留窗口并检查磁盘")
                    self.error = error.localizedDescription
                }
            }
        }
        saveWorker = (workerID, worker); await worker.value
        if saveWorker?.id == workerID { saveWorker = nil }
        if !pending.isEmpty { await flush() }
    }
    private func remember(page: Int, scale: Double) {
        guard let id = selectedID, let index = papers.firstIndex(where: { $0.id == id }), !isOpening else { return }
        papers[index].page = page; papers[index].scale = scale; papers[index].readingPoint = reader.readingPosition
        let paper = papers[index]
        stateDebounce?.cancel()
        stateDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)); try await self?.store.persistReading(paper.id, page: paper.page, scale: paper.scale, point: paper.readingPoint) }
            catch is CancellationError {} catch { self?.error = error.localizedDescription }
        }
    }
    private func synchronizeEditor() async {
        guard editor.ready else { return }
        do {
            if let snapshot = try await editor.call("snapshot") as? [String: String],
               let rawID = snapshot["id"], let id = UUID(uuidString: rawID), let markdown = snapshot["markdown"],
               let revision = revisions[id], LibraryStore.revision(markdown) != revision {
                noteChanged(id, markdown: markdown)
            }
        } catch { self.error = error.localizedDescription }
    }
    func save() async {
        await synchronizeEditor(); await flush()
        for task in draftTasks.values {
            do { try await task.value } catch { self.error = error.localizedDescription }
        }
    }
    func waitForDocumentJobs() async {
        while activeDocumentJobs > 0 { try? await Task.sleep(for: .milliseconds(50)) }
    }
    func shutdown() async {
        isChangingWorkspace = true; reader.focus.enabled = false; externalWatcher?.cancel(); workspacePresenter = nil; await ai.finish(); await save(); await reader.annotations.flush(); stateDebounce?.cancel()
        if let paper = currentPaper { do { try await store.persistReading(paper.id, page: paper.page, scale: paper.scale, point: paper.readingPoint) } catch { self.error = error.localizedDescription } }
    }
    func capture(page: Int, rect: PDFRect) async {
        guard !isChangingWorkspace else { return }
        activeDocumentJobs += 1; defer { activeDocumentJobs -= 1 }
        guard let id = selectedID, !isOpening else { return }
        let url = store.pdfURL(id)
        status = L("正在渲染 PDF 区域…")
        do {
            let image = try await Task.detached(priority: .userInitiated) { try PDFRegionRenderer.render(url: url, page: page, rect: rect) }.value
            let asset = "assets/\(UUID().uuidString).png"
            let source = SourceReference(paperID: id, page: page, rect: image.rect, asset: asset)
            try await store.addSource(source, image: image.png)
            guard selectedID == id else { throw EditorError.message(L("截图已保存到原论文资源文件夹；论文切换后未自动插入。")) }
            try await editor.insert(L("\n\n![PDF 第 \(page + 1) 页截图](\(asset))\n\n[来源 · 第 \(page + 1) 页](\(source.link))\n\n"))
            await flush(); status = L("截图已插入 · \(image.pixelWidth) × \(image.pixelHeight)")
        } catch { self.error = error.localizedDescription }
    }
    func quote() async {
        guard let id = selectedID else { return }
        let references = reader.selectionSources(paperID: id)
        guard !references.isEmpty else { error = L("请先在 PDF 中选择要摘录的文字。"); return }
        do {
            var markdown = "\n\n"
            for reference in references {
                try await store.addSource(reference)
                markdown += (reference.text ?? "").split(separator: "\n").map { line in
                    let punctuation = Set("\\`*_{}[]<>()#+-.!|$~=".map { $0 })
                    let escaped = line.map { punctuation.contains($0) ? "\\\($0)" : String($0) }.joined()
                    return "> \(escaped)"
                }.joined(separator: "\n")
                markdown += L("\n\n[来源 · 第 \(reference.page + 1) 页](\(reference.link))\n\n")
            }
            guard selectedID == id else { return }
            try await editor.insert(markdown); await flush()
        } catch { self.error = error.localizedDescription }
    }
    func openLink(_ url: URL) async {
        if url.scheme == "paperreader", url.host == "page", let number = Int(url.lastPathComponent) { reader.goToPage(number - 1); return }
        if url.scheme == "paperreader", let id = selectedID, ["source", "asset"].contains(url.host ?? "") {
            let sourceID = UUID(uuidString: url.lastPathComponent)
            let asset = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value
            do {
                if let source = try await store.sources(id).first(where: {
                    (url.host == "source" && $0.id == sourceID) || (url.host == "asset" && asset != nil && $0.asset == asset)
                }) { reader.reveal(source) }
            }
            catch { self.error = error.localizedDescription }
        } else if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
    }
    func importMarkdown() {
        guard let id = selectedID else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText, .plainText]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { do { try await self?.replaceNote(id, from: url) } catch { self?.error = error.localizedDescription } }
        }
    }
    func replaceNote(_ id: UUID, from url: URL, confirmReplacement: Bool = true) async throws {
        let markdown = try await Task.detached { try String(contentsOf: url, encoding: .utf8) }.value
        let analysis = try await editor.call("inspectMarkdown", markdown) as? [String: Any]
        guard selectedID == id else { return }
        if confirmReplacement {
            let alert = NSAlert(); alert.messageText = L("将 Markdown 导入当前笔记？")
            alert.informativeText = L("当前笔记会保留在 note.previous.md。相对路径的 PNG、JPEG、GIF 和 WebP 图片会复制到论文资源文件夹。")
            alert.addButton(withTitle: L("导入")); alert.addButton(withTitle: L("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let paths = try await store.importMarkdownAssets(id, paths: analysis?["images"] as? [String] ?? [], relativeTo: url.deletingLastPathComponent())
        let rewritten = try await editor.call("rewriteImages", ["markdown": markdown, "paths": paths]) as? String
        guard let rewritten, selectedID == id else { return }
        await save()
        guard !blocked.contains(id) else { throw LibraryError.externalChange }
        try await editor.setDocument(id: id, markdown: rewritten)
        noteChanged(id, markdown: rewritten); await flush()
    }
    func exportNotePDF() {
        guard let paper = currentPaper else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = L("\(paper.title) — 笔记.pdf")
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                guard let self else { return }; await self.save()
                guard self.selectedID == paper.id else { self.error = L("论文已切换，请在当前笔记中重新导出。"); return }
                do {
                    if try await self.editor.exportPDF(to: destination) { self.status = L("笔记 PDF 已导出") }
                    else { self.error = L("PDF 导出已取消。") }
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func exportMarkdown() {
        guard let id = selectedID else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = L("导出包含 note.md 和 assets 的独立文件夹")
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                guard let self else { return }; await self.save()
                do { try await self.store.exportNote(id, to: destination); self.status = L("Markdown 与资源已导出") }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func insertImage() {
        guard let id = selectedID else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                guard let self else { return }
                do {
                    let path = try await self.store.importAsset(id, from: url)
                    guard self.selectedID == id else { return }
                    try await self.editor.insert(L("\n\n![图片](\(path))\n\n")); await self.flush()
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func run(_ command: CommandID) {
        guard !isChangingWorkspace else { return }
        if runResearchCommand(command) { return }
        switch command {
        case .newFolder, .focus, .highlight, .selectText, .drawLine, .drawRectangle, .drawing, .laser, .undoAnnotation, .redoAnnotation, .exportAnnotated, .metadata, .askAI, .outline, .noteWindow: break
        case .open: openPanel()
        case .openFolder: openWorkspaceAction?()
        case .demo: Task { await openDemo() }
        case .save: Task { await save() }
        case .capture: ai.visible = false; reader.annotations.tool = .select; showNotes = true; reader.captureMode.toggle()
        case .quote: Task { await quote() }
        case .importMarkdown: importMarkdown()
        case .exportMarkdown: exportMarkdown()
        case .exportPDF: exportNotePDF()
        case .insertImage: insertImage()
        case .zoomIn: reader.view.zoomIn(nil)
        case .zoomOut: reader.view.zoomOut(nil)
        case .fit: reader.view.autoScales = true
        case .nextPage: reader.goToPage(reader.page + 1)
        case .previousPage: reader.goToPage(reader.page - 1)
        case .sidebar: showSidebar.toggle()
        case .notes: showNotes.toggle()
        case .revealFiles: if let id = selectedID { NSWorkspace.shared.activateFileViewerSelecting([store.pdfURL(id), store.noteURL(id)]) }
        }
    }
    func refreshWorkspace() async {
        guard !isRefreshingWorkspace, !isChangingWorkspace else { return }; isRefreshingWorkspace = true
        defer { isRefreshingWorkspace = false }
        do {
            var updated = try await store.scanWorkspace()
            if let id = selectedID, let index = updated.firstIndex(where: { $0.id == id }) {
                updated[index].page = reader.page; updated[index].scale = reader.scale; updated[index].readingPoint = reader.readingPosition
            }
            let groups = try await store.folders()
            guard !isChangingWorkspace else { return }
            if papers != updated { papers = updated }
            if folders != groups { folders = groups }
            if let id = selectedID, !updated.contains(where: { $0.id == id }) {
                await save(); selectedID = nil; commands.hasPaper = false
                reader.focus.enabled = false; reader.view.document = nil; await editor.clear()
            }
            if let id = selectedID {
                let recovered = try await store.recoverCloudNoteVersions(id)
                if !recovered.isEmpty { error = L("iCloud 冲突版本已保留为独立副本，可在笔记所在文件夹查看。") }
            }
            await checkExternalNote()
            if let waitingForPaper, papers.contains(where: { $0.id == waitingForPaper }) { await select(waitingForPaper) }
            await updateCloudStatus()
            if selectedID == nil, let first = papers.first { await select(first.id) }
        } catch { status = error.localizedDescription }
    }
    private func updateCloudStatus() async {
        guard workspaceIsCloud, let id = selectedID else { return }
        let url = store.noteURL(id)
        let result = await Task.detached { () -> (Bool, String?) in
            do {
                let values = try url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey])
                return (values.ubiquitousItemIsUploaded == true, (values.ubiquitousItemUploadingError ?? values.ubiquitousItemDownloadingError)?.localizedDescription)
            } catch { return (false, error.localizedDescription) }
        }.value
        if let error = result.1 { cloudStatus = L("iCloud 暂不可用：\(error)") }
        else { cloudStatus = result.0 ? L("当前笔记已上传到 iCloud") : L("已保存在本机 · 等待 iCloud 上传") }
    }
    private func checkExternalNote() async {
        guard !isChangingWorkspace, let id = selectedID, !isOpening, let revision = revisions[id], !blocked.contains(id) else { return }
        do {
            let note = try await store.readNote(id)
            guard selectedID == id, note.revision != revision else { return }
            await synchronizeEditor()
            if pending[id] != nil { await flush(); return }
            revisions[id] = note.revision
            try await editor.setDocument(id: id, markdown: note.markdown)
            status = L("外部修改已重新载入")
        } catch { status = error.localizedDescription }
    }

}

private enum PDFValidation {
    static func isValid(_ url: URL) -> Bool {
        guard let document = CGPDFDocument(url as CFURL) else { return false }
        return document.numberOfPages > 0 && !document.isEncrypted
    }
}
