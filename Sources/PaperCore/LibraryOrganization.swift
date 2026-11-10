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
            groups.append(folder); try saveFolders(groups)
        case .renameFolder(let id, let value):
            guard let index = groups.firstIndex(where: { $0.id == id }) else { throw LibraryError.invalidPath }
            groups[index].name = try name(value); try saveFolders(groups)
        case .moveFolder(let id, let parent):
            try checkParent(parent)
            guard let index = groups.firstIndex(where: { $0.id == id }) else { throw LibraryError.invalidPath }
            groups[index].parentID = parent; try saveFolders(groups)
        case .removeFolder(let id):
            guard let group = groups.first(where: { $0.id == id }) else { throw LibraryError.invalidPath }
            for var paper in try papers() where paper.folderID == id { paper.folderID = group.parentID; try persist(paper) }
            for index in groups.indices where groups[index].parentID == id { groups[index].parentID = group.parentID }
            groups.removeAll { $0.id == id }; try saveFolders(groups)
        case .renamePaper(let id, let value):
            var paper = try record(id)
            let value = try name(value)
            paper.fileName = value.lowercased().hasSuffix(".pdf") ? value : value + ".pdf"
            paper.title = String(paper.displayFileName.dropLast(4)); try persist(paper)
        case .movePaper(let id, let parent):
            try checkParent(parent)
            var paper = try record(id); paper.folderID = parent; try persist(paper)
        }
    }
    public func persistMetadata(_ id: UUID, metadata: Bibliography) throws {
        var paper = try record(id); paper.metadata = metadata; try persist(paper)
    }
    private func record(_ id: UUID) throws -> Paper {
        try JSONDecoder().decode(Paper.self, from: Data(contentsOf: directory(id).appendingPathComponent("paper.json")))
    }
}
