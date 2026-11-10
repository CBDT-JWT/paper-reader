import PaperCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var registry: CommandRegistry
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("快捷键")).font(.system(size: 20, weight: .semibold))
            Text(L("修改后立即用于菜单栏、工具栏与右键菜单。Cmd+P 保留为打印。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(CommandID.allCases) { id in ShortcutRow(registry: registry, id: id) }
                }.padding(4)
            }
            HStack {
                Text(L("点击按键框录制；Delete 清除，Esc 取消。编辑器保留常用文本编辑键。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(L("恢复默认")) { registry.reset() }
            }
        }.font(.system(size: 14)).padding(24).frame(width: 760, height: 590)
    }
}

private struct ShortcutRow: View {
    @ObservedObject var registry: CommandRegistry
    let id: CommandID
    @State private var draft = CommandShortcut(key: "")
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(id.title).frame(width: 210, alignment: .leading)
                ShortcutRecorder(shortcut: $draft, title: id.title).frame(width: 118, height: 30)
                Spacer(minLength: 0)
                Button(L("应用")) { error = registry.set(draft, for: id) }
            }.toggleStyle(.checkbox)
            if let error { Text(L(error)).font(.system(size: 12)).foregroundStyle(.red) }
        }
        .onAppear { draft = registry.shortcuts[id] ?? .init(key: "") }
        .onChange(of: registry.shortcuts[id]) { _, value in draft = value ?? .init(key: "") }
    }
}
