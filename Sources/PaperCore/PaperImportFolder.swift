import Foundation

extension LibraryStore {
    public func paperImportFolder(path: String?, fallback: UUID?) throws -> UUID? {
        guard let path else { return fallback }
        if path.isEmpty { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !$0.contains("\\") && !$0.contains(":") && $0.rangeOfCharacter(from: .controlCharacters) == nil }) else { throw LibraryError.invalidPath }
        if let documentsRoot { _ = try Self.containedURL(path, in: documentsRoot) }
        var parent: UUID?
        for part in parts {
            let name = part.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.hasPrefix(".") else { throw LibraryError.invalidPath }
            let siblings = try folders().filter { $0.parentID == parent }
            if let folder = siblings.first(where: { $0.name == part }) ?? siblings.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { parent = folder.id }
            else {
                let folder = LibraryFolder(name: name, parentID: parent)
                try organize(.createFolder(folder)); parent = folder.id
            }
        }
        return parent
    }
}
