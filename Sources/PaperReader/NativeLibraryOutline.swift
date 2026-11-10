import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PaperCore

/// The tree owns native drag tracking. Selecting a paper can update SwiftUI without
/// replacing a Button that is currently trying to begin a dragging session.
struct NativeLibraryOutline: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let outline = LibraryOutlineView(); outline.headerView = nil; outline.backgroundColor = .clear
        let column = NSTableColumn(identifier: .init("library")); column.resizingMask = .autoresizingMask
        outline.addTableColumn(column); outline.outlineTableColumn = column; outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.indentationPerLevel = 14; outline.intercellSpacing = .init(width: 0, height: 2)
        outline.style = .sourceList; outline.focusRingType = .none
        outline.dataSource = context.coordinator; outline.delegate = context.coordinator
        outline.target = context.coordinator; outline.doubleAction = #selector(Coordinator.openFolder(_:))
        outline.registerForDraggedTypes([.init(UTType.libraryItem.identifier), .fileURL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.menuForRow = { [weak coordinator = context.coordinator] row in coordinator?.menu(for: row) }
        outline.setAccessibilityLabel(L("文献库")); scroll.documentView = outline
        context.coordinator.outline = outline
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(model) }

    @MainActor final class Item: NSObject {
        let id: UUID
        let folder: LibraryFolder?
        let paper: Paper?
        var children: [Item] = []
        init(folder: LibraryFolder) { id = folder.id; self.folder = folder; paper = nil }
        init(paper: Paper) { id = paper.id; self.paper = paper; folder = nil }
    }
    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let model: AppModel
        weak var outline: NSOutlineView?
        private var roots: [Item] = []
        private var items: [UUID: Item] = [:]
        private struct PaperRow: Equatable {
            let id: UUID; let title: String; let filename: String; let folder: UUID?; let year: Int?; let imported: Date
            init(_ paper: Paper) { id = paper.id; title = paper.title; filename = paper.displayFileName; folder = paper.folderID; year = paper.metadata?.year; imported = paper.importedAt }
        }
        private var paperRows: [PaperRow] = []
        private var dragging = false
        private var papers: [Paper] = []
        private var folders: [LibraryFolder] = []
        private var sort: LibrarySort?
        private var ascending = true
        private var query = ""
        private var selectedPaper: UUID?
        private var activeFolder: UUID?
        private var refreshing = false
        init(model: AppModel) { self.model = model }
        func update(_ model: AppModel) {
            guard let outline, !dragging else { return }
            let rows = model.papers.map(PaperRow.init)
            let paperChanged = selectedPaper != model.selectedID
            let folderChanged = activeFolder != model.activeFolderID
            let dataChanged = paperRows != rows || folders != model.folders || sort != model.librarySort || ascending != model.librarySortAscending || query != model.query
            refreshing = true; defer { refreshing = false }
            if dataChanged {
                let expanded = Set(items.values.filter { $0.folder != nil && outline.isItemExpanded($0) }.map(\.id))
                let previous = Set(items.keys)
                paperRows = rows; papers = model.papers; folders = model.folders; sort = model.librarySort; ascending = model.librarySortAscending; query = model.query
                items = [:]
                func build(_ parent: UUID?, visited: Set<UUID>) -> [Item] {
                    let groups = LibraryHierarchy.ordered(folders.filter { folder in parent == nil ? folder.parentID == nil || !folders.contains(where: { $0.id == folder.parentID }) : folder.parentID == parent })
                    var nodes: [Item] = groups.filter { !visited.contains($0.id) }.map { folder in
                        let item = Item(folder: folder); items[folder.id] = item
                        item.children = build(folder.id, visited: visited.union([folder.id])); return item
                    }
                    let records = papers.filter { paper in parent == nil ? paper.folderID == nil || !folders.contains(where: { $0.id == paper.folderID }) : paper.folderID == parent }
                    nodes += model.librarySort.ordered(records, ascending: ascending).map { paper in let item = Item(paper: paper); items[paper.id] = item; return item }
                    return nodes
                }
                if query.isEmpty { roots = build(nil, visited: []) }
                else { roots = model.librarySort.ordered(model.filteredPapers, ascending: ascending).map { paper in let item = Item(paper: paper); items[paper.id] = item; return item } }
                outline.reloadData()
                for item in items.values where item.folder != nil && (expanded.contains(item.id) || !previous.contains(item.id)) { outline.expandItem(item) }
            }
            var target: UUID?
            if folderChanged && !paperChanged { target = model.activeFolderID ?? model.selectedID }
            else { target = model.selectedID }
            if dataChanged || paperChanged || folderChanged, let id = target, let item = items[id] {
                var parent = item.folder?.parentID ?? item.paper?.folderID
                var seen: Set<UUID> = [], ancestors: [Item] = []
                while let id = parent, seen.insert(id).inserted, let ancestor = items[id] {
                    ancestors.append(ancestor); parent = ancestor.folder?.parentID
                }
                for ancestor in ancestors.reversed() { outline.expandItem(ancestor) }
                if item.folder != nil { outline.expandItem(item) }
                let row = outline.row(forItem: item)
                if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            }
            selectedPaper = model.selectedID; activeFolder = model.activeFolderID
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Item)?.children.count ?? roots.count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Item)?.children ?? roots)[index] }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Item)?.folder != nil }
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { (item as? Item)?.folder != nil ? 34 : 50 }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            let view = LibraryCellView()
            view.title.stringValue = item.folder?.name ?? item.paper?.title ?? ""
            view.detail.stringValue = item.paper?.metadata?.year.map(String.init) ?? (item.paper == nil ? "" : "PDF")
            view.detail.isHidden = item.folder != nil
            view.icon.image = NSImage(systemSymbolName: item.folder != nil ? "folder" : "doc.richtext", accessibilityDescription: nil)
            view.icon.contentTintColor = item.folder != nil ? .secondaryLabelColor : .controlAccentColor
            view.toolTip = item.paper?.displayFileName ?? item.folder?.name
            view.setAccessibilityLabel(item.folder?.name ?? item.paper?.displayFileName)
            return view
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !refreshing, let outline, let item = outline.item(atRow: outline.selectedRow) as? Item else { return }
            if let folder = item.folder { model.activeFolderID = folder.id }
            else if let paper = item.paper, paper.id != model.selectedID { Task { await model.select(paper.id) } }
        }
        @objc func openFolder(_ sender: NSOutlineView) {
            guard let item = sender.item(atRow: sender.clickedRow) as? Item, item.folder != nil else { return }
            if sender.isItemExpanded(item) { sender.collapseItem(item) } else { sender.expandItem(item) }
        }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let item = item as? Item else { return nil }
            let payload = LibraryDragItem(id: item.id, folder: item.folder != nil)
            guard let data = try? JSONEncoder().encode(payload) else { return nil }
            let writer = NSPasteboardItem(); writer.setData(data, forType: .init(UTType.libraryItem.identifier)); return writer
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) { dragging = true }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = false; update(model) }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            let target = item as? Item
            guard target == nil || target?.folder != nil else { return [] }
            let board = info.draggingPasteboard
            if let data = board.data(forType: .init(UTType.libraryItem.identifier)), let payload = try? JSONDecoder().decode(LibraryDragItem.self, from: data) {
                if payload.folder, let parent = target?.id, LibraryHierarchy.descendants(of: payload.id, in: folders).contains(parent) { return [] }
                outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .move
            }
            if board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return .copy }
            return []
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            let target = item as? Item
            guard target == nil || target?.folder != nil else { return false }
            let board = info.draggingPasteboard
            if let data = board.data(forType: .init(UTType.libraryItem.identifier)) {
                return handleLibraryDrop([NSItemProvider(item: data as NSData, typeIdentifier: UTType.libraryItem.identifier)], folderID: target?.id, model: model)
            }
            let urls = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            guard !urls.isEmpty else { return false }
            Task {
                let directory = await Task.detached { urls.first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } }.value
                if let directory { model.openWorkspaceURLAction?(directory) }
                else { await model.importPDFs(urls.filter { $0.pathExtension.lowercased() == "pdf" }, into: target?.id) }
            }; return true
        }
        func menu(for row: Int) -> NSMenu {
            let menu = NSMenu()
            guard let item = outline?.item(atRow: row) as? Item else {
                for entry in model.commands.menuItems([.openFolder]) { menu.addItem(entry) }; menu.addItem(action(L("新建文件夹…")) { [model] in model.createFolder() }); return menu
            }
            if let folder = item.folder {
                menu.addItem(action(L("新建子文件夹…")) { [model] in model.createFolder(parentID: folder.id) })
                menu.addItem(action(L("导入 PDF 到此文件夹…")) { [model] in model.activeFolderID = folder.id; model.openPanel() })
                menu.addItem(action(L("重命名…")) { [model] in model.renameFolder(folder) })
            } else if let paper = item.paper {
                menu.addItem(action(L("打开论文")) { [model] in Task { await model.select(paper.id) } })
                menu.addItem(action(L("重命名…")) { [model] in model.rename(paper) })
            }
            let destinations = NSMenu(); let move = NSMenuItem(title: L("移动至"), action: nil, keyEquivalent: ""); move.submenu = destinations
            let apply: (UUID?) -> Void = { [model] parent in if item.folder != nil { model.moveFolder(item.id, to: parent) } else { model.move(item.id, to: parent) } }
            destinations.addItem(action(L("文献库")) { apply(nil) })
            let forbidden = item.folder != nil ? LibraryHierarchy.descendants(of: item.id, in: folders) : []
            for folder in LibraryHierarchy.ordered(folders) where !forbidden.contains(folder.id) { destinations.addItem(action(folder.name) { apply(folder.id) }) }
            menu.addItem(move); menu.addItem(.separator())
            if let folder = item.folder { menu.addItem(action(L("移除文件夹")) { [model] in model.removeFolder(folder) }) }
            if let paper = item.paper {
                menu.addItem(action(L("在 Finder 中显示文件")) { [model] in NSWorkspace.shared.activateFileViewerSelecting([model.store.pdfURL(paper.id), model.store.noteURL(paper.id)]) })
                menu.addItem(action(paper.sourceRelativePath == nil ? L("移到废纸篓") : L("从工作区移除（保留原 PDF）")) { [model] in Task { await model.trashPaper(paper) } })
            }
            return menu
        }
        private func action(_ title: String, perform: @escaping () -> Void) -> NSMenuItem {
            let target = LibraryMenuAction(perform)
            let item = NSMenuItem(title: title, action: #selector(LibraryMenuAction.run), keyEquivalent: "")
            item.target = target; item.representedObject = target; return item
        }
    }
}

@MainActor private final class LibraryOutlineView: NSOutlineView {
    var menuForRow: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { menuForRow?(row(at: convert(event.locationInWindow, from: nil))) }
}
@MainActor private final class LibraryMenuAction: NSObject {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
    @objc func run() { perform() }
}
@MainActor private final class LibraryCellView: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let icon = NSImageView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 14); title.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        let labels = NSStackView(views: [title, detail]); labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 3
        let row = NSStackView(views: [icon, labels]); row.spacing = 8; row.alignment = .centerY; row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row); imageView = icon; textField = title
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18), row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), row.centerYAnchor.constraint(equalTo: centerYAnchor)])
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }
}
