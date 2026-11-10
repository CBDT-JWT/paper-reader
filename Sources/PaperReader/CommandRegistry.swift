import SwiftUI
import PDFKit
import Combine

enum CommandID: String, CaseIterable, Codable, Identifiable {
    case open, demo, save, importMarkdown, exportMarkdown, exportPDF, insertImage
    case capture, quote, zoomIn, zoomOut, fit, nextPage, previousPage, sidebar, notes, revealFiles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "导入 PDF…"
        case .demo: "打开示例论文"
        case .save: "保存笔记"
        case .importMarkdown: "导入 Markdown…"
        case .exportMarkdown: "导出 Markdown 与资源…"
        case .exportPDF: "导出笔记 PDF…"
        case .insertImage: "插入图片…"
        case .capture: "截图到笔记"
        case .quote: "摘录到笔记"
        case .zoomIn: "放大"
        case .zoomOut: "缩小"
        case .fit: "适合窗口"
        case .nextPage: "下一页"
        case .previousPage: "上一页"
        case .sidebar: "显示／隐藏文献库"
        case .notes: "显示／隐藏笔记"
        case .revealFiles: "在 Finder 中显示文件"
        }
    }
    var symbol: String {
        switch self {
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
    var needsPaper: Bool { ![.open, .demo, .sidebar, .notes].contains(self) }
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
    var display: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased() }
    var normalized: String { "\(command)-\(option)-\(shift)-\(control)-\(key.lowercased())" }
    static let defaults: [CommandID: CommandShortcut] = [
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
           let saved = try? JSONDecoder().decode([CommandID: CommandShortcut].self, from: data) { shortcuts = saved }
        else { shortcuts = CommandShortcut.defaults }
    }
    func run(_ command: CommandID) {
        guard !command.needsPaper || hasPaper else { return }
        handler?(command)
    }
    func conflict(_ shortcut: CommandShortcut?, for command: CommandID) -> String? {
        guard let shortcut, !shortcut.key.isEmpty else { return nil }
        guard shortcut.key.count == 1, shortcut.command || shortcut.control || shortcut.option else { return "请输入一个字符，并选择至少一个修饰键。" }
        if shortcut.command && !shortcut.option && !shortcut.control && !shortcut.shift && ["p", "q", "w", "h", "m", "c", "v", "x", "a", "z", ",", "f"].contains(shortcut.key.lowercased()) {
            return "该组合保留给 macOS 标准命令。"
        }
        if shortcut.command && shortcut.option && !shortcut.control && !shortcut.shift && ["h", "m"].contains(shortcut.key.lowercased()) { return "该组合保留给 macOS 隐藏或最小化窗口。" }
        if shortcut.command && shortcut.shift && !shortcut.option && !shortcut.control && ["3", "4", "5", "z"].contains(shortcut.key) { return "该组合保留给系统截图或重做。" }
        if let other = shortcuts.first(where: { $0.key != command && $0.value.normalized == shortcut.normalized }) { return "与“\(other.key.title)”冲突。" }
        return nil
    }
    func set(_ shortcut: CommandShortcut?, for command: CommandID) -> String? {
        if let error = conflict(shortcut, for: command) { return error }
        if let shortcut, !shortcut.key.isEmpty { shortcuts[command] = shortcut } else { shortcuts.removeValue(forKey: command) }
        if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: "commandShortcuts") }
        return nil
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
            Button("关闭窗口") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .saveItem) {
            ForEach([CommandID.save, .importMarkdown, .exportMarkdown, .exportPDF, .revealFiles]) { RegisteredCommandButton(registry: registry, id: $0) }
        }
        CommandGroup(replacing: .printItem) {
            Button("打印当前论文…") { printPaper() }
                .keyboardShortcut("p").disabled(!registry.hasPaper)
        }
        CommandMenu("阅读") {
            ForEach([CommandID.capture, .quote, .zoomIn, .zoomOut, .fit, .previousPage, .nextPage, .sidebar, .notes]) { RegisteredCommandButton(registry: registry, id: $0) }
        }
    }
}
