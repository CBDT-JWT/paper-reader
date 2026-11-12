import Foundation
import Darwin
import PaperCore

/// A process owns one workspace index for its lifetime. Kernel locks release after a crash.
final class WorkspaceAccess: @unchecked Sendable {
    private let descriptor: Int32
    init(indexURL: URL) throws {
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = indexURL.deletingLastPathComponent().appendingPathComponent("workspace.lock")
        let opened = Darwin.open(file.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(opened); throw LibraryError.workspaceInUse }
        descriptor = opened
    }
    deinit { Darwin.close(descriptor) }
}
