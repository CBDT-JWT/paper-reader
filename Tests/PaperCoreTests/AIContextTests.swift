import XCTest
import Foundation
import PaperCore

final class AIContextTests: XCTestCase {
    func testLegacyMessagesAndQuotedHistoryRoundTrip() throws {
        let legacy = AIMessage(role: "user", content: "Existing question")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "quote")
        let decoded = try JSONDecoder().decode(AIMessage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, legacy)
        XCTAssertNil(decoded.quote)
        let source = SourceReference(paperID: UUID(), page: 4, rect: .init(x: 20, y: 30, width: 100, height: 15), text: "Evidence")
        let quote = AIQuote(text: "Evidence", label: "Paper page 5", source: source, link: source.link)
        let message = AIMessage(role: "user", content: "Explain this.", quote: quote)
        XCTAssertEqual(try JSONDecoder().decode(AIMessage.self, from: JSONEncoder().encode(message)), message)
        XCTAssertTrue(message.contextContent.contains("Evidence"))
        XCTAssertTrue(message.contextContent.contains("Explain this."))
        XCTAssertEqual(message.quote?.source?.page, 4)
    }
}
