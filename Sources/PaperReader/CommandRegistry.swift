import PaperCore
import SwiftUI
import PDFKit
import Combine

enum CommandID: String, CaseIterable, Codable, Identifiable {
    case newFolder, focus, highlight, selectText, drawLine, drawRectangle, drawing, laser, undoAnnotation, redoAnnotation, exportAnnotated, metadata, askAI, outline, noteWindow
    case open, demo, save, importMarkdown, exportMarkdown, exportPDF, insertImage
    case capture, quote, zoomIn, zoomOut, fit, nextPage, previousPage, sidebar, notes, revealFiles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .selectText: L("选择文字")
        case .drawLine: L("绘制直线")
        case .drawRectangle: L("绘制矩形")
        case .newFolder: L("新建文件夹…")
        case .focus: L("阅读聚焦")
        case .highlight: L("高亮选中文字")
        case .drawing: L("自由绘制")
        case .laser: L("激光笔")
        case .undoAnnotation: L("撤销批注")
        case .redoAnnotation: L("重做批注")
        case .exportAnnotated: L("导出带批注的 PDF…")
        case .metadata: L("文献信息与引用…")
        case .askAI: L("询问 AI")
        case .outline: L("论文目录")
        case .noteWindow: L("独立查看笔记")
        case .open: L("导入 PDF…")
        case .demo: L("打开示例论文")
        case .save: L("保存笔记")
        case .importMarkdown: L("导入 Markdown…")
        case .exportMarkdown: L("导出 Markdown 与资源…")
        case .exportPDF: L("导出笔记 PDF…")
        case .insertImage: L("插入图片…")
        case .capture: L("截图到笔记")
        case .quote: L("摘录到笔记")
        case .zoomIn: L("放大")
        case .zoomOut: L("缩小")
        case .fit: L("适合窗口")
        case .nextPage: L("下一页")
        case .previousPage: L("上一页")
        case .sidebar: L("显示／隐藏文献库")
        case .notes: L("显示／隐藏笔记")
        case .revealFiles: L("在 Finder 中显示文件")
        }
    }
    var symbol: String {
        switch self {
        case .selectText: "cursorarrow"
        case .drawLine: "line.diagonal"
        case .drawRectangle: "rectangle"
        case .newFolder: "folder.badge.plus"
        case .focus: "circle.dotted"
        case .highlight: "highlighter"
        case .drawing: "pencil.tip"
        case .laser: "laser.burst"
        case .undoAnnotation: "arrow.uturn.backward"
        case .redoAnnotation: "arrow.uturn.forward"
        case .exportAnnotated: "doc.badge.arrow.up"
        case .metadata: "info.circle"
        case .askAI: "sparkle"
        case .outline: "list.bullet.indent"
        case .noteWindow: "arrow.up.right.square"
        case .open: "plus"
        case .demo: "doc.text"
        case .save: "checkmark.circle"
        case .importMarkdown: "square.and.arrow.down"
        case .exportMarkdown, .exportPDF: "square.and.arrow.up"
        case .insertImage: "photo"
        case .capture: "viewfinder"
        case .quote: "text.quote"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .fit: "arrow.up.left.and.arrow.down.right"
        case .nextPage: "chevron.down"
        case .previousPage: "chevron.up"
        case .sidebar: "sidebar.left"
        case .notes: "sidebar.right"
        case .revealFiles: "folder"
        }
    }
    var needsPaper: Bool { ![.open, .demo, .newFolder, .sidebar, .notes].contains(self) }
}

struct CommandShortcut: Codable, Equatable {
    var key: String
    var command = true
    var option = false
    var shift = false
    var control = false
    var modifiers: EventModifiers {
        var value: EventModifiers = []
        if command { value.insert(.command) }; if option { value.insert(.option) }
        if shift { value.insert(.shift) }; if control { value.insert(.control) }; return value
    }
    var displayKey: String {
        let names = ["\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→", "\u{F729}": "↖", "\u{F72B}": "↘", "\u{F72C}": "⇞", "\u{F72D}": "⇟", "\t": "⇥", " ": "␣"]
        return names[key] ?? key.uppercased()
    }
    var display: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + displayKey }
    var normalized: String { "\(command)-\(option)-\(shift)-\(control)-\(key.lowercased())" }
    static let defaults: [CommandID: CommandShortcut] = [
        .askAI: .init(key: "g", option: true), .focus: .init(key: "f", option: true),
        .highlight: .init(key: "h", shift: true),
        .open: .init(key: "o"), .save: .init(key: "s"),
        .capture: .init(key: "s", option: true), .quote: .init(key: "e", shift: true),
        .zoomIn: .init(key: "="), .zoomOut: .init(key: "-"), .fit: .init(key: "0"),
        .sidebar: .init(key: "1", option: true), .notes: .init(key: "2", option: true)
    ]
}

@MainActor final class CommandRegistry: ObservableObject {
    @Published var shortcuts: [CommandID: CommandShortcut]
    @Published var hasPaper = false
    var handler: ((CommandID) -> Void)?
    init() {
        if let data = UserDefaults.standard.data(forKey: "commandShortcuts"),
           let saved = try? JSONDecoder().decode([CommandID: CommandShortcut].self, from: data) {
            shortcuts = saved
            if UserDefaults.standard.integer(forKey: "shortcutVersion") < 2 {
                for id in [CommandID.askAI, .focus, .highlight] {
                    if let value = CommandShortcut.defaults[id], shortcuts[id] == nil, !shortcuts.values.contains(where: { $0.normalized == value.normalized }) { shortcuts[id] = value }
                }
                UserDefaults.standard.set(2, forKey: "shortcutVersion")
                if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: "commandShortcuts") }
            }
        }
        else { shortcuts = CommandShortcut.defaults }
    }
    func run(_ command: CommandID) {
        guard !command.needsPaper || hasPaper else { return }
        handler?(command)
    }
    func conflict(_ shortcut: CommandShortcut?, for command: CommandID) -> String? {
        guard let shortcut, !shortcut.key.isEmpty else { return nil }
        guard shortcut.key.count == 1, shortcut.command || shortcut.control || shortcut.option else { return L("请输入一个字符，并选择至少一个修饰键。") }
        if shortcut.command && !shortcut.option && !shortcut.control && !shortcut.shift && ["p", "q", "w", "h", "m", "c", "v", "x", "a", "z", ",", "f"].contains(shortcut.key.lowercased()) {
            return L("该组合保留给 macOS 标准命令。")
        }
        if shortcut.command && shortcut.option && !shortcut.control && !shortcut.shift && ["h", "m"].contains(shortcut.key.lowercased()) { return L("该组合保留给 macOS 隐藏或最小化窗口。") }
        if shortcut.command && shortcut.control && shortcut.key.lowercased() == "q" { return L("该组合保留给 macOS 标准命令。") }
        if shortcut.command && shortcut.shift && !shortcut.option && !shortcut.control && ["3", "4", "5", "z"].contains(shortcut.key) { return L("该组合保留给系统截图或重做。") }
        if let other = shortcuts.first(where: { $0.key != command && $0.value.normalized == shortcut.normalized }) { return L("与“\(other.key.title)”冲突。") }
        return nil
    }
    func set(_ shortcut: CommandShortcut?, for command: CommandID) -> String? {
        if let error = conflict(shortcut, for: command) { return error }
        if let shortcut, !shortcut.key.isEmpty { shortcuts[command] = shortcut } else { shortcuts.removeValue(forKey: command) }
        if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: "commandShortcuts") }
        return nil
    }
    func menuItems(_ commands: [CommandID]) -> [NSMenuItem] {
        commands.map { id in
            let shortcut = shortcuts[id]
            let item = NSMenuItem(title: id.title, action: #selector(NativeCommandAction.invoke), keyEquivalent: shortcut?.key ?? "")
            let action = NativeCommandAction { [weak self] in self?.run(id) }
            item.target = action; item.representedObject = action
            var flags: NSEvent.ModifierFlags = []
            if shortcut?.command == true { flags.insert(.command) }; if shortcut?.option == true { flags.insert(.option) }
            if shortcut?.shift == true { flags.insert(.shift) }; if shortcut?.control == true { flags.insert(.control) }
            item.keyEquivalentModifierMask = flags; item.image = NSImage(systemSymbolName: id.symbol, accessibilityDescription: id.title)
            item.isEnabled = !id.needsPaper || hasPaper; return item
        }
    }
    func reset() {
        shortcuts = CommandShortcut.defaults
        UserDefaults.standard.removeObject(forKey: "commandShortcuts")
    }
}

struct RegisteredCommandButton: View {
    @ObservedObject var registry: CommandRegistry
    let id: CommandID
    var body: some View {
        if let shortcut = registry.shortcuts[id], let char = shortcut.key.first {
            Button(id.title, systemImage: id.symbol) { registry.run(id) }
                .keyboardShortcut(KeyEquivalent(char), modifiers: shortcut.modifiers)
                .disabled(id.needsPaper && !registry.hasPaper)
        } else {
            Button(id.title, systemImage: id.symbol) { registry.run(id) }
                .disabled(id.needsPaper && !registry.hasPaper)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var registry: CommandRegistry
    let printPaper: () -> Void
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            RegisteredCommandButton(registry: registry, id: .open)
            RegisteredCommandButton(registry: registry, id: .demo)
        }
        CommandGroup(after: .newItem) {
            Button(L("关闭窗口")) { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .saveItem) {
            ForEach([CommandID.save, .newFolder, .importMarkdown, .exportMarkdown, .exportPDF, .exportAnnotated, .metadata, .revealFiles]) { RegisteredCommandButton(registry: registry, id: $0) }
        }
        CommandGroup(replacing: .printItem) {
            Button(L("打印当前论文…")) { printPaper() }
                .keyboardShortcut("p").disabled(!registry.hasPaper)
        }
        CommandMenu(L("阅读")) {
            ForEach([CommandID.capture, .quote, .highlight, .selectText, .drawLine, .drawRectangle, .drawing, .laser, .focus, .undoAnnotation, .redoAnnotation, .askAI, .outline, .noteWindow, .zoomIn, .zoomOut, .fit, .previousPage, .nextPage, .sidebar, .notes]) { RegisteredCommandButton(registry: registry, id: $0) }
        }
    }
}

@MainActor private final class NativeCommandAction: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
