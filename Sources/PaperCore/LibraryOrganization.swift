import Foundation

public enum LibrarySort: String, CaseIterable, Sendable {
    case filename, title, recent
    public func ordered(_ papers: [Paper], ascending: Bool = true) -> [Paper] {
        papers.sorted { left, right in
            let comparison: ComparisonResult
            switch self {
            case .filename: comparison = left.displayFileName.localizedStandardCompare(right.displayFileName)
            case .title: comparison = left.title.localizedStandardCompare(right.title)
            case .recent:
                comparison = left.importedAt == right.importedAt ? .orderedSame : left.importedAt > right.importedAt ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame { return left.id.uuidString < right.id.uuidString }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}

public enum LibraryOrganizationChange: Sendable {
    case createFolder(LibraryFolder), renameFolder(UUID, String), moveFolder(UUID, UUID?), removeFolder(UUID)
    case renamePaper(UUID, String), movePaper(UUID, UUID?)
}

public enum LibraryHierarchy {
    public static func descendants(of id: UUID, in folders: [LibraryFolder]) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var queue = [id]
        while let parent = queue.popLast() {
            for child in folders where child.parentID == parent && !result.contains(child.id) {
                result.insert(child.id); queue.append(child.id)
            }
        }
        return result
    }
    public static func ordered(_ folders: [LibraryFolder]) -> [LibraryFolder] {
        folders.sorted { left, right in
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id.uuidString < right.id.uuidString : order == .orderedAscending
        }
    }
}

extension LibraryStore {
    /// Each organization mutation reads the latest manifests inside the actor. A stale UI
    /// snapshot must not revert a rename or move while reading-position writes are pending.
    public func organize(_ change: LibraryOrganizationChange) throws {
        var groups = try folders()
        func checkParent(_ id: UUID?) throws {
            if let id, !groups.contains(where: { $0.id == id }) { throw LibraryError.invalidPath }
        }
        func name(_ value: String) throws -> String {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, ![".", ".."].contains(clean), !clean.contains("/"), !clean.contains(where: { $0.isNewline }) else { throw LibraryError.invalidName }
            return clean
        }
        switch change {
        case .createFolder(var folder):
            folder.name = try name(folder.name); try checkParent(folder.parentID)
            guard !groups.contains(where: { $0.id == folder.id }) else { throw LibraryError.invalidPath }
            groups.append(folder)
            if documentsRoot != nil { _ = try sourceFolderPath(folder.id, groups: &groups) }
            try saveFolders(groups)
        case .renameFolder(let id, let value):
            guard let index = groups.firstIndex(where: { $0.id == id }) else { throw LibraryError.invalidPath }
            let value = try name(value)
            if documentsRoot != nil, let old = groups[index].sourceRelativePath {
                let parent = (old as NSString).deletingLastPathComponent
                try relocateSourceDirectory(old, to: parent.isEmpty ? value : parent + "/" + value, groups: groups)
            } else { groups[index].name = value; try saveFolders(groups) }
        case .moveFolder(let id, let parent):
            try checkParent(parent)
            guard let index = groups.firstIndex(where: { $0.id == id }) else { throw LibraryError.invalidPath }
            guard !LibraryHierarchy.descendants(of: id, in: groups).contains(parent ?? UUID()) else { throw LibraryError.invalidPath }
            if documentsRoot != nil, let old = groups[index].sourceRelativePath {
                let parentPath = try sourceFolderPath(parent, groups: &groups)
                groups[index].parentID = parent
                let new = parentPath.isEmpty ? groups[index].name : parentPath + "/" + groups[index].name
                try relocateSourceDirectory(old, to: new, groups: groups)
            } else { groups[index].parentID = parent; try saveFolders(groups) }
        case .removeFolder(let id):
            guard let group = groups.first(where: { $0.id == id }) else { throw LibraryError.invalidPath }
            if let documentsRoot, let path = group.sourceRelativePath {
                let source = try Self.containedURL(path, in: documentsRoot)
                guard try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).isEmpty else { throw LibraryError.nonEmptyFolder }
                let recovery = root.appendingPathComponent(".RemovedFolders", isDirectory: true)
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                try CoordinatedFiles.move(source, to: recovery.appendingPathComponent(UUID().uuidString))
            }
            for var paper in try papers() where paper.folderID == id { paper.folderID = group.parentID; try persist(paper) }
            for index in groups.indices where groups[index].parentID == id { groups[index].parentID = group.parentID }
            groups.removeAll { $0.id == id }; try saveFolders(groups)
        case .renamePaper(let id, let value):
            var paper = try record(id)
            let value = try name(value)
            paper.fileName = value.lowercased().hasSuffix(".pdf") ? value : value + ".pdf"
            if let documentsRoot, let old = paper.sourceRelativePath {
                let parent = (old as NSString).deletingLastPathComponent
                let new = parent.isEmpty ? paper.displayFileName : parent + "/" + paper.displayFileName
                if old != new { try CoordinatedFiles.move(Self.containedURL(old, in: documentsRoot), to: Self.containedURL(new, in: documentsRoot)) }
                paper.sourceRelativePath = new
                try rewriteDocumentLinks(from: old, to: new)
            }
            paper.title = String(paper.displayFileName.dropLast(4)); try persist(paper)
        case .movePaper(let id, let parent):
            try checkParent(parent)
            var paper = try record(id)
            if let documentsRoot, let old = paper.sourceRelativePath {
                let folder = try sourceFolderPath(parent, groups: &groups)
                let new = folder.isEmpty ? paper.displayFileName : folder + "/" + paper.displayFileName
                if old != new { try CoordinatedFiles.move(Self.containedURL(old, in: documentsRoot), to: Self.containedURL(new, in: documentsRoot)) }
                paper.sourceRelativePath = new; try rewriteDocumentLinks(from: old, to: new); try saveFolders(groups)
            }
            paper.folderID = parent; try persist(paper)
        }
    }
    public func persistMetadata(_ id: UUID, metadata: Bibliography) throws {
        var paper = try record(id); paper.metadata = metadata; try persist(paper)
    }
}
