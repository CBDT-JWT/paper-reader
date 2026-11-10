import XCTest
import CoreGraphics
import ImageIO
import PDFKit
import PaperCore

final class PDFRegionRendererTests: XCTestCase {
    func testCropCoordinatesResolutionAndColorAtEveryRotation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PDFRegionTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("fixture.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(original as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 60, y: 100, width: 80, height: 40))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 170, y: 240, width: 60, height: 60))
        context.endPDFPage(); context.closePDF()
        for rotation in [0, 90, 180, 270] {
            let pdf = try XCTUnwrap(PDFDocument(url: original))
            let page = try XCTUnwrap(pdf.page(at: 0))
            page.rotation = rotation; page.setBounds(CGRect(x: 20, y: 30, width: 260, height: 340), for: .cropBox)
            let rotated = root.appendingPathComponent("rotated-\(rotation).pdf")
            XCTAssertTrue(pdf.write(to: rotated))
            let result = try PDFRegionRenderer.render(url: rotated, page: 0, rect: .init(x: 60, y: 100, width: 80, height: 40), scale: 3)
            XCTAssertEqual(result.pixelWidth, rotation % 180 == 0 ? 240 : 120)
            XCTAssertEqual(result.pixelHeight, rotation % 180 == 0 ? 120 : 240)
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result.png as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            let pixel = try centerPixel(image)
            XCTAssertGreaterThan(pixel[0], 240, "red channel, rotation \(rotation)")
            // Device RGB PDF colors are converted by ColorSync; allow profile variation.
            XCTAssertLessThan(pixel[1], 80, "green channel, rotation \(rotation)")
            XCTAssertLessThan(pixel[2], 80, "blue channel, rotation \(rotation)")
        }
    }
    func testInvalidPageAndOversizedRasterAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PDFBounds-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try DemoPaper.create(at: url)
        XCTAssertThrowsError(try PDFRegionRenderer.render(url: url, page: 999, rect: .init(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertThrowsError(try PDFRegionRenderer.render(url: url, page: 0, rect: .init(x: -100, y: -100, width: 10, height: 10)))
        XCTAssertThrowsError(try PDFRegionRenderer.render(url: url, page: 0, rect: .init(x: 0, y: 0, width: 10, height: 10), scale: 100))
    }
    private func centerPixel(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { bytes[$0] }
    }
}
