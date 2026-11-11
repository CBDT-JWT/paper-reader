import XCTest
import PaperCore

final class ReadingFigureTests: XCTestCase {
    private let bounds = PDFRect(x: 0, y: 0, width: 612, height: 792)

    func testVectorDiagramAndMultilineCaptionAreSkippedWhileBodyAndEquationRemain() {
        let lines: [ReadingLine] = [
            .init(id: 0, text: "A paragraph of research text above the diagram.", rect: .init(x: 40, y: 710, width: 240, height: 10)),
            .init(id: 1, text: "Voltage / mV", rect: .init(x: 65, y: 620, width: 70, height: 8)),
            .init(id: 2, text: "Figure 1: A comparison of two methods.", rect: .init(x: 40, y: 550, width: 240, height: 9)),
            .init(id: 3, text: "The caption continues on a second line.", rect: .init(x: 40, y: 538, width: 210, height: 9)),
            .init(id: 4, text: "The next paragraph remains available for reading.", rect: .init(x: 40, y: 510, width: 240, height: 10)),
            .init(id: 5, text: "E = mc²", rect: .init(x: 100, y: 450, width: 100, height: 20))
        ]
        let graphics: [ReadingGraphic] = [
            .init(rect: .init(x: 40, y: 570, width: 240, height: 120), kind: .form),
            .init(rect: lines[5].rect, kind: .form)
        ]
        let regions = ReadingFigureDetector.regions(graphics: graphics, lines: lines, bounds: bounds)
        let layout = ReadingLayout(bounds: bounds, lines: lines, figureRegions: regions)
        XCTAssertEqual(layout.readingOrder().map(\.id), [0, 4, 5])
        XCTAssertTrue(layout.focused(at: .init(x: 80, y: 625), above: 1, below: 2).isEmpty)
        XCTAssertTrue(layout.focused(at: .init(x: 80, y: 542), above: 1, below: 2).isEmpty)
        XCTAssertEqual(layout.focused(lineID: 0, above: 2, below: 8).map(\.id), [0])
        XCTAssertEqual(layout.focused(lineID: 4, above: 8, below: 0).map(\.id), [4])
    }

    func testRasterAndCaptionAboveItAreExcludedAndWholePageScanIsRetained() {
        let caption = ReadingLine(id: 0, text: "Fig. 2. An experimental image.", rect: .init(x: 40, y: 600, width: 220, height: 10))
        let graphics: [ReadingGraphic] = [
            .init(rect: bounds, kind: .image),
            .init(rect: .init(x: 40, y: 470, width: 240, height: 120), kind: .image)
        ]
        let regions = ReadingFigureDetector.regions(graphics: graphics, lines: [caption], bounds: bounds)
        XCTAssertEqual(regions.count, 1)
        XCTAssertTrue(regions[0].cgRect.contains(caption.rect.cgRect))
        XCTAssertFalse(regions[0].cgRect.contains(CGPoint(x: 50, y: 700)))
    }

    func testFullWidthFigurePreservesTheColumnReadingBands() {
        var lines: [ReadingLine] = []
        for column in 0..<2 { for row in 0..<8 {
            lines.append(.init(id: column * 100 + row, text: "A substantial sentence of actual research paper prose.",
                               rect: .init(x: Double(40 + column * 280), y: Double(720 - row * 15), width: 240, height: 10)))
            lines.append(.init(id: 1000 + column * 100 + row, text: "Another substantial sentence below the spanning diagram.",
                               rect: .init(x: Double(40 + column * 280), y: Double(450 - row * 15), width: 240, height: 10)))
        } }
        let layout = ReadingLayout(bounds: bounds, lines: lines, figureRegions: [.init(x: 40, y: 500, width: 520, height: 100)])
        XCTAssertEqual(layout.columnCount, 2)
        let order = layout.readingOrder().map(\.id)
        XCTAssertLessThan(order.firstIndex(of: 107)!, order.firstIndex(of: 1000)!)
        XCTAssertEqual(layout.focused(lineID: 7, above: 0, below: 8).map(\.id), [7])
    }

    func testAdjacentFiguresUseTheirOwnFollowingCaptions() {
        let lines: [ReadingLine] = [
            .init(id: 0, text: "Figure 5: The first image.", rect: .init(x: 320, y: 625, width: 230, height: 9)),
            .init(id: 1, text: "Figure 6: The second image.", rect: .init(x: 320, y: 497, width: 230, height: 9)),
            .init(id: 2, text: "The next body paragraph remains available in the right column.", rect: .init(x: 314, y: 484, width: 244, height: 8.4))
        ]
        let graphics: [ReadingGraphic] = [
            .init(rect: .init(x: 330, y: 650, width: 210, height: 58), kind: .form),
            .init(rect: .init(x: 333, y: 526, width: 90, height: 89), kind: .image),
            .init(rect: .init(x: 452, y: 526, width: 90, height: 89), kind: .image)
        ]
        let regions = ReadingFigureDetector.regions(graphics: graphics, lines: lines, bounds: bounds)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(ReadingLayout(bounds: bounds, lines: lines, figureRegions: regions).lines.map(\.id), [2])
        XCTAssertTrue(regions.contains { $0.cgRect.contains(CGPoint(x: 370, y: 510)) })
    }

    func testBodyGlyphBoxTouchingFigureEdgeRetainsItsNavigationIdentity() {
        let line = ReadingLine(id: 42, text: "A body line whose font bounds touch the image boundary.", rect: .init(x: 40, y: 598, width: 240, height: 10))
        let layout = ReadingLayout(bounds: bounds, lines: [line], figureRegions: [.init(x: 40, y: 500, width: 240, height: 100)])
        XCTAssertEqual(layout.focused(lineID: 42, above: 0, below: 0).map(\.id), [42])
        XCTAssertNotNil(layout.focusRectangle(lineID: 42, above: 0, below: 0))
    }
}
