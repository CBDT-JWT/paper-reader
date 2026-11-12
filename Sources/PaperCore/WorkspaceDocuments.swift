import Foundation

extension LibraryStore {
    public nonisolated var hasSharedNote: Bool { documentsRoot != nil }
    public nonisolated var sharedNoteID: UUID { UUID(uuidString: "F0BA2819-29BE-49F2-8828-AF821F527280")! }
    public nonisolated func noteIdentity(_ paperID: UUID) -> UUID { hasSharedNote ? sharedNoteID : paperID }
    public nonisolated func noteDirectory(_ id: UUID) -> URL { documentsRoot ?? directory(id) }

    /// File ownership stays with the chosen directory. The local index remembers its note name.
    func prepareWorkspaceDocuments() throws {
        guard let documentsRoot else { return }
        try migrateLegacyWorkspace()
        let configuration = deviceDirectory.appendingPathComponent("workspace-note.json")
        let files = try FileManager.default.contentsOfDirectory(at: documentsRoot, includingPropertiesForKeys: [.isRegularFileKey, .fileResourceIdentifierKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "md" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let existing = try CoordinatedFiles.readOptional(configuration)
        var selection: WorkspaceNoteSelection
        if let existing {
            selection = try JSONDecoder().decode(WorkspaceNoteSelection.self, from: existing)
            var url = try Self.containedURL(selection.name, in: documentsRoot)
            if !FileManager.default.fileExists(atPath: url.path), !CoordinatedFiles.needsDownload(url) {
                // External rename keeps the chosen note. Missing files stay missing until resolved.
                let renamed = files.first { candidate in
                    let identity = try? candidate.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier.map { String(describing: $0) }
                    return identity != nil && identity == selection.identity
                }
                if let renamed { url = renamed; selection.name = url.lastPathComponent }
            }
            let selectedURL = url
            sharedNotePath.withLock { $0 = selectedURL }
        } else {
            let conventional = documentsRoot.appendingPathComponent("notes.md")
            let selected = FileManager.default.fileExists(atPath: conventional.path) ? conventional : files.count == 1 ? files[0] : conventional
            let url = try Self.containedURL(selected.lastPathComponent, in: documentsRoot)
            try CoordinatedFiles.update(url) { $0 ?? Data() }
            selection = WorkspaceNoteSelection(name: url.lastPathComponent, identity: nil)
            sharedNotePath.withLock { $0 = url }
        }
        let note = noteURL(sharedNoteID)
        if let identity = try? note.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier {
            selection.identity = String(describing: identity)
        }
        try CoordinatedFiles.write(JSONEncoder().encode(selection), to: configuration)
        let stagedNote = root.appendingPathComponent("workspace-note.md")
        if let bytes = try CoordinatedFiles.readOptional(stagedNote) {
            let stagedAssets = root.appendingPathComponent("workspace-assets")
            if FileManager.default.fileExists(atPath: stagedAssets.path) {
                try CoordinatedFiles.move(stagedAssets, to: documentsRoot.appendingPathComponent("assets"))
            }
            try CoordinatedFiles.update(note) { previous in
                if previous == nil || previous?.isEmpty == true || previous == bytes { return bytes }
                throw LibraryError.externalChange
            }
            try CoordinatedFiles.move(stagedNote, to: root.appendingPathComponent("copied-workspace-note.md"))
        }
        for var paper in try papers() {
            if paper.sourceRelativePath == nil {
                var groups = try folders()
                let folder = try sourceFolderPath(paper.folderID, groups: &groups)
                try saveFolders(groups)
                let parent = folder.isEmpty ? documentsRoot : try Self.containedURL(folder, in: documentsRoot)
                let plan = directory(paper.id).appendingPathComponent("pdf-migration.json")
                let destination: URL
                if let data = try CoordinatedFiles.readOptional(plan) {
                    destination = try Self.containedURL(JSONDecoder().decode(String.self, from: data), in: documentsRoot)
                } else {
                    var candidate = parent.appendingPathComponent(paper.displayFileName)
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        candidate = parent.appendingPathComponent(candidate.deletingPathExtension().lastPathComponent + "-" + paper.id.uuidString + ".pdf")
                    }
                    destination = candidate
                    try CoordinatedFiles.write(JSONEncoder().encode(String(candidate.path.dropFirst(documentsRoot.path.count + 1))), to: plan)
                }
                let old = directory(paper.id).appendingPathComponent("paper.pdf")
                if FileManager.default.fileExists(atPath: old.path) { try CoordinatedFiles.move(old, to: destination) }
                guard FileManager.default.fileExists(atPath: destination.path) else { throw LibraryError.missingPaper }
                paper.sourceRelativePath = String(destination.path.dropFirst(documentsRoot.path.count + 1))
                paper.fileName = destination.lastPathComponent
                try persist(paper)
            }
            try migratePaperNote(paper)
        }
        try consolidateSourceRecords()
        try repairLegacyPageLinks()
    }

    private func migrateLegacyWorkspace() throws {
        guard let documentsRoot else { return }
        let legacy = documentsRoot.appendingPathComponent(".paper-reader", isDirectory: true)
        guard legacy.standardizedFileURL != root.standardizedFileURL,
              FileManager.default.fileExists(atPath: legacy.path) else { return }
        for source in try FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            if UUID(uuidString: source.lastPathComponent) != nil {
                let manifest = source.appendingPathComponent("paper.json")
                if CoordinatedFiles.needsDownload(manifest) { throw LibraryError.workspaceDownloading }
                let paper = try JSONDecoder().decode(Paper.self, from: CoordinatedFiles.read(manifest))
                guard paper.id.uuidString == source.lastPathComponent else { throw LibraryError.invalidWorkspace }
                let destination = directory(paper.id)
                if !FileManager.default.fileExists(atPath: destination.path) { try CoordinatedFiles.move(source, to: destination) }
            } else if ["folders.json", "workspace.json"].contains(source.lastPathComponent) {
                let destination = root.appendingPathComponent(source.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destination.path) { try CoordinatedFiles.move(source, to: destination) }
            }
        }
        // Empty legacy containers can disappear. Recovery folders and unknown files stay accessible.
        if try FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil).isEmpty { try FileManager.default.removeItem(at: legacy) }
    }

    private func migratePaperNote(_ paper: Paper) throws {
        let folder = directory(paper.id)
        let oldNote = folder.appendingPathComponent("note.md")
        guard let bytes = try CoordinatedFiles.readOptional(oldNote) else { return }
        guard var markdown = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let prefix = "assets/" + paper.id.uuidString + "/"
        let oldAssets = folder.appendingPathComponent("assets")
        let targetAssets = try Self.containedURL(String(prefix.dropLast()), in: documentsRoot!)
        if FileManager.default.fileExists(atPath: oldAssets.path) {
            try FileManager.default.createDirectory(at: targetAssets.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: targetAssets.path) { try CoordinatedFiles.move(oldAssets, to: targetAssets) }
        }
        markdown = markdown.replacingOccurrences(of: "](assets/", with: "](" + prefix)
            .replacingOccurrences(of: "](<assets/", with: "](<" + prefix)
        markdown = try anchoringPageLinks(markdown, to: paper.id)
        let references = try sourcesForPaper(paper.id)
        var updated: [SourceReference] = []
        for reference in references {
            let asset = reference.asset.map { $0.hasPrefix("assets/") && !$0.hasPrefix(prefix) ? prefix + $0.dropFirst(7) : $0 }
            let migrated = SourceReference(id: reference.id, paperID: reference.paperID, page: reference.page, rect: reference.rect, asset: asset, text: reference.text)
            markdown = markdown.replacingOccurrences(of: reference.link, with: sourceLink(migrated))
            updated.append(migrated)
        }
        if updated != references { try CoordinatedFiles.write(JSONEncoder().encode(updated), to: folder.appendingPathComponent("sources.json")) }
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines) != "# " + paper.title,
           !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let marker = sourceLink(SourceReference(paperID: paper.id, page: 0, rect: .init(x: 0, y: 0, width: 1, height: 1))) + "&note=" + paper.id.uuidString
            let escapedTitle = paper.title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            let contribution = "\n\n## " + escapedTitle + "\n\n[PDF](" + marker + ")\n\n" + markdown + "\n"
            try CoordinatedFiles.update(noteURL(paper.id)) { previous in
                guard var text = String(data: previous ?? Data(), encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                if !text.contains("note=" + paper.id.uuidString) { text += contribution }
                return Data(text.utf8)
            }
        }
        let archive = folder.appendingPathComponent("migrated-note.md")
        if !FileManager.default.fileExists(atPath: archive.path) { try CoordinatedFiles.move(oldNote, to: archive) }
    }

    private func consolidateSourceRecords() throws {
        let records = try papers().sorted { $0.importedAt < $1.importedAt }
        var canonicalByPath: [String: UUID] = [:]
        for paper in records {
            guard let path = paper.sourceRelativePath else { continue }
            if let canonical = canonicalByPath[path] {
                let duplicateAnnotations = directory(paper.id).appendingPathComponent("annotations.json")
                if let data = try CoordinatedFiles.readOptional(duplicateAnnotations) {
                    let incoming = try JSONDecoder().decode([PaperAnnotation].self, from: data)
                    let destination = directory(canonical).appendingPathComponent("annotations.json")
                    try CoordinatedFiles.update(destination) { current in
                        var combined = try current.map { try JSONDecoder().decode([PaperAnnotation].self, from: $0) } ?? []
                        let known = Set(combined.map(\.id))
                        combined += incoming.filter { !known.contains($0.id) }
                        return try JSONEncoder().encode(combined)
                    }
                }
                let recovery = root.appendingPathComponent("Recovered Legacy Records", isDirectory: true)
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                try CoordinatedFiles.move(directory(paper.id), to: recovery.appendingPathComponent(paper.id.uuidString))
                try unindex(paper.id)
            } else { canonicalByPath[path] = paper.id }
        }
    }

    public func sourceLink(_ reference: SourceReference) -> String {
        guard documentsRoot != nil, let path = sourcePaths.withLock({ $0[reference.paperID] }) else { return reference.link }
        var link = URLComponents()
        link.scheme = "paperreader"; link.host = "document"
        link.queryItems = [URLQueryItem(name: "file", value: path), URLQueryItem(name: "paper", value: reference.paperID.uuidString), URLQueryItem(name: "page", value: String(reference.page)),
                           URLQueryItem(name: "x", value: String(reference.rect.x)), URLQueryItem(name: "y", value: String(reference.rect.y)),
                           URLQueryItem(name: "w", value: String(reference.rect.width)), URLQueryItem(name: "h", value: String(reference.rect.height))]
        link.percentEncodedQuery = link.percentEncodedQuery?.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        return link.string ?? reference.link
    }
    /// Page-only AI citations need the originating paper once notes are shared.
    public func anchoringPageLinks(_ markdown: String, to paperID: UUID) throws -> String {
        guard hasSharedNote else { return markdown }
        let reference = SourceReference(paperID: paperID, page: 0, rect: .init(x: 0, y: 0, width: 1, height: 1))
        guard let base = URLComponents(string: sourceLink(reference)), base.host == "document" else { return markdown }
        return try Self.anchoringPageLinks(markdown, base: base)
    }

    private static func anchoringPageLinks(_ markdown: String, base: URLComponents) throws -> String {
        let expression = try NSRegularExpression(pattern: #"(?<=\]\()paperreader://page/([1-9][0-9]*)(?=\))"#)
        var text = markdown
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text), let numberRange = Range(match.range(at: 1), in: text),
                  let number = Int(text[numberRange]) else { continue }
            var link = base
            var items = (link.queryItems ?? []).filter { !["page", "x", "y", "w", "h", "note"].contains($0.name) }
            items.append(URLQueryItem(name: "page", value: String(number - 1)))
            link.queryItems = items
            link.percentEncodedQuery = link.percentEncodedQuery?.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
            if let replacement = link.string { text.replaceSubrange(range, with: replacement) }
        }
        return text
    }

    private func repairLegacyPageLinks() throws {
        let completed = deviceDirectory.appendingPathComponent("page-links-v1.json")
        guard !FileManager.default.fileExists(atPath: completed.path),
              let initial = try CoordinatedFiles.readOptional(noteURL(sharedNoteID)) else { return }
        if initial.range(of: Data("paperreader://page/".utf8)) != nil {
            let markers = try NSRegularExpression(pattern: #"(?m)^\[PDF\]\((paperreader://document\?[^)\r\n]+)\)$"#)
            try CoordinatedFiles.update(noteURL(sharedNoteID)) { bytes in
                guard let bytes, var text = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                let matches = markers.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for index in matches.indices.reversed() {
                    let match = matches[index]
                    guard let markerRange = Range(match.range(at: 1), in: text),
                          let base = URLComponents(string: String(text[markerRange])),
                          let items = base.queryItems,
                          let paper = items.first(where: { $0.name == "paper" })?.value,
                          UUID(uuidString: paper) != nil,
                          items.first(where: { $0.name == "note" })?.value == paper,
                          let path = items.first(where: { $0.name == "file" })?.value else { continue }
                    _ = try Self.containedURL(path, in: documentsRoot!)
                    let start = match.range.location + match.range.length
                    let end = index + 1 < matches.count ? matches[index + 1].range.location : (text as NSString).length
                    guard let range = Range(NSRange(location: start, length: end - start), in: text) else { continue }
                    let anchored = try Self.anchoringPageLinks(String(text[range]), base: base)
                    text.replaceSubrange(range, with: anchored)
                }
                let updated = Data(text.utf8)
                if updated != bytes {
                    let recovery = deviceDirectory.appendingPathComponent("legacy-page-links.previous.md")
                    if !FileManager.default.fileExists(atPath: recovery.path) { try CoordinatedFiles.write(bytes, to: recovery) }
                }
                return updated
            }
        }
        try CoordinatedFiles.write(Data("true".utf8), to: completed)
    }

    func sourcesForPaper(_ id: UUID) throws -> [SourceReference] {
        guard let data = try CoordinatedFiles.readOptional(directory(id).appendingPathComponent("sources.json")) else { return [] }
        return try JSONDecoder().decode([SourceReference].self, from: data)
    }
}

private struct WorkspaceNoteSelection: Codable {
    var name: String
    var identity: String?
}

extension LibraryStore {
    /// Update portable references after a real file/folder move while retaining surrounding Markdown.
    func rewriteDocumentLinks(from old: String, to new: String) throws {
        guard documentsRoot != nil else { return }
        let expression = try NSRegularExpression(pattern: #"paperreader://document\?[^\s)<>]+"#)
        try CoordinatedFiles.update(noteURL(sharedNoteID)) { bytes in
            guard let bytes, var text = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text), var link = URLComponents(string: String(text[range])),
                      var items = link.queryItems, let index = items.firstIndex(where: { $0.name == "file" }),
                      let path = items[index].value, path == old || path.hasPrefix(old + "/") else { continue }
                items[index].value = path == old ? new : new + path.dropFirst(old.count)
                link.queryItems = items
                link.percentEncodedQuery = link.percentEncodedQuery?.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                if let replacement = link.string { text.replaceSubrange(range, with: replacement) }
            }
            return Data(text.utf8)
        }
    }
}
