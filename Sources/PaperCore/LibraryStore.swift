import Foundation
import CryptoKit
import CSQLite

/// All database and file IO is serialized off the UI actor. Notes remain ordinary UTF-8 files.
public actor LibraryStore {
    public nonisolated let root: URL
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("library.sqlite").path, &connection) == SQLITE_OK else {
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
    public nonisolated func pdfURL(_ id: UUID) -> URL { directory(id).appendingPathComponent("paper.pdf") }
    public nonisolated func noteURL(_ id: UUID) -> URL { directory(id).appendingPathComponent("note.md") }
    public static func revision(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    public func papers() throws -> [Paper] {
        // Manifests are the recovery authority if the index was lost or an import was interrupted.
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var records: [Paper] = []
        for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
            let manifest = directory.appendingPathComponent("paper.json")
            if let data = try? Data(contentsOf: manifest), let paper = try? decoder.decode(Paper.self, from: data) {
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
        let directory = directory(paper.id)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: url, to: pdfURL(paper.id))
            try Data("# \(paper.title)\n\n".utf8).write(to: noteURL(paper.id), options: .atomic)
            try persist(paper)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
        return paper
    }

    public func persist(_ paper: Paper) throws {
        try encoder.encode(paper).write(to: directory(paper.id).appendingPathComponent("paper.json"), options: .atomic)
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
        let text = try String(contentsOf: noteURL(id), encoding: .utf8)
        return NoteSnapshot(markdown: text, revision: Self.revision(text))
    }
    @discardableResult
    public func saveNote(_ id: UUID, markdown: String, expectedRevision: String) throws -> String {
        let url = noteURL(id)
        let existing = try String(contentsOf: url, encoding: .utf8)
        let revision = Self.revision(markdown)
        if Self.revision(existing) == revision { return revision }
        guard Self.revision(existing) == expectedRevision else {
            let conflict = directory(id).appendingPathComponent("note-conflict-\(UUID().uuidString).md")
            try Data(markdown.utf8).write(to: conflict, options: .atomic)
            throw LibraryError.externalChange
        }
        // Keep the previous complete version for recovery, then atomically replace.
        try Data(existing.utf8).write(to: directory(id).appendingPathComponent("note.previous.md"), options: .atomic)
        try Data(markdown.utf8).write(to: url, options: .atomic)
        return revision
    }

    public func sources(_ id: UUID) throws -> [SourceReference] {
        let url = directory(id).appendingPathComponent("sources.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([SourceReference].self, from: Data(contentsOf: url))
    }
    public func addSource(_ reference: SourceReference, image: Data? = nil) throws {
        var entries = try sources(reference.paperID)
        if let asset = reference.asset, let image {
            let url = try Self.containedURL(asset, in: directory(reference.paperID))
            try image.write(to: url, options: .atomic)
        }
        entries.append(reference)
        try encoder.encode(entries).write(to: directory(reference.paperID).appendingPathComponent("sources.json"), options: .atomic)
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
        try FileManager.default.copyItem(at: source, to: directory(id).appendingPathComponent(name))
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
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([LibraryFolder].self, from: Data(contentsOf: url))
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
        try encoder.encode(folders).write(to: root.appendingPathComponent("folders.json"), options: .atomic)
    }
    public func trash(_ id: UUID) throws {
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory(id), to: trash.appendingPathComponent(id.uuidString))
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
            guard let data = try? Data(contentsOf: $0.appendingPathComponent("paper.json")) else { return nil }
            return try? decoder.decode(Paper.self, from: data)
        }
    }
    public func restore(_ id: UUID) throws -> Paper {
        try FileManager.default.moveItem(at: root.appendingPathComponent(".Trash/\(id.uuidString)"), to: directory(id))
        let paper = try decoder.decode(Paper.self, from: Data(contentsOf: directory(id).appendingPathComponent("paper.json")))
        try index(paper); return paper
    }
    public func annotations(_ id: UUID) throws -> [PaperAnnotation] {
        let url = directory(id).appendingPathComponent("annotations.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([PaperAnnotation].self, from: Data(contentsOf: url))
    }
    public func saveAnnotations(_ id: UUID, records: [PaperAnnotation]) throws {
        try encoder.encode(records).write(to: directory(id).appendingPathComponent("annotations.json"), options: .atomic)
    }
    public func readSidecar(_ id: UUID, name: String) throws -> Data? {
        guard ["conversation.json"].contains(name) else { throw LibraryError.invalidPath }
        let url = directory(id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
    public func saveSidecar(_ id: UUID, name: String, data: Data) throws {
        guard ["conversation.json"].contains(name) else { throw LibraryError.invalidPath }
        try data.write(to: directory(id).appendingPathComponent(name), options: .atomic)
    }

    public func persistReading(_ id: UUID, page: Int, scale: Double, point: PDFPoint?) throws {
        var paper = try decoder.decode(Paper.self, from: Data(contentsOf: directory(id).appendingPathComponent("paper.json")))
        paper.page = page; paper.scale = scale; paper.readingPoint = point; try persist(paper)
    }

}
