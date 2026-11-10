import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PaperCore

struct LibraryTreeView: View {
    @ObservedObject var model: AppModel
    @State private var sortByTitle = false
    @State private var dropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("文献库")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Menu {
                    Button(L("新建文件夹…"), systemImage: "folder.badge.plus") { model.createFolder() }
                    Toggle(L("按标题排序"), isOn: $sortByTitle)
                    Button(L("恢复已删除论文"), systemImage: "arrow.uturn.backward") { Task { await model.restoreTrash() } }
                } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30)
            }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索论文"), text: $model.query).textFieldStyle(.plain)
            }.font(.system(size: 14)).padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
            HStack { Text(L("所有论文")); Spacer(); Text("\(model.papers.count)").monospacedDigit() }
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if model.query.isEmpty {
                        ForEach(model.folders.filter { $0.parentID == nil }) { FolderBranch(model: model, folder: $0, sortByTitle: sortByTitle) }
                        ForEach(ordered(model.papers.filter { paper in paper.folderID == nil || !model.folders.contains(where: { $0.id == paper.folderID }) })) { PaperLibraryRow(model: model, paper: $0) }
                    } else { ForEach(ordered(model.filteredPapers)) { PaperLibraryRow(model: model, paper: $0) } }
                }.padding(.horizontal, 10).padding(.bottom, 12)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("本地文献库")).font(.system(size: 12, weight: .medium))
                    Text(L("PDF 与笔记，保存在本机")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(18)
        }.background(dropTargeted ? Color.accentColor.opacity(0.05) : Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL, .plainText], isTargeted: $dropTargeted) { handleLibraryDrop($0, folderID: nil, model: model) }
    }
    private func ordered(_ papers: [Paper]) -> [Paper] { sortByTitle ? papers.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : papers }
}
private struct FolderBranch: View {
    @ObservedObject var model: AppModel
    let folder: LibraryFolder
    let sortByTitle: Bool
    @State private var expanded = true
    @State private var targeted = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.folders.filter { $0.parentID == folder.id }) { FolderBranch(model: model, folder: $0, sortByTitle: sortByTitle) }
                ForEach(contents) { PaperLibraryRow(model: model, paper: $0) }
            }.padding(.top, 5)
        } label: {
            Label(folder.name, systemImage: expanded ? "folder.fill" : "folder").font(.system(size: 14, weight: .medium)).lineLimit(1).padding(.vertical, 7)
                .foregroundStyle(.secondary)
                .contextMenu {
                    Button(L("新建子文件夹…")) { model.createFolder(parentID: folder.id) }
                    Button(L("重命名…")) { model.renameFolder(folder) }
                    Menu(L("移动至")) {
                        Button(L("文献库")) { model.moveFolder(folder.id, to: nil) }
                        ForEach(model.folders.filter { $0.id != folder.id }) { target in Button(target.name) { model.moveFolder(folder.id, to: target.id) } }
                    }
                    Button(L("移除文件夹")) { model.removeFolder(folder) }
                }
        }.padding(.horizontal, 5).background(targeted ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .onDrop(of: [.plainText, .fileURL], isTargeted: $targeted) { handleLibraryDrop($0, folderID: folder.id, model: model) }
    }
    private var contents: [Paper] {
        let papers = model.papers.filter { $0.folderID == folder.id }
        return sortByTitle ? papers.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : papers
    }
}
private struct PaperLibraryRow: View {
    @ObservedObject var model: AppModel
    let paper: Paper
    var body: some View {
        Button { Task { await model.select(paper.id) } } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.richtext").font(.system(size: 14)).frame(width: 18, height: 20).foregroundStyle(model.selectedID == paper.id ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(paper.title).font(.system(size: 14, weight: model.selectedID == paper.id ? .medium : .regular)).lineLimit(3).multilineTextAlignment(.leading)
                    Text(paper.metadata?.year.map(String.init) ?? "PDF").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading).contentShape(RoundedRectangle(cornerRadius: 8))
                .background(model.selectedID == paper.id ? Color.accentColor.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).onDrag { NSItemProvider(object: paper.id.uuidString as NSString) }
            .contextMenu {
                Button(L("打开论文"), systemImage: "doc.richtext") { Task { await model.select(paper.id) } }
                Button(L("重命名…"), systemImage: "pencil") { model.rename(paper) }
                Menu(L("移动至")) {
                    Button(L("文献库")) { model.move(paper.id, to: nil) }
                    ForEach(model.folders) { folder in Button(folder.name) { model.move(paper.id, to: folder.id) } }
                }
                Button(L("在 Finder 中显示文件"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.pdfURL(paper.id), model.store.noteURL(paper.id)]) }
                Divider()
                Button(L("移到废纸篓"), systemImage: "trash", role: .destructive) { Task { await model.trashPaper(paper) } }
            }
    }
}
@MainActor private func handleLibraryDrop(_ providers: [NSItemProvider], folderID: UUID?, model: AppModel) -> Bool {
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in let imported = await model.importPDFs([url]); for paper in imported { model.move(paper.id, to: folderID) } }
            }
        } else {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text, let id = UUID(uuidString: text) else { return }; Task { @MainActor in model.move(id, to: folderID) }
            }
        }
    }
    return !providers.isEmpty
}
