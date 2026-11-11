import SwiftUI
import AppKit
import PaperCore

@main enum ApplicationEntry {
    @MainActor static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.count == 4, arguments[1] == "--verify-workspace-bookmark" {
            do {
                let bookmark = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
                let workspace = try WorkspaceLocation.resolve(bookmark: bookmark, cloud: false)
                let expected = URL(fileURLWithPath: arguments[3]).resolvingSymlinksInPath().standardizedFileURL.path
                exit(workspace.folder.resolvingSymlinksInPath().standardizedFileURL.path == expected ? 0 : 1)
            } catch { exit(1) }
        }
        if arguments.count == 3, arguments[1] == "--export-annotations" {
            do {
                let request = try JSONDecoder().decode(AnnotationExportRequest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
                try PDFServices.writeAnnotated(request)
                exit(0)
            } catch { exit(1) }
        }
        PaperReaderApp.main()
    }
}

struct PaperReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var bootstrap = AppBootstrap()
    @StateObject private var updates = AppUpdateController()
    var body: some Scene {
        WindowGroup("Paper Reader", id: "workspace") {
            Group {
                if let model = bootstrap.model { WorkspaceView(model: model).id(ObjectIdentifier(model))
                    .disabled(bootstrap.isSwitching)
                    .overlay { if bootstrap.isSwitching { ProgressView(L("正在准备工作区，原文献库会保留…")).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) } } }
                else {
                    VStack(spacing: 16) {
                        Text("Paper Reader").font(.system(size: 20, weight: .semibold))
                        if let error = bootstrap.error {
                            Text(error).font(.system(size: 14)).foregroundStyle(.secondary).textSelection(.enabled)
                            Button(L("重试")) { Task { await bootstrap.start(delegate: delegate) } }.font(.system(size: 14))
                            Button(L("打开原本机文献库")) { Task { await bootstrap.useLocalLibrary() } }.font(Design.body)
                            Button(L("打开文件夹…")) { bootstrap.chooseWorkspace(cloud: false) }.font(Design.body)
                        } else { ProgressView(L("正在打开本地文献库…")).font(.system(size: 14)) }
                    }.padding(30).frame(minWidth: 1060, minHeight: 650)
                }
            }.task { await bootstrap.start(delegate: delegate); updates.start() }
        }
        .defaultSize(width: 1440, height: 920)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("检查更新…")) { updates.check() }.disabled(!updates.canCheck)
            }
            AppCommands(registry: bootstrap.commands, printPaper: { bootstrap.model?.reader.view.print(with: NSPrintInfo.shared, autoRotate: true) })
            CommandGroup(after: .undoRedo) {
                Button(L("撤销笔记编辑")) { bootstrap.model?.editor.format("undo") }.disabled(bootstrap.model == nil)
                Button(L("重做笔记编辑")) { bootstrap.model?.editor.format("redo") }.disabled(bootstrap.model == nil)
            }
        }
        Settings {
            TabView {
                WorkspaceSettingsView(bootstrap: bootstrap).tabItem { Label(L("文献库与 iCloud"), systemImage: "icloud") }
                UpdateSettingsView(updates: updates).tabItem { Label(L("更新"), systemImage: "arrow.triangle.2.circlepath") }
                SettingsView(registry: bootstrap.commands).tabItem { Label(L("快捷键"), systemImage: "keyboard") }
                if let model = bootstrap.model { AISettingsView(settings: model.ai.settings).tabItem { Label("AI", systemImage: "sparkle") } }
            }
        }
    }
}

@MainActor final class AppBootstrap: ObservableObject {
    let commands = CommandRegistry()
    let preferences: UserDefaults = ProcessInfo.processInfo.arguments.contains("--workspace-self-test") ? UserDefaults(suiteName: "PaperReader.WorkspaceSelfTest")! : .standard
    @Published var model: AppModel?
    @Published var error: String?
    private var isStarting = false
    @Published private(set) var location: WorkspaceLocation?
    @Published private(set) var isSwitching = false
    private weak var applicationDelegate: AppDelegate?
    private var scopedURL: URL?
    func start(delegate: AppDelegate) async {
        guard model == nil, !isStarting else { return }
        isStarting = true; error = nil; applicationDelegate = delegate
        do {
            let root = AppModel.defaultRoot
            var selected: WorkspaceLocation?
            if ProcessInfo.processInfo.environment["PAPER_READER_LIBRARY"] == nil, let bookmark = preferences.data(forKey: WorkspaceLocation.bookmarkKey) {
                let cloud = preferences.bool(forKey: WorkspaceLocation.cloudKey)
                selected = try await Task.detached { try WorkspaceLocation.resolve(bookmark: bookmark, cloud: cloud) }.value
                if let selected { _ = selected.folder.startAccessingSecurityScopedResource(); scopedURL = selected.folder }
            }
            let workspace = selected
            let store = try await Task.detached(priority: .userInitiated) {
                if let workspace { try workspace.prepare(); return try LibraryStore(root: workspace.data, indexURL: WorkspaceLocation.indexURL(for: workspace.folder), documentsRoot: workspace.folder) }
                return try LibraryStore(root: root)
            }.value
            location = selected
            let appModel = AppModel(store: store, commands: commands)
            wire(appModel); model = appModel; delegate.model = appModel
            if ProcessInfo.processInfo.arguments.contains("--workspace-self-test") { await WorkspaceSelfTest.run(bootstrap: self) }
            else if ProcessInfo.processInfo.arguments.contains("--self-test") {
                if ProcessInfo.processInfo.arguments.contains("--ai-self-test") { await AISelfTest.runStandalone(model: appModel) }
                else { await IntegrationSelfTest.run(model: appModel) }
            }
            else if ProcessInfo.processInfo.arguments.contains("--website-demo") { await WebsiteDemo.prepare(model: appModel) }
            else { await appModel.start(); await delegate.openPendingFiles() }
        } catch { self.error = error.localizedDescription }
        isStarting = false
    }
    private func wire(_ model: AppModel) {
        model.openWorkspaceAction = { [weak self] in self?.chooseWorkspace(cloud: false) }
        model.openWorkspaceURLAction = { [weak self] url in
            Task {
                let cloud = await Task.detached { WorkspaceLocation.isCloudFolder(url) }.value
                await self?.openWorkspace(.init(folder: url.standardizedFileURL, isCloud: cloud), copyCurrent: false)
            }
        }
        model.workspaceIsCloud = location?.isCloud == true
    }
    func chooseWorkspace(cloud: Bool) {
        guard !isSwitching else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowedContentTypes = [.folder]
        panel.message = cloud ? L("在 iCloud Drive 中选择或新建 Paper Reader 文件夹。原文献库会保留。") : L("选择已有的论文文件夹，按原有层级打开 PDF。")
        if cloud { panel.directoryURL = WorkspaceLocation.cloudHint }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                let detected = await Task.detached { WorkspaceLocation.isCloudFolder(url) }.value
                await self?.openWorkspace(WorkspaceLocation(folder: url.standardizedFileURL, isCloud: cloud || detected), copyCurrent: cloud)
            }
        }
    }
    func openWorkspace(_ workspace: WorkspaceLocation, copyCurrent: Bool, remember: Bool = true) async {
        guard !isSwitching else { return }; isSwitching = true
        defer { isSwitching = false }
        _ = workspace.folder.startAccessingSecurityScopedResource()
        var candidate: LibraryStore?
        do {
            if workspace.isCloud, !ProcessInfo.processInfo.arguments.contains("--self-test"), !(await Task.detached { WorkspaceLocation.isCloudFolder(workspace.folder) }.value) { throw LibraryError.notCloudFolder }
            model?.isChangingWorkspace = true
            await model?.waitForDocumentJobs(); await model?.ai.finish()
            if let editor = model?.editor, editor.ready { _ = try await editor.call("setReadOnly", true) }
            model?.editor.isFrozen = true
            await model?.save()
            guard model?.canLeaveWorkspace != false else { throw LibraryError.externalChange }
            if copyCurrent, let old = model?.store, old.root.standardizedFileURL != workspace.data.standardizedFileURL {
                let existing = await Task.detached { FileManager.default.fileExists(atPath: workspace.data.path) }.value
                if !existing {
                    let staging = workspace.folder.appendingPathComponent(".paper-reader-import-" + UUID().uuidString)
                    try await old.copyLibrary(to: staging)
                    try await Task.detached { try CoordinatedFiles.move(staging, to: workspace.data) }.value
                }
            }
            try await Task.detached { try workspace.prepare() }.value
            let store = try await Task.detached { try LibraryStore(root: workspace.data, indexURL: WorkspaceLocation.indexURL(for: workspace.folder), documentsRoot: workspace.folder) }.value
            candidate = store
            _ = try await store.scanWorkspace()
            let bookmark = try await Task.detached { try WorkspaceLocation.bookmark(for: workspace.folder) }.value
            try await model?.store.copyDeviceState(to: store.deviceDirectory)
            await model?.shutdown()
            await model?.store.close()
            scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = workspace.folder
            location = workspace
            let replacement = AppModel(store: store, commands: commands); wire(replacement)
            model = replacement; applicationDelegate?.model = replacement
            if remember {
                preferences.set(bookmark, forKey: WorkspaceLocation.bookmarkKey)
                preferences.set(workspace.isCloud, forKey: WorkspaceLocation.cloudKey)
            }
            await replacement.start()
        } catch {
            await candidate?.close()
            model?.isChangingWorkspace = false; model?.editor.isFrozen = false
            if let editor = model?.editor, editor.ready { _ = try? await editor.call("setReadOnly", false) }
            workspace.folder.stopAccessingSecurityScopedResource(); model?.error = error.localizedDescription; self.error = error.localizedDescription
        }
    }
    func useLocalLibrary() async {
        guard !isSwitching else { return }; isSwitching = true
        defer { isSwitching = false }
        do {
            let root = AppModel.defaultRoot
            let store = try await Task.detached { try LibraryStore(root: root) }.value
            model?.isChangingWorkspace = true
            await model?.waitForDocumentJobs(); await model?.ai.finish()
            if let editor = model?.editor, editor.ready { _ = try await editor.call("setReadOnly", true) }
            model?.editor.isFrozen = true
            await model?.save()
            guard model?.canLeaveWorkspace != false else { throw LibraryError.externalChange }
            await model?.shutdown(); await model?.store.close(); scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil; location = nil
            let replacement = AppModel(store: store, commands: commands); wire(replacement)
            model = replacement; applicationDelegate?.model = replacement
            preferences.removeObject(forKey: WorkspaceLocation.bookmarkKey)
            preferences.removeObject(forKey: WorkspaceLocation.cloudKey)
            await replacement.start()
        } catch {
            model?.isChangingWorkspace = false; model?.editor.isFrozen = false
            if let editor = model?.editor, editor.ready { _ = try? await editor.call("setReadOnly", false) }
            model?.error = error.localizedDescription; self.error = error.localizedDescription
        }
    }

}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminating = false
    private var pendingFiles: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        NSApp.activate(ignoringOtherApps: true)
    }
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
