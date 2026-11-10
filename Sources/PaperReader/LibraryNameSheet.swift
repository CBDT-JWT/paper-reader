import SwiftUI
import PaperCore

struct LibraryNameRequest: Identifiable {
    enum Action { case newFolder(UUID?), renameFolder(UUID), renamePaper(UUID) }
    let id = UUID()
    let action: Action
    let title: String
    let initial: String
}

struct LibraryNameSheet: View {
    @ObservedObject var model: AppModel
    let request: LibraryNameRequest
    @State private var name = ""
    @State private var saving = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.title).font(Design.title)
            TextField(L("名称"), text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { save() }.accessibilityIdentifier("library.name")
            if invalid && !name.isEmpty { Text(L("名称不能为空，也不能包含斜杠或换行。")).font(Design.small).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L("取消")) { model.libraryNameRequest = nil }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(L("保存")) { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(invalid || saving)
            }
        }.font(Design.body).padding(24).frame(width: 400)
            .task { name = request.initial; focused = true }
    }
    private var invalid: Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || [".", ".."].contains(clean) || clean.contains("/") || clean.contains(where: { $0.isNewline })
    }
    private func save() {
        guard !invalid, !saving else { return }; saving = true
        Task { await model.saveLibraryName(request, name: name); saving = false }
    }
}
