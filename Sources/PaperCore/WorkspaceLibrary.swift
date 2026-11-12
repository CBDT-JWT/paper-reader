import Foundation

extension LibraryStore {
    /// Discover a user-selected folder in place. PDFs are linked by relative path, never moved on open.
    public func scanWorkspace() async throws -> [Paper] {
        let records = try scanWorkspaceFiles()
        for paper in records where FileManager.default.fileExists(atPath: directory(paper.id).appendingPathComponent("annotations.json").path) {
            _ = try await annotations(paper.id)
        }
        return records
    }
    private func scanWorkspaceFiles() throws -> [Paper] {
        guard let documentsRoot else { return try papers() }
        try prepareWorkspaceDocuments()
        var records = try papers()
        var groups = try folders()
        var foldersByPath = Dictionary(groups.compactMap { folder in folder.sourceRelativePath.map { ($0, folder.id) } }, uniquingKeysWith: { first, _ in first })
        var papersByPath = Dictionary(records.compactMap { paper in paper.sourceRelativePath.map { ($0, paper.id) } }, uniquingKeysWith: { first, _ in first })
        let ignored = Set(try trashedPapers().compactMap(\.sourceRelativePath))
        let identityURL = deviceDirectory.appendingPathComponent("workspace-files.json")
        var identities = (try? JSONDecoder().decode([String: UUID].self, from: Data(contentsOf: identityURL))) ?? [:]
        let previousGroups = groups
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileResourceIdentifierKey]
        guard let enumerator = FileManager.default.enumerator(at: documentsRoot, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return records }
        for case let discovered as URL in enumerator {
            let url = discovered.standardizedFileURL
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
            let path = String(url.path.dropFirst(documentsRoot.path.count + 1))
            if values.isDirectory == true {
                if foldersByPath[path] == nil {
                    var folder = LibraryFolder(name: url.lastPathComponent, parentID: foldersByPath[(path as NSString).deletingLastPathComponent])
                    folder.sourceRelativePath = path; groups.append(folder); foldersByPath[path] = folder.id
                }
                continue
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "pdf", !ignored.contains(path) else { continue }
            let identity = values.fileResourceIdentifier.map { String(describing: $0) }
            let parent = foldersByPath[(path as NSString).deletingLastPathComponent]
            if let id = papersByPath[path] {
                if let identity { identities[identity] = id }; continue
            }
            if let identity, let id = identities[identity], let index = records.firstIndex(where: { $0.id == id }),
               let old = records[index].sourceRelativePath,
               !FileManager.default.fileExists(atPath: documentsRoot.appendingPathComponent(old).path) {
                records[index].sourceRelativePath = path; records[index].fileName = url.lastPathComponent; records[index].folderID = parent
                try persist(records[index]); try rewriteDocumentLinks(from: old, to: path); papersByPath[path] = id; continue
            }
            let digest = Self.revision(path)
            let raw = String(digest.prefix(32))
            let identifier = [raw.prefix(8), raw.dropFirst(8).prefix(4), raw.dropFirst(12).prefix(4), raw.dropFirst(16).prefix(4), raw.dropFirst(20)].map(String.init).joined(separator: "-")
            var paper = Paper(id: UUID(uuidString: identifier)!, title: url.deletingPathExtension().lastPathComponent)
            paper.sourceRelativePath = path; paper.fileName = url.lastPathComponent; paper.folderID = parent
            try persist(paper); records.append(paper); papersByPath[path] = paper.id
            if let identity { identities[identity] = paper.id }
        }
        if groups != previousGroups { try saveFolders(groups) }
        try JSONEncoder().encode(identities).write(to: identityURL, options: .atomic)
        return records.filter { paper in
            let url = pdfURL(paper.id)
            return FileManager.default.fileExists(atPath: url.path) || CoordinatedFiles.needsDownload(url)
        }.sorted { $0.importedAt > $1.importedAt }
    }

    public func copyDeviceState(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: deviceDirectory, includingPropertiesForKeys: nil) where file.lastPathComponent != "workspace-files.json" {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: file, to: target) }
        }
        for paper in try papers() {
            let target = destination.appendingPathComponent(paper.id.uuidString + ".conversation.json")
            if !FileManager.default.fileExists(atPath: target.path), let data = try readSidecar(paper.id, name: "conversation.json") { try data.write(to: target, options: .atomic) }
        }
    }
    /// Copy a complete managed library into a selected workspace, retaining all UUIDs and the original.
    /// No databases, WAL files, API keys, or device reading state enter the shared folder.
    public func copyLibrary(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if documentsRoot != nil {
            try CoordinatedFiles.copy(noteURL(sharedNoteID), to: destination.appendingPathComponent("workspace-note.md"))
            let assets = noteDirectory(sharedNoteID).appendingPathComponent("assets")
            if FileManager.default.fileExists(atPath: assets.path) { try CoordinatedFiles.copy(assets, to: destination.appendingPathComponent("workspace-assets")) }
        }
        for paper in try papers() {
            let target = destination.appendingPathComponent(paper.id.uuidString)
            guard !FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            do {
                for name in documentsRoot == nil ? ["note.md", "note.previous.md", "sources.json", "annotations.json", "assets"] : ["sources.json", "annotations.json"] {
                    let source = directory(paper.id).appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: source.path) { try CoordinatedFiles.copy(source, to: target.appendingPathComponent(name)) }
                }
                // Conflict/recovery notes are user data too.
                for file in try FileManager.default.contentsOfDirectory(at: directory(paper.id), includingPropertiesForKeys: nil) where file.lastPathComponent.contains("conflict") {
                    try CoordinatedFiles.copy(file, to: target.appendingPathComponent(file.lastPathComponent))
                }
                try CoordinatedFiles.copy(pdfURL(paper.id), to: target.appendingPathComponent("paper.pdf"))
                var shared = paper; shared.sourceRelativePath = nil; shared.page = 0; shared.scale = 0; shared.readingPoint = nil
                try CoordinatedFiles.write(JSONEncoder().encode(shared), to: target.appendingPathComponent("paper.json"))
            } catch { throw error } // Keep any copied data for recovery; never remove the source library.
        }
        if !FileManager.default.fileExists(atPath: destination.appendingPathComponent("folders.json").path) {
            var groups = try folders()
            for i in groups.indices { groups[i].sourceRelativePath = nil }
            try CoordinatedFiles.write(JSONEncoder().encode(groups), to: destination.appendingPathComponent("folders.json"))
        }
    }
}

extension LibraryStore {
    func sourceFolderPath(_ id: UUID?, groups: inout [LibraryFolder]) throws -> String {
        guard let documentsRoot, let id else { return "" }
        guard let index = groups.firstIndex(where: { $0.id == id }) else { throw LibraryError.invalidPath }
        if let path = groups[index].sourceRelativePath { return path }
        let parent = try sourceFolderPath(groups[index].parentID, groups: &groups)
        let path = parent.isEmpty ? groups[index].name : parent + "/" + groups[index].name
        let url = try Self.containedURL(path, in: documentsRoot)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        groups[index].sourceRelativePath = path
        return path
    }
    func relocateSourceDirectory(_ old: String, to new: String, groups original: [LibraryFolder]) throws {
        guard let documentsRoot else { return }
        guard old != new else { return }
        guard !new.hasPrefix(old + "/") else { throw LibraryError.invalidPath }
        try CoordinatedFiles.move(try Self.containedURL(old, in: documentsRoot), to: Self.containedURL(new, in: documentsRoot))
        func changed(_ path: String) -> String { path == old ? new : new + path.dropFirst(old.count) }
        var groups = original
        for i in groups.indices {
            if let path = groups[i].sourceRelativePath, path == old || path.hasPrefix(old + "/") {
                groups[i].sourceRelativePath = changed(path)
                if path == old { groups[i].name = (new as NSString).lastPathComponent }
            }
        }
        try saveFolders(groups)
        for var paper in try papers() {
            if let path = paper.sourceRelativePath, path.hasPrefix(old + "/") { paper.sourceRelativePath = changed(path); try persist(paper) }
        }
        try rewriteDocumentLinks(from: old, to: new)
    }
}
