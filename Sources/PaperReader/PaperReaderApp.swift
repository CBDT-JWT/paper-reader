import SwiftUI
import AppKit
import PaperCore

@main struct PaperReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var bootstrap = AppBootstrap()
    var body: some Scene {
        WindowGroup("Paper Reader", id: "workspace") {
            Group {
                if let model = bootstrap.model { WorkspaceView(model: model) }
                else {
                    VStack(spacing: 16) {
                        Text("Paper Reader").font(.system(size: 20, weight: .semibold))
                        if let error = bootstrap.error {
                            Text(error).font(.system(size: 14)).foregroundStyle(.secondary).textSelection(.enabled)
                            Button("重试") { Task { await bootstrap.start(delegate: delegate) } }.font(.system(size: 14))
                        } else { ProgressView("正在打开本地文献库…").font(.system(size: 14)) }
                    }.padding(30).frame(minWidth: 1060, minHeight: 650)
                }
            }.task { await bootstrap.start(delegate: delegate) }
        }
        .defaultSize(width: 1440, height: 920)
        .windowStyle(.titleBar)
        .commands {
            AppCommands(registry: bootstrap.commands, printPaper: { bootstrap.model?.reader.view.print(with: NSPrintInfo.shared, autoRotate: true) })
            CommandGroup(after: .undoRedo) {
                Button("撤销笔记编辑") { bootstrap.model?.editor.format("undo") }.disabled(bootstrap.model == nil)
                Button("重做笔记编辑") { bootstrap.model?.editor.format("redo") }.disabled(bootstrap.model == nil)
            }
        }
        Settings { SettingsView(registry: bootstrap.commands) }
    }
}

@MainActor private final class AppBootstrap: ObservableObject {
    let commands = CommandRegistry()
    @Published var model: AppModel?
    @Published var error: String?
    private var isStarting = false
    func start(delegate: AppDelegate) async {
        guard model == nil, !isStarting else { return }
        isStarting = true; error = nil
        do {
            let root = AppModel.defaultRoot
            let store = try await Task.detached(priority: .userInitiated) { try LibraryStore(root: root) }.value
            let appModel = AppModel(store: store, commands: commands)
            model = appModel; delegate.model = appModel
            if ProcessInfo.processInfo.arguments.contains("--self-test") { await IntegrationSelfTest.run(model: appModel) }
            else { await appModel.start(); await delegate.openPendingFiles() }
        } catch { self.error = error.localizedDescription }
        isStarting = false
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminating = false
    private var pendingFiles: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating, let model else { return .terminateNow }
        terminating = true
        Task { await model.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pendingFiles += filenames.map { URL(fileURLWithPath: $0) }
        Task { await openPendingFiles(); sender.reply(toOpenOrPrint: .success) }
    }
    func openPendingFiles() async {
        guard let model, !pendingFiles.isEmpty else { return }
        let files = pendingFiles; pendingFiles.removeAll(); await model.importPDFs(files)
    }
}
