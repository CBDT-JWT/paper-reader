import Foundation
import PaperCore

struct WorkspaceLocation: Sendable {
    let folder: URL
    let isCloud: Bool
    var data: URL { folder.appendingPathComponent(".paper-reader", isDirectory: true) }
    static let bookmarkKey = "workspace.bookmark.v1"
    static let cloudKey = "workspace.cloud.v1"
    static var localLibrary: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PaperReader/Library", isDirectory: true) }
    static var cloudHint: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true) }
    static func indexURL(for folder: URL) -> URL {
        let key = LibraryStore.revision(folder.standardizedFileURL.path)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PaperReader/WorkspaceIndexes/\(key)/library.sqlite")
    }
    static func isCloudFolder(_ folder: URL) -> Bool {
        var current = folder
        for _ in 0..<12 {
            if (try? current.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { return true }
            let parent = current.deletingLastPathComponent(); if parent == current { break }; current = parent
        }
        return false
    }
    static func resolve(bookmark: Data, cloud: Bool) throws -> WorkspaceLocation {
        var stale = false
        // The Developer ID distribution does not adopt App Sandbox. Ordinary bookmarks
        // survive relaunch without a sandbox-only security token tied to a process.
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
        return WorkspaceLocation(folder: url.standardizedFileURL, isCloud: cloud)
    }
    static func bookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func prepare() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw CocoaError(.fileNoSuchFile) }
        if isCloud, !ProcessInfo.processInfo.arguments.contains("--self-test"), !Self.isCloudFolder(folder) { throw LibraryError.notCloudFolder }
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let marker = data.appendingPathComponent("workspace.json")
        if FileManager.default.fileExists(atPath: marker.path) {
            let object = try JSONSerialization.jsonObject(with: CoordinatedFiles.read(marker)) as? [String: Any]
            guard object?["format"] as? Int == 1, object?["application"] as? String == "Paper Reader" else { throw LibraryError.invalidWorkspace }
        } else {
            try CoordinatedFiles.write(Data("{\"format\":1,\"application\":\"Paper Reader\"}".utf8), to: marker)
        }
    }
}

/// Directory notifications cover both the shared notes and original PDFs. No UI work runs here.
final class WorkspacePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let changed: @Sendable () -> Void
    init(url: URL, changed: @escaping @Sendable () -> Void) {
        presentedItemURL = url; self.changed = changed
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        presentedItemOperationQueue = queue
        super.init(); NSFileCoordinator.addFilePresenter(self)
    }
    func presentedItemDidChange() { changed() }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitemDidAppear(at url: URL) { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    deinit { NSFileCoordinator.removeFilePresenter(self) }
}
