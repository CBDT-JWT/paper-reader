import SwiftUI
import PaperCore

struct WorkspaceSettingsView: View {
    @ObservedObject var bootstrap: AppBootstrap
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("文献库与 iCloud")).font(Design.title)
            Label(bootstrap.location?.isCloud == true ? L("iCloud Drive 工作区") : L("本地工作区"), systemImage: bootstrap.location?.isCloud == true ? "icloud" : "folder")
            Text(bootstrap.location?.folder.path ?? AppModel.defaultRoot.path)
                .font(Design.small).foregroundStyle(.secondary).textSelection(.enabled)
            Text(L("打开文件夹后，整个工作区共用根目录的一份 Markdown；图片保存在 assets，批注直接写入 PDF。"))
            HStack {
                Button(L("打开文件夹…")) { bootstrap.chooseWorkspace(cloud: false) }
                Button(L("启用 iCloud Drive…")) { bootstrap.chooseWorkspace(cloud: true) }
            }.disabled(bootstrap.isSwitching)
            Button(L("打开原本机文献库")) { Task { await bootstrap.useLocalLibrary() } }.disabled(bootstrap.isSwitching)
            if bootstrap.isSwitching { ProgressView(L("正在准备工作区，原文献库会保留…")).controlSize(.small) }
            Text(L("在 iCloud Drive 中新建工作区时，会复制当前文献库；选择已有工作区则直接打开。同一 Apple 账户的其他 Mac 选择同一文件夹即可使用。"))
                .font(Design.small).foregroundStyle(.secondary)
            Text(L("PDF、根目录笔记和 assets 随所选文件夹同步。索引、阅读位置、草稿和 AI 会话留在本机。"))
                .font(Design.small).foregroundStyle(.secondary)
        }.font(Design.body).padding(28).frame(width: 540, alignment: .leading)
    }
}
