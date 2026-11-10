import XCTest
import PaperCore

final class ResearchFeatureTests: XCTestCase, @unchecked Sendable {
    func testColumnsNeverIlluminateTheParallelColumn() {
        for count in [2, 3] {
            var lines: [ReadingLine] = [.init(id: 999, text: "Spanning title", rect: .init(x: 30, y: 760, width: 540, height: 24))]
            for column in 0..<count { for index in 0..<10 {
                lines.append(.init(id: column * 100 + index, text: "Body", rect: .init(x: Double(30 + column * (540/count + 10)), y: Double(700-index*18), width: Double(540/count-15), height: 12)))
            } }
            let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 612, height: 792), lines: lines)
            XCTAssertEqual(layout.columnCount, count)
            let focused = layout.focused(at: .init(x: 70, y: 666), above: 1, below: 2)
            XCTAssertEqual(focused.count, 4)
            XCTAssertTrue(focused.allSatisfy { $0.column == 0 && $0.rect.x + $0.rect.width < 310 })
            let title = layout.focused(at: .init(x: 300, y: 770), above: 1, below: 2)
            XCTAssertEqual(title.map(\.id), [999])
        }
    }
    func testKeyboardReadingOrderCrossesColumnsWithoutMixingFocusWindows() {
        let lines: [ReadingLine] = [
            .init(id: 90, text: "Title", rect: .init(x: 30, y: 760, width: 540, height: 20)),
            .init(id: 1, text: "Left first", rect: .init(x: 30, y: 700, width: 220, height: 12)),
            .init(id: 2, text: "Left last", rect: .init(x: 30, y: 680, width: 220, height: 12)),
            .init(id: 3, text: "Right first", rect: .init(x: 330, y: 700, width: 220, height: 12)),
            .init(id: 4, text: "Right last", rect: .init(x: 330, y: 680, width: 220, height: 12)),
            .init(id: 91, text: "Spanning equation", rect: .init(x: 30, y: 600, width: 540, height: 20)),
            .init(id: 5, text: "Left lower", rect: .init(x: 30, y: 550, width: 220, height: 12)),
            .init(id: 6, text: "Left lower end", rect: .init(x: 30, y: 530, width: 220, height: 12)),
            .init(id: 7, text: "Right lower", rect: .init(x: 330, y: 550, width: 220, height: 12)),
            .init(id: 8, text: "Right lower end", rect: .init(x: 330, y: 530, width: 220, height: 12))]
        let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 600, height: 800), lines: lines)
        XCTAssertEqual(layout.readingOrder().map(\.id), [90,1,2,3,4,91,5,6,7,8])
        XCTAssertEqual(layout.focused(at: .init(x: 350, y: 705), above: 2, below: 2).map(\.id), [3,4])
        XCTAssertEqual(layout.focused(at: .init(x: 300, y: 607), above: 2, below: 2).map(\.id), [91])
    }
    func testManualColumnClipsSpanningLinesAndScanFallsBackSafely() {
        let layout = ReadingLayout(bounds: .init(x: 0, y: 0, width: 600, height: 800), lines: [.init(id: 1, text: "Merged PDFKit line", rect: .init(x: 30, y: 700, width: 540, height: 12))])
        let focused = layout.focused(at: .init(x: 60, y: 705), above: 3, below: 3, manualColumn: 0)
        XCTAssertEqual(focused.first?.rect.x, 30); XCTAssertEqual(focused.first?.rect.width, 270)
        XCTAssertTrue(ReadingLayout(bounds: layout.bounds, lines: []).focused(at: .init(x: 0, y: 0), above: 1, below: 1).isEmpty)
    }
    func testFoldersTrashRestoreAndReadingUpdatesDoNotOverwriteMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReaderResearch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.pdf"); try DemoPaper.create(at: url)
        let store = try LibraryStore(root: root.appendingPathComponent("Library"))
        let folder = LibraryFolder(name: "Methods"), child = LibraryFolder(name: "Subfolder")
        try await store.saveFolders([folder, child]); let folders = try await store.folders(); XCTAssertEqual(folders.count, 2)
        var cycleA = folder, cycleB = child; cycleA.parentID = child.id; cycleB.parentID = folder.id
        do { try await store.saveFolders([cycleA,cycleB]); XCTFail("Cycle must be rejected") } catch LibraryError.invalidPath {}
        var paper = try await store.importPDF(from: url); paper.title = "Renamed"; paper.folderID = folder.id; paper.metadata = Bibliography(title: "Actual title", doi: "10.1000/test")
        try await store.persist(paper)
        try await store.persistReading(paper.id, page: 2, scale: 1.3, point: .init(x: 40, y: 440))
        let updated = try await store.papers(); XCTAssertEqual(updated[0].title, "Renamed"); XCTAssertEqual(updated[0].metadata, paper.metadata); XCTAssertEqual(updated[0].readingPoint?.y, 440)
        let record = PaperAnnotation(page: 0, kind: .ink, rect: .init(x: 30, y: 40, width: 80, height: 90), points: [.init(x: 30, y: 40), .init(x: 50, y: 60)])
        try await store.saveAnnotations(paper.id, records: [record]); let annotations = try await store.annotations(paper.id); XCTAssertEqual(annotations, [record])
        try await store.trash(paper.id); let empty = try await store.papers(); XCTAssertTrue(empty.isEmpty)
        let trash = try await store.trashedPapers(); XCTAssertEqual(trash.first?.id, paper.id)
        let restored = try await store.restore(paper.id); XCTAssertEqual(restored.id, paper.id)
        let restoredAnnotations = try await store.annotations(paper.id); XCTAssertEqual(restoredAnnotations, [record]); await store.close()
    }
    func testCrossrefDecodingAndCitationFormatsUseRealFields() throws {
        let data = Data(#"{"message":{"title":["Evidence & understanding"],"author":[{"given":"Ada","family":"Lovelace"}],"published":{"date-parts":[[2024,3]]},"container-title":["Research Journal"],"DOI":"10.1234/test","type":"journal-article","volume":"12","issue":"2","page":"10-18","abstract":"<jats:p>Real abstract.</jats:p>"}}"#.utf8)
        let record = try MetadataService.decodeCrossref(data)
        XCTAssertEqual(record.authors, ["Lovelace, Ada"]); XCTAssertEqual(record.year, 2024); XCTAssertEqual(record.abstract, "Real abstract.")
        for style in Bibliography.Style.allCases { let citation = record.citation(style); XCTAssertTrue(citation.contains("10.1234/test")); XCTAssertTrue(citation.contains("2024")) }
        XCTAssertTrue(record.citation(.bibtex).contains("Evidence \\& understanding"))
        XCTAssertEqual(MetadataService.doi(in: "doi: 10.1038/nature14539."), "10.1038/nature14539")
        let original = #"{"title":"π","nested":[true,1,null]}"#
        let value = try JSONValue.parse(original); XCTAssertEqual(value["title"].string, "π"); XCTAssertEqual(try JSONValue.parse(value.text), value)
    }
    func testArxivMetadataAndAuthorFormatting() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Feed title must not be used</title><entry><id>http://arxiv.org/abs/1706.03762v1</id><title>Attention Is All You Need</title><published>2017-06-12T00:00:00Z</published><summary>Verified abstract</summary><author><name>Ashish Vaswani</name></author></entry></feed>
        """
        let metadata = try MetadataService.decodeArxiv(Data(xml.utf8))
        XCTAssertEqual(metadata.arxivID, "1706.03762v1"); XCTAssertEqual(metadata.year, 2017)
        XCTAssertEqual(metadata.authors, ["Vaswani, Ashish"])
        XCTAssertTrue(metadata.citation(.apa).contains("Vaswani, A."))
        XCTAssertTrue(metadata.citation(.ieee).contains("A. Vaswani"))
        XCTAssertTrue(metadata.citation(.bibtex).contains("archivePrefix = {arXiv}"))
        XCTAssertEqual(MetadataService.arxivID(in: "arXiv:1706.03762v2 [cs.CL]"), "1706.03762v2")
        XCTAssertEqual(MetadataService.arxivID(in: "https://arxiv.org/abs/hep-th/9901001"), "hep-th/9901001")
    }
    func testLegacyPaperManifestDecodesWithoutLosingIdentity() throws {
        let id = UUID(); let data = Data("{\"id\":\"\(id)\",\"title\":\"Old paper\",\"importedAt\":0,\"page\":1,\"scale\":1}".utf8)
        let paper = try JSONDecoder().decode(Paper.self, from: data); XCTAssertEqual(paper.id, id); XCTAssertNil(paper.folderID); XCTAssertNil(paper.metadata)
    }
}
