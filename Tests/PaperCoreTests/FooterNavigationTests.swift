import XCTest
import PaperCore

final class FooterNavigationTests: XCTestCase {
    func testOverlappingFooterRetainsIdentityAndReachesTheRightColumn() throws {
        var lines: [ReadingLine] = []
        for column in 0..<2 {
            for row in 0..<12 {
                lines.append(.init(id: column * 100 + row, text: "A substantial sentence in the paper's body column.",
                                   rect: .init(x: Double(40 + column * 280), y: Double(700 - row * 18), width: 240, height: 10)))
            }
        }
        lines.append(.init(id: 901, text: "Funding acknowledgement in a smaller footer font.", rect: .init(x: 40, y: 32, width: 220, height: 10)))
        lines.append(.init(id: 900, text: "Footer whose font bounds overlap the preceding line.", rect: .init(x: 40, y: 30, width: 240, height: 20)))
        lines.append(.init(id: 999, text: "12", rect: .init(x: 296, y: 8, width: 20, height: 10)))
        let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 612, height: 792), lines: lines)
        let order = layout.readingOrder()
        let footerIndex = try XCTUnwrap(order.firstIndex { $0.id == 900 })
        XCTAssertEqual(order[footerIndex - 1].id, 901)
        XCTAssertEqual(order[footerIndex + 1].id, 100)
        XCTAssertEqual(layout.focused(at: .init(x: 160, y: 40), above: 0, below: 0).first?.id, 901)
        XCTAssertEqual(layout.focused(lineID: 900, above: 0, below: 0).map(\.id), [900])
        let frame = try XCTUnwrap(layout.focusRectangle(lineID: 900, above: 0, below: 0))
        XCTAssertTrue(frame.cgRect.contains(lines[lines.count - 2].rect.cgRect))
        for line in order {
            XCTAssertEqual(layout.focused(lineID: line.id, above: 0, below: 0).first?.id, line.id)
        }
        XCTAssertEqual(order.last?.id, 999)
    }

    func testSharedPDFTextTagAndNarrowGutterWithCopyrightFooter() {
        var glyphs: [ReadingGlyph] = []
        func draw(_ text: String, x: Double, y: Double, source: Int) {
            for (index, character) in text.enumerated() where character != " " {
                glyphs.append(.init(text: String(character), rect: .init(x: x + Double(index) * 4, y: y, width: 3.5, height: 10), sourceLine: source))
            }
        }
        let body = "A paper sentence with enough letters to identify its column."
        let rightX = 40 + Double(body.count) * 4 + 12
        for row in 0..<12 {
            draw(body, x: 40, y: Double(700 - row * 18), source: row)
            draw(body, x: rightX, y: Double(700 - row * 18), source: row)
        }
        draw("Copyright 2026. All rights reserved.", x: 40, y: 30, source: 100)
        let result = ReadingLineBuilder.lines(glyphs: glyphs, bounds: .init(x: 0, y: 0, width: 612, height: 792))
        let bodyLines = result.filter { $0.rect.y > 100 }
        XCTAssertEqual(bodyLines.count, 24)
        XCTAssertTrue(bodyLines.allSatisfy { $0.rect.cgRect.maxX < rightX || $0.rect.x >= rightX })
        let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 612, height: 792), lines: result)
        XCTAssertEqual(layout.columnCount, 2)
        let order = layout.readingOrder()
        XCTAssertTrue(order.indices.dropLast().contains { order[$0].column == 0 && order[$0 + 1].column == 1 })
    }
}
