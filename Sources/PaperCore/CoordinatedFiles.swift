import Foundation

/// Cooperates with iCloud Drive and other document editors. Call off the main actor.
public enum CoordinatedFiles {
    public static func readOptional(_ url: URL) throws -> Data? {
        if needsDownload(url) { throw LibraryError.workspaceDownloading }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url)
    }
    public static func read(_ url: URL) throws -> Data {
        if needsDownload(url) { throw LibraryError.workspaceDownloading }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try Data(contentsOf: coordinated) }
        }
        if let coordinationError { throw coordinationError }
        return try result.unwrap().get()
    }
    public static func write(_ data: Data, to url: URL) throws {
        try update(url) { _ in data }
    }
    public static func update(_ url: URL, transform: (Data?) throws -> Data) throws {
        if needsDownload(url) { throw LibraryError.workspaceDownloading }
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            result = Result {
                let previous = FileManager.default.fileExists(atPath: coordinated.path) ? try Data(contentsOf: coordinated) : nil
                let data = try transform(previous)
                if previous != data { try data.write(to: coordinated, options: .atomic) }
            }
        }
        if let coordinationError { throw coordinationError }
        try result.unwrap().get()
    }
    public static func copy(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forReplacing, error: &coordinationError) { source, destination in
            result = Result { try FileManager.default.copyItem(at: source, to: destination) }
        }
        if let coordinationError { throw coordinationError }
        try result.unwrap().get()
    }
    public static func move(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { source, destination in
            result = Result {
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        try result.unwrap().get()
    }
    public static func needsDownload(_ url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        let legacy = FileManager.default.fileExists(atPath: placeholder.path)
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        let pending = legacy || (values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus == .notDownloaded)
        if pending { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
        return pending
    }
    /// Requests hydration without treating an evicted file as a deleted document.
    @discardableResult public static func requestDownload(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        }
        return false
    }
    /// Preserve system conflict versions as ordinary files before resolving their system flags.
    public static func preserveConflicts(at url: URL) throws -> [URL] {
        var copies: [URL] = []
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            let data = try read(version.url)
            let digest = LibraryStore.revision(data.base64EncodedString())
            let name = url.deletingPathExtension().lastPathComponent + "-icloud-conflict-" + digest.prefix(16) + "." + url.pathExtension
            let destination = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) { try write(data, to: destination); copies.append(destination) }
            version.isResolved = true
        }
        return copies
    }
}
private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else { throw CocoaError(.fileReadUnknown) }; return self
    }
}
