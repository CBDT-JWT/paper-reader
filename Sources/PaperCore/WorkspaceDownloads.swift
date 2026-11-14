import Foundation
import Darwin

public struct WorkspaceDownload: Codable, Sendable, Equatable {
    public let path: String
    public let bytes: Int
    public let sourceURL: URL
    public let mimeType: String?
}

extension LibraryStore {
    /// The only model-writable content is a completed HTTP download inside this workspace.
    public func downloadFile(from source: URL, folder: String = "", fileName: String? = nil) async throws -> WorkspaceDownload {
        guard ["https", "http"].contains(source.scheme?.lowercased() ?? ""), source.host != nil,
              source.user == nil, source.password == nil else { throw LibraryError.invalidPath }
        let base = documentsRoot ?? root.appendingPathComponent("Downloads", isDirectory: true)
        let directory = folder.isEmpty ? base : try Self.containedURL(folder, in: base)
        // Validate before requesting the URL, including intermediate symlinks.
        if !folder.isEmpty { _ = try Self.containedURL(folder, in: base) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source)
        request.timeoutInterval = 300
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, ["https", "http"].contains(finalURL.scheme?.lowercased() ?? "") else {
            throw AIError.message(L("文件下载失败，请检查下载链接。"))
        }
        try Task.checkCancellation()
        let name = fileName ?? response.suggestedFilename ?? source.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw LibraryError.invalidPath }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = try Self.containedURL(".download-" + UUID().uuidString, in: directory)
        try FileManager.default.copyItem(at: temporary, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let size = try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var suffix = 1
        while true {
            try Task.checkCancellation()
            let candidate = suffix == 1 ? name : stem + " (\(suffix))" + (ext.isEmpty ? "" : "." + ext)
            let relative = folder.isEmpty ? candidate : folder + "/" + candidate
            let destination = try Self.containedURL(relative, in: base)
            // A same-volume hard link publishes the complete file atomically and never replaces a name.
            if Darwin.link(staging.path, destination.path) == 0 {
                return WorkspaceDownload(path: relative, bytes: size, sourceURL: finalURL, mimeType: response.mimeType)
            }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            suffix += 1
        }
    }
    public nonisolated var downloadDirectory: URL { documentsRoot ?? root.appendingPathComponent("Downloads", isDirectory: true) }
}
