import SwiftUI

struct SettingsView: View {
    @ObservedObject var registry: CommandRegistry
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷键").font(.system(size: 20, weight: .semibold))
            Text("修改后立即用于菜单栏、工具栏与右键菜单。Cmd+P 保留为打印。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(CommandID.allCases) { id in ShortcutRow(registry: registry, id: id) }
                }.padding(4)
            }
            HStack {
                Text("清空按键可取消绑定。编辑器保留常用文本编辑键。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { registry.reset() }
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
                TextField("无", text: $draft.key).frame(width: 42).textFieldStyle(.roundedBorder)
                Toggle("⌘", isOn: $draft.command)
                Toggle("⌥", isOn: $draft.option)
                Toggle("⇧", isOn: $draft.shift)
                Toggle("⌃", isOn: $draft.control)
                Spacer(minLength: 0)
                Button("应用") { error = registry.set(draft, for: id) }
            }.toggleStyle(.checkbox)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }
        .onAppear { draft = registry.shortcuts[id] ?? .init(key: "") }
        .onChange(of: registry.shortcuts[id]) { _, value in draft = value ?? .init(key: "") }
    }
}
