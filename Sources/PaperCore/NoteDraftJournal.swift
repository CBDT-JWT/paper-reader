import Foundation

/// Independent of the document actor: a stalled file provider cannot stall local draft recovery.
public actor NoteDraftJournal {
    public struct Draft: Codable, Sendable {
        public let markdown: String
        public let baseRevision: String
    }
    private let root: URL
    private var sequence: [UUID: UInt64] = [:]
    public init(deviceDirectory: URL) { root = deviceDirectory.appendingPathComponent("Drafts", isDirectory: true) }
    private func url(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".json") }
    public func stage(_ id: UUID, markdown: String, baseRevision: String, sequence value: UInt64) throws {
        guard value >= (sequence[id] ?? 0) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(Draft(markdown: markdown, baseRevision: baseRevision)).write(to: url(id), options: .atomic)
        sequence[id] = value
    }
    public func read(_ id: UUID) throws -> Draft? {
        guard FileManager.default.fileExists(atPath: url(id).path) else { return nil }
        return try JSONDecoder().decode(Draft.self, from: Data(contentsOf: url(id)))
    }
    public func clear(_ id: UUID, matching markdown: String) throws {
        guard try read(id)?.markdown == markdown else { return }
        try FileManager.default.removeItem(at: url(id))
    }
    /// Archive both sides before a user resolves an unsaved-draft/file conflict.
    public func archive(_ id: UUID, draft: Draft, current: String) throws -> URL {
        let folder = root.appendingPathComponent("Recovery-" + id.uuidString + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(draft.markdown.utf8).write(to: folder.appendingPathComponent("local-draft.md"), options: .atomic)
        try Data(current.utf8).write(to: folder.appendingPathComponent("file-version.md"), options: .atomic)
        return folder
    }
}
