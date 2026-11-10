import AppKit
import SwiftUI
import PaperCore

extension AppModel {
    func createFolder(parentID: UUID? = nil) { libraryNameRequest = .init(action: .newFolder(parentID), title: L("新建文件夹"), initial: "") }
    func rename(_ paper: Paper) { libraryNameRequest = .init(action: .renamePaper(paper.id), title: L("重命名论文"), initial: paper.displayFileName) }
    func renameFolder(_ folder: LibraryFolder) { libraryNameRequest = .init(action: .renameFolder(folder.id), title: L("重命名文件夹"), initial: folder.name) }
    @discardableResult
    func organizeLibrary(_ change: LibraryOrganizationChange) async -> Bool {
        do {
            try await store.organize(change)
            folders = try await store.folders(); papers = try await store.papers()
            if let activeFolderID, !folders.contains(where: { $0.id == activeFolderID }) { self.activeFolderID = nil }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func moveFolder(_ id: UUID, to parent: UUID?) { Task { await organizeLibrary(.moveFolder(id, parent)) } }
    func move(_ id: UUID, to folderID: UUID?) { Task { await organizeLibrary(.movePaper(id, folderID)) } }
    func removeFolder(_ folder: LibraryFolder) { Task { await organizeLibrary(.removeFolder(folder.id)) } }
    func saveLibraryName(_ request: LibraryNameRequest, name: String) async {
        let change: LibraryOrganizationChange
        var newID: UUID?
        switch request.action {
        case .newFolder(let parent):
            let folder = LibraryFolder(name: name, parentID: parent); newID = folder.id; change = .createFolder(folder)
        case .renameFolder(let id): change = .renameFolder(id, name)
        case .renamePaper(let id): change = .renamePaper(id, name)
        }
        if await organizeLibrary(change) {
            libraryNameRequest = nil
            if let newID { activeFolderID = newID }
        }
    }
    func trashPaper(_ paper: Paper) async {
        await save(); await reader.annotations.flush()
        if selectedID == paper.id { await ai.finish() }
        do {
            try await store.trash(paper.id); papers.removeAll { $0.id == paper.id }
            if selectedID == paper.id {
                selectedID = nil; reader.focus.enabled = false; ai.cancel(); ai.visible = false; commands.hasPaper = false; reader.view.document = nil; await editor.clear()
                if let next = papers.first { await select(next.id) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func restoreTrash() async {
        do { for paper in try await store.trashedPapers() { let restored = try await store.restore(paper.id); papers.insert(restored, at: 0) } }
        catch { self.error = error.localizedDescription }
    }
    func highlightSelection() {
        guard let selection = reader.view.currentSelection, let document = reader.view.document else { error = L("请先选择原文。"); return }
        let records = selection.selectionsByLine().flatMap { line in line.pages.map { page in PaperAnnotation(page: document.index(for: page), kind: .highlight, rect: PDFRect(line.bounds(for: page))) } }
        reader.annotations.add(records)
    }
    func exportAnnotations() {
        guard let paper = currentPaper else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = paper.title + L(" — 批注.pdf")
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            Task {
                await self.reader.annotations.flush(); let records = self.reader.annotations.records; let original = self.store.pdfURL(paper.id)
                do { try await PDFServices.exportAnnotated(original: original, destination: destination, annotations: records); self.status = L("批注 PDF 已导出") }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func lookupMetadata(paperID: UUID? = nil) async {
        guard let id = paperID ?? selectedID else { return }
        do {
            let url = store.pdfURL(id)
            let pages = try await Task.detached { try PDFServices.text(url: url) }.value
            let text = pages.prefix(3).map(\.text).joined(separator: "\n")
            let doi = MetadataService.doi(in: text)
            let arxiv = MetadataService.arxivID(in: text)
            let metadata: Bibliography
            if let doi { metadata = try await MetadataService.fetch(doi: doi) }
            else if let arxiv { metadata = try await MetadataService.fetchArxiv(id: arxiv) }
            else { if selectedID == id { status = L("未检测到 DOI 或 arXiv ID，可手动填写文献信息。") }; return }
            guard let index = papers.firstIndex(where: { $0.id == id }) else { return }
            let header = pages.first?.text.components(separatedBy: "\n").prefix(20).joined(separator: " ") ?? ""
            let normalized: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            let family = metadata.authors.first?.split(separator: ",").first.map(String.init) ?? ""
            guard (doi == nil || metadata.doi.lowercased() == doi?.lowercased()), normalized(header).contains(normalized(metadata.title)), family.isEmpty || normalized(header).contains(normalized(family)) else {
                metadataCandidates[id] = metadata
                if selectedID == id { status = L("找到候选文献，请在文献信息中确认。") }; return
            }
            papers[index].metadata = metadata; let value = papers[index]; try await store.persistMetadata(value.id, metadata: metadata)
            if selectedID == id { status = L("文献信息已更新") }
        } catch { status = error.localizedDescription }
    }
    func updateMetadata(_ metadata: Bibliography) async {
        guard let id = selectedID, let index = papers.firstIndex(where: { $0.id == id }) else { return }
        papers[index].metadata = metadata; metadataCandidates.removeValue(forKey: id); let value = papers[index]
        do { try await store.persistMetadata(value.id, metadata: metadata) } catch { self.error = error.localizedDescription }
    }
    func runResearchCommand(_ command: CommandID) -> Bool {
        switch command {
        case .newFolder: createFolder()
        case .highlight: highlightSelection()
        case .selectText: reader.annotations.tool = .select; reader.captureMode = false
        case .drawLine: reader.captureMode = false; reader.annotations.tool = .line
        case .drawRectangle: reader.captureMode = false; reader.annotations.tool = .rectangle
        case .focus: reader.focus.enabled.toggle()
        case .drawing: reader.captureMode = false; reader.annotations.tool = reader.annotations.tool == .ink ? .select : .ink
        case .laser: reader.captureMode = false; reader.annotations.tool = reader.annotations.tool == .laser ? .select : .laser
        case .undoAnnotation: reader.annotations.undo()
        case .redoAnnotation: reader.annotations.redo()
        case .exportAnnotated: exportAnnotations()
        case .metadata: metadataPresented = true
        case .askAI: ai.visible.toggle()
        case .outline: OutlineWindow.show(model: self)
        case .noteWindow: NoteWindow.show(model: self)
        default: return false
        }
        return true
    }
}
