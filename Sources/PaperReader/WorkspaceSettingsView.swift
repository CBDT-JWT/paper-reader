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
            Text(L("打开文件夹会按原有层级显示 PDF；关联笔记、图片与批注保存在该文件夹的 .paper-reader 目录。"))
            HStack {
                Button(L("打开文件夹…")) { bootstrap.chooseWorkspace(cloud: false) }
                Button(L("启用 iCloud Drive…")) { bootstrap.chooseWorkspace(cloud: true) }
            }.disabled(bootstrap.isSwitching)
            Button(L("打开原本机文献库")) { Task { await bootstrap.useLocalLibrary() } }.disabled(bootstrap.isSwitching)
            if bootstrap.isSwitching { ProgressView(L("正在准备工作区，原文献库会保留…")).controlSize(.small) }
            Text(L("在 iCloud Drive 中新建工作区时，会复制当前文献库；选择已有工作区则直接打开。同一 Apple 账户的其他 Mac 选择同一文件夹即可使用。"))
                .font(Design.small).foregroundStyle(.secondary)
            Text(L("PDF、笔记、资源、批注与文件夹信息参与同步。SQLite、阅读位置、API 密钥与 AI 会话留在本机。离线时可继续编辑已下载的文件；检测到笔记版本冲突会保留副本，不自动合并。"))
                .font(Design.small).foregroundStyle(.secondary)
        }.font(Design.body).padding(28).frame(width: 540, alignment: .leading)
    }
}
