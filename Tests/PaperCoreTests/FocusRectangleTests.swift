import XCTest
import PaperCore

final class FocusRectangleTests: XCTestCase {
    private func layout() -> ReadingLayout {
        var lines: [ReadingLine] = []
        for column in 0..<2 {
            for row in 0..<12 {
                lines.append(ReadingLine(id: column * 100 + row, text: "A research sentence long enough to identify its column.",
                                         rect: PDFRect(x: Double(40 + column * 280), y: Double(700 - row * 18), width: row == 5 ? 160 : 240, height: 11)))
            }
        }
        lines.append(ReadingLine(id: 999, text: "A spanning title", rect: PDFRect(x: 40, y: 750, width: 520, height: 20)))
        return ReadingLayout(bounds: PDFRect(x: 0, y: 0, width: 612, height: 792), lines: lines)
    }

    func testRectangleContainsAllContextAndInterlineWhitespaceWithoutTheOtherColumn() throws {
        let layout = layout(), point = PDFPoint(x: 70, y: 613)
        let selected = layout.focused(at: point, above: 1, below: 2)
        let frame = try XCTUnwrap(layout.focusRectangle(at: point, above: 1, below: 2)).cgRect
        XCTAssertEqual(selected.count, 4)
        XCTAssertTrue(selected.allSatisfy { frame.contains($0.rect.cgRect) })
        XCTAssertLessThan(frame.maxX, 320)
        XCTAssertGreaterThan(frame.height, selected.map(\.rect.height).reduce(0, +))
        let right = try XCTUnwrap(layout.focusRectangle(at: PDFPoint(x: 340, y: 613), above: 2, below: 2)).cgRect
        XCTAssertGreaterThan(right.minX, frame.maxX)
    }

    func testSpanningTitleAndManualColumnClipHaveIndependentRectangles() throws {
        let layout = layout()
        let title = try XCTUnwrap(layout.focusRectangle(at: PDFPoint(x: 300, y: 760), above: 10, below: 10)).cgRect
        XCTAssertGreaterThan(title.width, 500)
        XCTAssertGreaterThan(title.minY, 700)
        let manual = try XCTUnwrap(layout.focusRectangle(at: PDFPoint(x: 310, y: 760), above: 2, below: 2, manualColumn: 1, manualCount: 2)).cgRect
        XCTAssertGreaterThanOrEqual(manual.minX, 306)
        XCTAssertLessThanOrEqual(manual.maxX, 612)
    }

    func testColumnReadingOrderConnectsLeftBottomToRightTopAndReverses() throws {
        let layout = layout(), order = layout.readingOrder()
        let leftBottom = try XCTUnwrap(order.firstIndex { $0.id == 11 })
        XCTAssertEqual(order[leftBottom + 1].id, 100)
        XCTAssertGreaterThan(order[leftBottom + 1].rect.y, order[leftBottom].rect.y)
        XCTAssertEqual(order[leftBottom].id, 11)
    }
}
