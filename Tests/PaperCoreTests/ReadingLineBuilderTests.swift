import XCTest
import PaperCore

final class ReadingLineBuilderTests: XCTestCase {
    func testPhysicalLinesSplitTheGutterAndRejectHiddenVectorMetadata() {
        var glyphs: [ReadingGlyph] = []
        func draw(_ text: String, x: Double, y: Double, height: Double = 10) {
            var cursor = x
            for character in text {
                if character != " " { glyphs.append(.init(text: String(character), rect: .init(x: cursor, y: y, width: 4, height: height))) }
                cursor += character == " " ? 3 : 4
            }
        }
        draw("IEEE heading across the page", x: 160, y: 750, height: 20)
        draw("A physical line in the left column.", x: 36, y: 700)
        draw("A physical line in the right column.", x: 330, y: 700)
        draw("The second line remains separate.", x: 36, y: 684)
        glyphs.append(.init(text: "<latexit hidden metadata>", rect: .init(x: 40, y: 699, width: 0.00001, height: 0.00001)))
        let lines = ReadingLineBuilder.lines(glyphs: glyphs, bounds: .init(x: 0, y: 0, width: 612, height: 792))
        XCTAssertEqual(lines.count, 4)
        XCTAssertFalse(lines.contains { $0.text.contains("latexit") })
        let parallel = lines.filter { $0.rect.y == 700 }
        XCTAssertEqual(parallel.count, 2)
        XCTAssertTrue(parallel[0].rect.x + parallel[0].rect.width < parallel[1].rect.x)
        XCTAssertEqual(lines.filter { $0.rect.y == 684 }.count, 1)
    }
    func testDenseFigureLabelsAndCenteredHeadingsDoNotChangeBodyColumns() {
        var lines: [ReadingLine] = [.init(id: 900, text: "A centered IEEE heading", rect: .init(x: 180, y: 750, width: 240, height: 20))]
        for column in 0..<2 { for row in 0..<14 {
            lines.append(.init(id: column * 100 + row, text: "A substantial sentence of actual research paper prose.", rect: .init(x: Double(36 + column * 294), y: Double(700 - row * 15), width: 246, height: 10)))
        } }
        for index in 0..<180 {
            lines.append(.init(id: 1000 + index, text: "12", rect: .init(x: Double(40 + index % 12 * 19), y: Double(320 + index / 12 * 7), width: 8, height: 6)))
        }
        let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 612, height: 792), lines: lines)
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertLessThan(layout.lines.first { $0.id == 900 }!.column, 0)
        let right = layout.focused(at: .init(x: 350, y: 660), above: 1, below: 2)
        XCTAssertEqual(right.count, 4)
        XCTAssertTrue(right.allSatisfy { $0.column == 1 && $0.rect.x >= 330 })
        XCTAssertEqual(layout.focused(at: .init(x: 300, y: 755), above: 2, below: 2).map(\.id), [900])
    }
    func testHeadingBoxPaddingCannotStealTheAdjacentBodyBaseline() {
        var lines: [ReadingLine] = [.init(id: 900, text: "A spanning title", rect: .init(x: 49, y: 527, width: 510, height: 12.4))]
        for column in 0..<2 { for row in 0..<8 {
            lines.append(.init(id: column * 100 + row, text: "A substantial sentence of actual research paper prose.", rect: .init(x: Double(53 + column * 260), y: 521.4 - Double(row * 12), width: 246, height: 8)))
        } }
        let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 612, height: 792), lines: lines)
        let focused = layout.focused(at: .init(x: 175, y: 525.4), above: 1, below: 2)
        XCTAssertFalse(focused.isEmpty)
        XCTAssertTrue(focused.allSatisfy { $0.column == 0 })
    }

    func testLogicalTextBreaksDoNotFragmentOnePhysicalLine() {
        let glyphs: [ReadingGlyph] = [
            .init(text: "Body", rect: .init(x: 40, y: 700, width: 24, height: 10), sourceLine: 1),
            .init(text: "citation", rect: .init(x: 67, y: 700, width: 35, height: 10), sourceLine: 2),
            .init(text: "continues", rect: .init(x: 105, y: 700, width: 45, height: 10), sourceLine: 3),
            .init(text: "Other column", rect: .init(x: 330, y: 700, width: 100, height: 10), sourceLine: 4)]
        let lines = ReadingLineBuilder.lines(glyphs: glyphs, bounds: .init(x: 0, y: 0, width: 612, height: 792))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Body citation continues")
        XCTAssertLessThan(lines[0].rect.x + lines[0].rect.width, lines[1].rect.x)
    }

}
