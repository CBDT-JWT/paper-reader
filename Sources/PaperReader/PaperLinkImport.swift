import SwiftUI
import AppKit
import PaperCore

extension AppModel {
    @discardableResult
    func downloadPaper(from url: URL, folderID: UUID?, fileName: String? = nil, reveal: Bool = false) async throws -> Paper {
        guard !isChangingWorkspace else { throw CancellationError() }
        let download = try await PaperDownloadService.download(url, fileName: fileName)
        defer { download.cleanup() }
        try Task.checkCancellation()
        guard !isChangingWorkspace else { throw CancellationError() }
        let valid = await Task.detached { PDFValidation.isValid(download.file) }.value
        guard valid else { throw LibraryError.invalidPDF }
        let paper = try await store.importPDF(from: download.file, folderID: folderID, sourceURL: download.requestedURL, downloadURL: download.downloadURL, sourceVersion: download.sourceVersion)
        if !papers.contains(where: { $0.id == paper.id }) { papers.insert(paper, at: 0) }
        if let updated = try? await store.folders() { folders = updated }
        venueEnrichment.enqueue([paper.id])
        if reveal && !Task.isCancelled { await select(paper.id) }
        return paper
    }
}

struct PaperLinkImport: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @FocusState private var focused: Bool
    private var url: URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    private var destination: String {
        if let folder = model.folders.first(where: { $0.id == model.paperLinkImportFolder }) { return folder.sourceRelativePath ?? folder.name }
        return model.store.documentsRoot?.lastPathComponent ?? L("文献库")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("从链接导入论文")).font(Design.title)
            TextField(L("粘贴 arXiv、IEEE、DOI 或 PDF 链接"), text: $text).textFieldStyle(.roundedBorder)
                .focused($focused).onSubmit { start() }.disabled(busy).accessibilityIdentifier("paper.import.link")
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(L("保存到") + " " + destination)
            }.font(Design.small).foregroundStyle(.secondary)
            if busy { HStack { ProgressView().controlSize(.small); Text(L("正在解析并下载论文…")).font(Design.small).foregroundStyle(.secondary) } }
            if let error {
                Text(error).font(Design.small).foregroundStyle(.secondary).textSelection(.enabled)
                if let url { Button(L("打开来源网页")) { NSWorkspace.shared.open(url) } }
            }
            HStack {
                Spacer()
                Button(L("取消")) { job?.cancel(); model.paperLinkImportPresented = false }.keyboardShortcut(.cancelAction)
                Button(L("下载并导入")) { start() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(busy || url == nil)
            }
        }.font(Design.body).padding(24).frame(width: 480)
            .onAppear { focused = true }.onDisappear { job?.cancel() }
    }
    private func start() {
        guard !busy, let url else { return }
        busy = true; error = nil
        let folder = model.paperLinkImportFolder
        job = Task {
            do {
                try await model.downloadPaper(from: url, folderID: folder, reveal: true)
                model.paperLinkImportPresented = false
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
