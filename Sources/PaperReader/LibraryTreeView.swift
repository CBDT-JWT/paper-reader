import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PaperCore

private extension LibrarySort {
    var label: String { switch self { case .filename: L("文件名"); case .title: L("标题"); case .recent: L("导入时间") } }
}
extension UTType { static let libraryItem = UTType(exportedAs: "dev.paperreader.library-item") }
struct LibraryDragItem: Codable { let id: UUID; let folder: Bool
    var provider: NSItemProvider { NSItemProvider(item: try! JSONEncoder().encode(self) as NSData, typeIdentifier: UTType.libraryItem.identifier) }
}

struct LibraryTreeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(L("文献库")).font(Design.title)
                Spacer(minLength: 0)
                Button { model.createFolder(parentID: model.activeFolderID) } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(WorkspaceIconStyle()).help(L("新建文件夹…")).accessibilityLabel(L("新建文件夹…"))
                Menu {
                    Picker(L("排序方式"), selection: $model.librarySort) {
                        ForEach(LibrarySort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.inline)
                    Toggle(L("倒序排列"), isOn: Binding(get: { !model.librarySortAscending }, set: { model.librarySortAscending = !$0 }))
                    Divider()
                    Button(L("恢复已删除论文"), systemImage: "arrow.uturn.backward") { Task { await model.restoreTrash() } }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 30, height: 30) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30)
                    .help(L("排序方式")).accessibilityLabel(L("排序方式"))
            }.padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索论文"), text: $model.query).textFieldStyle(.plain)
            }.font(Design.body).padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
            Button { model.activeFolderID = nil } label: {
                HStack { Text(L("所有论文")); Spacer(); Text("\(model.papers.count)").monospacedDigit() }
                    .font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 10).contentShape(Rectangle())
            }.buttonStyle(.plain)
            NativeLibraryOutline(model: model)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("本地文献库")).font(.system(size: 12, weight: .medium))
                    Text(L("PDF 与笔记，保存在本机")).font(Design.small).foregroundStyle(.secondary)
                }
            }.padding(18)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}
@MainActor func handleLibraryDrop(_ providers: [NSItemProvider], folderID: UUID?, model: AppModel) -> Bool {
    let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.libraryItem.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    for provider in accepted {
        if provider.hasItemConformingToTypeIdentifier(UTType.libraryItem.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.libraryItem.identifier) { data, _ in
                guard let data, let item = try? JSONDecoder().decode(LibraryDragItem.self, from: data) else { return }
                Task { @MainActor in
                    let moved = await model.organizeLibrary(item.folder ? .moveFolder(item.id, folderID) : .movePaper(item.id, folderID))
                    if moved { model.activeFolderID = folderID }
                }
            }
        } else {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in _ = await model.importPDFs([url], into: folderID) }
            }
        }
    }
    return !accepted.isEmpty
}
