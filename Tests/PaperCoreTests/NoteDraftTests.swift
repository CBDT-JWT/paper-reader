import XCTest
import Foundation
import PaperCore

final class NoteDraftTests: XCTestCase, @unchecked Sendable {
    func testDraftOrderingRecoveryAndConditionalClear() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), journal = NoteDraftJournal(deviceDirectory: root)
        try await journal.stage(id, markdown: "latest", baseRevision: "base", sequence: 2)
        try await journal.stage(id, markdown: "stale", baseRevision: "base", sequence: 1)
        try await journal.clear(id, matching: "stale")
        let reopened = NoteDraftJournal(deviceDirectory: root)
        let persisted = try await reopened.read(id)
        let draft = try XCTUnwrap(persisted)
        XCTAssertEqual(draft.markdown, "latest")
        XCTAssertEqual(draft.baseRevision, "base")
        let recovery = try await reopened.archive(id, draft: draft, current: "remote")
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent("local-draft.md"), encoding: .utf8), "latest")
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent("file-version.md"), encoding: .utf8), "remote")
        try await journal.clear(id, matching: "latest")
        let cleared = try await journal.read(id)
        XCTAssertNil(cleared)
    }
}
