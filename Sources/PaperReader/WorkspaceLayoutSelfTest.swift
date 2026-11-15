import AppKit
import PDFKit
import PaperCore

/// Focused native regressions use the standalone AI runner's disposable library.
@MainActor enum WorkspaceLayoutSelfTest {
    static func run(model: AppModel, output: URL) async throws -> [String] {
        var checks: [String] = []
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw IntegrationSelfTest.Failure(message: message) }
            checks.append(message)
        }
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(450))
            model.reader.view.window?.contentView?.layoutSubtreeIfNeeded()
        }
        for _ in 0..<100 {
            if model.reader.view.window != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let window = model.reader.view.window,
              let split = findSplit(in: window.contentView), split.arrangedSubviews.count == 4 else {
            throw IntegrationSelfTest.Failure(message: "Workspace split missing")
        }
        let ai = model.ai, pdf = model.reader.view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ai.settings.models = ["layout-fixture"]
        let savedVisibility = model.showAssetFolders
        defer { model.showAssetFolders = savedVisibility }
        model.showSidebar = true; model.showNotes = true
        ai.expanded = false
        try await settle()
        try await IntegrationSelfTest.setFullScreen(true, window: window)
        try await settle()
        try check(!window.titlebarAppearsTransparent, "Full-screen titlebar has an explicit opaque background")
        try check(window.backgroundColor == WorkspacePalette.chromeNS, "Window fallback uses the white content surface")
        try snapshot(window, to: output.appendingPathComponent("fullscreen-closed.png"))

        ai.expanded = true
        try await settle()
        let initialWidth = split.arrangedSubviews[3].frame.width
        try check((320...560).contains(initialWidth), "Conversation opens at a bounded remembered width")
        guard let page = pdf.document?.page(at: 0),
              let selection = page.selection(for: page.bounds(for: .cropBox)) else {
            throw IntegrationSelfTest.Failure(message: "PDF selection missing")
        }
        pdf.setCurrentSelection(selection, animate: false)
        model.commands.run(.askAI)
        try await settle()
        try check(ai.pendingQuote != nil && abs(split.arrangedSubviews[3].frame.width - initialWidth) < 2, "Ask AI adds the selected PDF quote without changing drawer width")
        ai.pendingQuote = AIQuote(text: String(repeating: "LongSelectedTokenWithoutSpaces", count: 80), label: "Fixture quote")
        try await settle()
        try check(abs(split.arrangedSubviews[3].frame.width - initialWidth) < 2, "A long unbroken quote keeps the drawer width")
        // Reserve the reader minimum so AppKit can resize either adjacent pane.
        split.setPosition(split.arrangedSubviews[0].frame.maxX + split.dividerThickness + 360, ofDividerAt: 1)
        try await settle()
        let requestedWidth: CGFloat = initialWidth < 440 ? 500 : 360
        split.setPosition(split.bounds.maxX - requestedWidth - split.dividerThickness, ofDividerAt: 2)
        try await settle()
        let resizedWidth = split.arrangedSubviews[3].frame.width
        try check((320...560).contains(resizedWidth) && abs(resizedWidth - initialWidth) > 2,
                  "The conversation divider resizes within the native pane constraints")
        ai.expanded = false; try await settle()
        ai.expanded = true; try await settle()
        try check(abs(split.arrangedSubviews[3].frame.width - resizedWidth) < 2, "Closing and reopening preserves the resized drawer width")
        try snapshot(window, to: output.appendingPathComponent("fullscreen-open.png"))

        pdf.scaleFactor = 1.77
        try await settle()
        guard let line = selection.selectionsByLine().first(where: { line in
            let rect = pdf.convert(line.bounds(for: page), from: page).intersection(pdf.visibleRect)
            return line.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && !rect.isNull && rect.height > 0 && pdf.visibleRect.insetBy(dx: 20, dy: 24).contains(NSPoint(x: rect.midX, y: rect.midY))
        }) else { throw IntegrationSelfTest.Failure(message: "Visible selection line missing") }
        pdf.setCurrentSelection(line, animate: false)
        let lineRect = pdf.convert(line.bounds(for: page), from: page).intersection(pdf.visibleRect)
        let point = pdf.convert(NSPoint(x: lineRect.midX, y: lineRect.midY), to: nil)
        window.makeFirstResponder(pdf)
        pdf.showSelectionActions(at: point)
        for _ in 0..<50 {
            if pdf.selectionActionsFrameInScreen != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await settle()
        let pointInScreen = window.convertPoint(toScreen: point)
        try check(pdf.selectionActionsAnchorInScreen?.insetBy(dx: -2, dy: -2).contains(pointInScreen) == true,
                  "Selection anchor matches the released screen point")
        guard let popover = pdf.selectionActionsFrameInScreen else {
            throw IntegrationSelfTest.Failure(message: "Selection actions missing")
        }
        try check(popover.insetBy(dx: -24, dy: -32).contains(pointInScreen), "Selection actions anchor to the released selection in full screen at 177% zoom")
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                           charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
            throw IntegrationSelfTest.Failure(message: "Escape fixture missing")
        }
        pdf.keyDown(with: escape)
        try check(!pdf.selectionActionsVisible, "Escape dismisses the selection toolbar")
        pdf.showSelectionActions(at: point)
        pdf.scaleFactor = 1.6
        try await settle()
        try check(!pdf.selectionActionsVisible, "Zooming dismisses a stale selection toolbar")

        let assets = LibraryFolder(name: "assets"), papers = LibraryFolder(name: "Papers")
        let child = LibraryFolder(name: "images", parentID: assets.id)
        try await model.store.saveFolders([assets, child, papers])
        model.folders = try await model.store.folders()
        model.showAssetFolders = false
        try await settle()
        guard let outline = IntegrationSelfTest.findOutline(in: window.contentView) else { throw IntegrationSelfTest.Failure(message: "File tree missing") }
        func folderRows() -> [String] {
            (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? NativeLibraryOutline.Item)?.folder?.name }
        }
        try check(folderRows() == ["Papers"] && model.hiddenLibraryFolderIDs == [assets.id, child.id], "The file tree hides assets and its descendants by default")
        model.showAssetFolders = true; try await settle()
        try check(folderRows().contains("assets"), "Show Asset Folders reveals the resource folder")
        guard let row = (0..<outline.numberOfRows).first(where: { (outline.item(atRow: $0) as? NativeLibraryOutline.Item)?.folder?.id == papers.id }) else {
            throw IntegrationSelfTest.Failure(message: "Folder row missing")
        }
        window.makeFirstResponder(outline)
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        try await settle()
        guard let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView else { throw IntegrationSelfTest.Failure(message: "Folder cell missing") }
        try check(cell.backgroundStyle == .emphasized && cell.textField?.textColor == NSColor.white && cell.imageView?.contentTintColor == NSColor.white,
                  "Selected folder text and icon use white against the blue row")
        try snapshot(window, to: output.appendingPathComponent("fullscreen-folder.png"))
        try await IntegrationSelfTest.setFullScreen(false, window: window)
        try await settle()
        try snapshot(window, to: output.appendingPathComponent("windowed.png"))
        return checks
    }

    private static func findSplit(in view: NSView?) -> NSSplitView? {
        if let split = view as? NSSplitView, split.identifier?.rawValue == "workspace.split" { return split }
        for child in view?.subviews ?? [] { if let split = findSplit(in: child) { return split } }
        return nil
    }
    private static func snapshot(_ window: NSWindow, to url: URL) throws {
        guard let root = window.contentView?.superview,
              let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
