import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum PDFRegionRenderer {
    public struct Result: Sendable {
        public let png: Data
        public let rect: PDFRect
        public let pixelWidth: Int
        public let pixelHeight: Int
    }
    /// Uses PDF user-space coordinates; handles crop-box origins and intrinsic 90° rotations.
    public static func render(url: URL, page index: Int, rect: PDFRect, scale: Double = 3) throws -> Result {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: index + 1) else { throw LibraryError.invalidPDF }
        let region = rect.cgRect.standardized.intersection(page.getBoxRect(.cropBox))
        guard !region.isNull, region.width >= 1, region.height >= 1, scale >= 1, scale <= 6 else { throw LibraryError.invalidPDF }
        let crop = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle % 180) == 90
        let size = rotated ? CGSize(width: crop.height, height: crop.width) : crop.size
        let transform = page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
        let displayRegion = region.applying(transform)
        let width = Int(ceil(displayRegion.width * scale)), height = Int(ceil(displayRegion.height * scale))
        guard width <= 16000, height <= 16000, width * height <= 40_000_000 else { throw LibraryError.oversizedImage }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LibraryError.oversizedImage }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -displayRegion.minX, y: -displayRegion.minY)
        context.concatenate(transform)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw LibraryError.invalidPDF }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw LibraryError.invalidPDF }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.invalidPDF }
        return Result(png: data as Data, rect: PDFRect(region), pixelWidth: width, pixelHeight: height)
    }
}
