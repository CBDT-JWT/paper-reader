import Foundation
import CryptoKit
import CSQLite
import os

/// All database and file IO is serialized off the UI actor. Notes remain ordinary UTF-8 files.
public actor LibraryStore {
    public nonisolated let root: URL
    public nonisolated let documentsRoot: URL?
    public nonisolated let deviceDirectory: URL
    private nonisolated let sourcePaths = OSAllocatedUnfairLock(initialState: [UUID: String]())
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(root: URL, indexURL: URL? = nil, documentsRoot: URL? = nil) throws {
        self.root = root; self.documentsRoot = documentsRoot?.resolvingSymlinksInPath().standardizedFileURL
        let indexURL = indexURL ?? root.appendingPathComponent("library.sqlite")
        self.deviceDirectory = indexURL.deletingLastPathComponent().appendingPathComponent("DeviceData", isDirectory: true)
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open(indexURL.path, &connection) == SQLITE_OK else {
            sqlite3_close(connection); throw LibraryError.database("open")
        }
        db = connection
        let schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS papers (id TEXT PRIMARY KEY, record BLOB NOT NULL);"
        guard sqlite3_exec(connection, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(connection); db = nil; throw LibraryError.database("schema")
        }
    }
    // SQLite connection remains actor confined; shutdown is explicit to avoid Sendable deinit access.
    public func close() { sqlite3_close(db); db = nil }
    public nonisolated func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public nonisolated func pdfURL(_ id: UUID) -> URL {
        if let documentsRoot, let path = sourcePaths.withLock({ $0[id] }), let url = try? Self.containedURL(path, in: documentsRoot) { return url }
        return directory(id).appendingPathComponent("paper.pdf")
    }
    public nonisolated func noteURL(_ id: UUID) -> URL { directory(id).appendingPathComponent("note.md") }
    public static func revision(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    public func papers() throws -> [Paper] {
        // Manifests are the recovery authority if the index was lost or an import was interrupted.
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var records: [Paper] = []
        for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
            let manifest = directory.appendingPathComponent("paper.json")
            if documentsRoot != nil && (CoordinatedFiles.needsDownload(manifest) || !FileManager.default.fileExists(atPath: manifest.path)) {
                _ = try? CoordinatedFiles.requestDownload(directory)
                throw LibraryError.workspaceDownloading
            }
            if documentsRoot != nil {
                let bytes = try CoordinatedFiles.read(manifest)
                guard let decoded = try? decoder.decode(Paper.self, from: bytes), decoded.id == UUID(uuidString: directory.lastPathComponent) else { throw LibraryError.invalidWorkspace }
            }
            if let data = try? CoordinatedFiles.read(manifest), var paper = try? decoder.decode(Paper.self, from: data) {
                if let path = paper.sourceRelativePath { let id = paper.id; sourcePaths.withLock { $0[id] = path } }
                if let reading = try? decoder.decode(ReadingState.self, from: Data(contentsOf: readingURL(paper.id))) {
                    paper.page = reading.page; paper.scale = reading.scale; paper.readingPoint = reading.point
                }
                try index(paper); records.append(paper)
            }
        }
        return records.sorted { $0.importedAt > $1.importedAt }
    }

    public func importPDF(from url: URL, folderID: UUID? = nil) throws -> Paper {
        if let folderID, try !folders().contains(where: { $0.id == folderID }) { throw LibraryError.invalidPath }
        let prefix = try FileHandle(forReadingFrom: url)
        let header = try prefix.read(upToCount: 1024) ?? Data(); try prefix.close()
        guard String(decoding: header, as: UTF8.self).contains("%PDF-") else { throw LibraryError.invalidPDF }
        var paper = Paper(title: url.deletingPathExtension().lastPathComponent)
        paper.fileName = url.lastPathComponent; paper.folderID = folderID
        var target = directory(paper.id).appendingPathComponent("paper.pdf")
        var needsCopy = true
        if let documentsRoot {
            let prefix = documentsRoot.standardizedFileURL.path + "/"
            if url.standardizedFileURL.path.hasPrefix(prefix), !url.path.hasPrefix(root.path + "/") {
                let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
                if let existing = try papers().first(where: { $0.sourceRelativePath == path }) { return existing }
                paper.sourceRelativePath = path; target = url; needsCopy = false
            } else {
                var groups = try folders()
                let path = try sourceFolderPath(folderID, groups: &groups)
                try saveFolders(groups)
                let base = path.isEmpty ? documentsRoot : try Self.containedURL(path, in: documentsRoot)
                var candidate = base.appendingPathComponent(url.lastPathComponent)
                var suffix = 2
                while FileManager.default.fileExists(atPath: candidate.path) {
                    candidate = base.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(suffix).pdf"); suffix += 1
                }
                target = candidate; paper.fileName = candidate.lastPathComponent
                paper.sourceRelativePath = String(candidate.path.dropFirst(documentsRoot.path.count + 1))
            }
        }
        let directory = directory(paper.id)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        do {
            if needsCopy { try CoordinatedFiles.copy(url, to: target) }
            try CoordinatedFiles.write(Data("# \(paper.title)\n\n".utf8), to: noteURL(paper.id))
            try persist(paper)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
        return paper
    }

    public func persist(_ paper: Paper) throws {
        var shared = paper; shared.page = 0; shared.scale = 0; shared.readingPoint = nil
        if let path = paper.sourceRelativePath { let id = paper.id; sourcePaths.withLock { $0[id] = path } }
        try CoordinatedFiles.write(encoder.encode(shared), to: directory(paper.id).appendingPathComponent("paper.json"))
        try saveReading(paper.id, state: ReadingState(page: paper.page, scale: paper.scale, point: paper.readingPoint))
        try index(paper)
    }
    private func index(_ paper: Paper) throws {
        guard let db else { throw LibraryError.database("closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO papers(id,record) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK else {
            throw LibraryError.database(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let data = try encoder.encode(paper)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, paper.id.uuidString, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LibraryError.database(String(cString: sqlite3_errmsg(db))) }
    }

    public func readNote(_ id: UUID) throws -> NoteSnapshot {
        guard let text = String(data: try CoordinatedFiles.read(noteURL(id)), encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return NoteSnapshot(markdown: text, revision: Self.revision(text))
    }
    @discardableResult
    public func saveNote(_ id: UUID, markdown: String, expectedRevision: String) throws -> String {
        let url = noteURL(id)
        let revision = Self.revision(markdown)
        _ = try CoordinatedFiles.preserveConflicts(at: url)
        try CoordinatedFiles.update(url) { existingData in
            guard let existing = String(data: existingData ?? Data(), encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            if Self.revision(existing) == revision { return Data(markdown.utf8) }
            guard existingData != nil, Self.revision(existing) == expectedRevision else {
                let container = FileManager.default.fileExists(atPath: directory(id).path) ? directory(id) : root.appendingPathComponent("Recovered Edits", isDirectory: true)
                let conflict = container.appendingPathComponent("note-conflict-\(id.uuidString)-\(UUID().uuidString).md")
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                try CoordinatedFiles.write(Data(markdown.utf8), to: conflict)
                throw LibraryError.externalChange
            }
            try CoordinatedFiles.write(Data(existing.utf8), to: directory(id).appendingPathComponent("note.previous.md"))
            return Data(markdown.utf8)
        }
        return revision
    }

    public func sources(_ id: UUID) throws -> [SourceReference] {
        let url = directory(id).appendingPathComponent("sources.json")
        guard let data = try CoordinatedFiles.readOptional(url) else { return [] }
        return try decoder.decode([SourceReference].self, from: data)
    }
    public func addSource(_ reference: SourceReference, image: Data? = nil) throws {
        if let asset = reference.asset, let image {
            let url = try Self.containedURL(asset, in: directory(reference.paperID))
            try CoordinatedFiles.write(image, to: url)
        }
        let url = directory(reference.paperID).appendingPathComponent("sources.json")
        try CoordinatedFiles.update(url) { previous in
            var entries = try previous.map { try decoder.decode([SourceReference].self, from: $0) } ?? []
            entries.append(reference)
            return try encoder.encode(entries)
        }
    }
    public static func containedURL(_ path: String, in directory: URL) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains(":") else { throw LibraryError.invalidPath }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let components = (path as NSString).pathComponents
        guard !components.contains(".."), !components.contains("."), !components.isEmpty else { throw LibraryError.invalidPath }
        var url = root
        for component in components {
            url.appendPathComponent(component)
            // Foundation may leave an intermediate symlink unresolved when the leaf is absent.
            // Reject symlinks component by component, including dangling ones.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil { throw LibraryError.invalidPath }
        }
        url = url.standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw LibraryError.invalidPath }
        return url
    }
    public func exportNote(_ id: UUID, to destination: URL) throws {
        let target = destination.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        do {
            for name in ["note.md", "sources.json", "paper.json", "assets"] {
                let file = directory(id).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.copyItem(at: file, to: target.appendingPathComponent(name))
                }
            }
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
    public func importAsset(_ id: UUID, from source: URL) throws -> String {
        let name = "assets/\(UUID().uuidString).\(source.pathExtension.lowercased())"
        try CoordinatedFiles.copy(source, to: directory(id).appendingPathComponent(name))
        return name
    }
    /// Copies only explicitly referenced, contained image assets. Never overwrites an existing asset.
    public func importMarkdownAssets(_ id: UUID, paths: [String], relativeTo folder: URL) throws -> [String: String] {
        let allowed = Set(["png", "jpg", "jpeg", "gif", "webp"])
        let sources: [(String, URL)] = try Set(paths).map { path in
            let source = try Self.containedURL(path.removingPercentEncoding ?? path, in: folder)
            guard allowed.contains(source.pathExtension.lowercased()), FileManager.default.isReadableFile(atPath: source.path) else {
                throw LibraryError.invalidPath
            }
            return (path, source)
        }
        var copied: [String: String] = [:]
        do {
            for (path, source) in sources { copied[path] = try importAsset(id, from: source) }
            return copied
        } catch {
            for path in copied.values { try? FileManager.default.removeItem(at: directory(id).appendingPathComponent(path)) }
            throw error
        }
    }

    public func folders() throws -> [LibraryFolder] {
        let url = root.appendingPathComponent("folders.json")
        guard let data = try CoordinatedFiles.readOptional(url) else { return [] }
        return try decoder.decode([LibraryFolder].self, from: data)
    }
    public func saveFolders(_ folders: [LibraryFolder]) throws {
        let ids = Set(folders.map(\.id))
        guard ids.count == folders.count else { throw LibraryError.invalidPath }
        for folder in folders {
            var visited: Set<UUID> = [folder.id]
            var parent = folder.parentID
            while let id = parent {
                guard ids.contains(id), visited.insert(id).inserted else { throw LibraryError.invalidPath }
                parent = folders.first(where: { $0.id == id })?.parentID
            }
        }
        try CoordinatedFiles.write(encoder.encode(folders), to: root.appendingPathComponent("folders.json"))
    }
    public func trash(_ id: UUID) throws {
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try CoordinatedFiles.move(directory(id), to: trash.appendingPathComponent(id.uuidString))
        guard let db else { return }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "DELETE FROM papers WHERE id=?", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(statement)
    }
    public func trashedPapers() throws -> [Paper] {
        let folder = root.appendingPathComponent(".Trash")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).compactMap {
            if documentsRoot != nil && (CoordinatedFiles.needsDownload($0.appendingPathComponent("paper.json")) || !FileManager.default.fileExists(atPath: $0.appendingPathComponent("paper.json").path)) { throw LibraryError.workspaceDownloading }
            guard let data = try? CoordinatedFiles.read($0.appendingPathComponent("paper.json")) else { return nil }
            return try? decoder.decode(Paper.self, from: data)
        }
    }
    public func restore(_ id: UUID) throws -> Paper {
        try CoordinatedFiles.move(root.appendingPathComponent(".Trash/\(id.uuidString)"), to: directory(id))
        let paper = try decoder.decode(Paper.self, from: Data(contentsOf: directory(id).appendingPathComponent("paper.json")))
        try index(paper); return paper
    }
    public func annotations(_ id: UUID) throws -> [PaperAnnotation] {
        let url = directory(id).appendingPathComponent("annotations.json")
        guard let data = try CoordinatedFiles.readOptional(url) else { return [] }
        return try decoder.decode([PaperAnnotation].self, from: data)
    }
    public func saveAnnotations(_ id: UUID, records: [PaperAnnotation]) throws {
        try CoordinatedFiles.write(encoder.encode(records), to: directory(id).appendingPathComponent("annotations.json"))
    }
    public func readSidecar(_ id: UUID, name: String) throws -> Data? {
        guard ["conversation.json"].contains(name) else { throw LibraryError.invalidPath }
        let local = deviceDirectory.appendingPathComponent(id.uuidString + "." + name)
        if FileManager.default.fileExists(atPath: local.path) { return try Data(contentsOf: local) }
        let legacy = directory(id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: legacy.path) ? try CoordinatedFiles.read(legacy) : nil
    }
    public func saveSidecar(_ id: UUID, name: String, data: Data) throws {
        guard ["conversation.json"].contains(name) else { throw LibraryError.invalidPath }
        try data.write(to: deviceDirectory.appendingPathComponent(id.uuidString + "." + name), options: .atomic)
    }

    public func record(_ id: UUID) throws -> Paper {
        var paper = try decoder.decode(Paper.self, from: CoordinatedFiles.read(directory(id).appendingPathComponent("paper.json")))
        if let reading = try? decoder.decode(ReadingState.self, from: Data(contentsOf: readingURL(id))) {
            paper.page = reading.page; paper.scale = reading.scale; paper.readingPoint = reading.point
        }
        return paper
    }
    private struct ReadingState: Codable { let page: Int; let scale: Double; let point: PDFPoint? }
    private func readingURL(_ id: UUID) -> URL { deviceDirectory.appendingPathComponent(id.uuidString + ".reading.json") }
    private func saveReading(_ id: UUID, state: ReadingState) throws {
        try encoder.encode(state).write(to: readingURL(id), options: .atomic)
    }
    public func persistReading(_ id: UUID, page: Int, scale: Double, point: PDFPoint?) throws {
        try saveReading(id, state: ReadingState(page: page, scale: scale, point: point))
    }
    public func recoverCloudNoteVersions(_ id: UUID) throws -> [URL] {
        try CoordinatedFiles.preserveConflicts(at: noteURL(id))
    }
}
