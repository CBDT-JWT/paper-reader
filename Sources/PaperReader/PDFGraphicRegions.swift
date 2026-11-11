import CoreGraphics
import PaperCore

/// Reads graphic placement from the content stream, without rendering or OCR.
/// Form bounds cover vector diagrams as well as raster image XObjects.
enum PDFGraphicRegions {
    static func read(page: CGPDFPage) -> [ReadingGraphic] {
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        let context = State(table: table)
        CGPDFOperatorTableSetCallback(table, "q") { _, info in PDFGraphicRegions.state(info).stack.append(PDFGraphicRegions.state(info).transform) }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let value = PDFGraphicRegions.state(info)
            if let saved = value.stack.popLast() { value.transform = saved }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let values = PDFGraphicRegions.numbers(6, scanner) else { return }
            let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            PDFGraphicRegions.state(info).transform = matrix.concatenating(PDFGraphicRegions.state(info).transform)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in PDFGraphicRegions.object(scanner, PDFGraphicRegions.state(info)) }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let values = PDFGraphicRegions.numbers(2, scanner) else { return }
            PDFGraphicRegions.state(info).path.move(to: CGPoint(x: values[0], y: values[1]), transform: PDFGraphicRegions.state(info).transform)
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let values = PDFGraphicRegions.numbers(2, scanner) else { return }
            PDFGraphicRegions.state(info).path.addLine(to: CGPoint(x: values[0], y: values[1]), transform: PDFGraphicRegions.state(info).transform)
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            guard let v = PDFGraphicRegions.numbers(6, scanner) else { return }
            let value = PDFGraphicRegions.state(info)
            value.path.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]), transform: value.transform)
        }
        CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
            guard let v = PDFGraphicRegions.numbers(4, scanner) else { return }
            let value = PDFGraphicRegions.state(info)
            value.path.addCurve(to: CGPoint(x: v[2], y: v[3]).applying(value.transform), control1: value.path.currentPoint,
                                control2: CGPoint(x: v[0], y: v[1]).applying(value.transform))
        }
        CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
            guard let v = PDFGraphicRegions.numbers(4, scanner) else { return }
            let value = PDFGraphicRegions.state(info), end = CGPoint(x: v[2], y: v[3]).applying(PDFGraphicRegions.state(info).transform)
            value.path.addCurve(to: end, control1: CGPoint(x: v[0], y: v[1]).applying(value.transform), control2: end)
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let v = PDFGraphicRegions.numbers(4, scanner) else { return }
            PDFGraphicRegions.state(info).path.addRect(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]), transform: PDFGraphicRegions.state(info).transform)
        }
        CGPDFOperatorTableSetCallback(table, "h") { _, info in PDFGraphicRegions.state(info).path.closeSubpath() }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in PDFGraphicRegions.state(info).path = CGMutablePath() }
        for name in ["S", "s", "f", "F", "f*", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                let value = PDFGraphicRegions.state(info)
                value.append(value.path.boundingBoxOfPath.insetBy(dx: -0.5, dy: -0.5), kind: .path)
                value.path = CGMutablePath()
            }
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        scan(stream, context)
        return context.regions
    }

    private final class State {
        let table: CGPDFOperatorTableRef
        var transform = CGAffineTransform.identity
        var stack: [CGAffineTransform] = []
        var path = CGMutablePath()
        var depth = 0
        var forms = 0
        var regions: [ReadingGraphic] = []
        init(table: CGPDFOperatorTableRef) { self.table = table }
        func append(_ rect: CGRect, kind: ReadingGraphic.Kind) {
            guard regions.count < 20_000, !rect.isNull, rect.width.isFinite, rect.height.isFinite,
                  rect.width > 0, rect.height > 0 else { return }
            regions.append(.init(rect: PDFRect(rect.standardized), kind: kind))
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func numbers(_ count: Int, _ scanner: CGPDFScannerRef) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for index in values.indices.reversed() {
            guard CGPDFScannerPopNumber(scanner, &values[index]) else { return nil }
        }
        return values
    }

    private static func scan(_ stream: CGPDFContentStreamRef, _ value: State) {
        let scanner = CGPDFScannerCreate(stream, value.table, Unmanaged.passUnretained(value).toOpaque())
        CGPDFScannerScan(scanner)
    }

    private static func object(_ scanner: CGPDFScannerRef, _ value: State) {
        var name: UnsafePointer<CChar>?
        guard value.depth < 12, value.forms < 2_048, CGPDFScannerPopName(scanner, &name), let name,
              let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name) else { return }
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(resource, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream) else { return }
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
        if String(cString: subtype) == "Image" {
            value.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(value.transform), kind: .image)
        } else if String(cString: subtype) == "Form" {
            value.forms += 1
            var bbox: CGPDFArrayRef?, matrix: CGPDFArrayRef?, resources: CGPDFDictionaryRef?
            CGPDFDictionaryGetArray(dictionary, "BBox", &bbox)
            CGPDFDictionaryGetArray(dictionary, "Matrix", &matrix)
            CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
            let saved = value.transform, savedStack = value.stack, savedPath = value.path
            defer { value.transform = saved; value.stack = savedStack; value.path = savedPath; value.depth -= 1 }
            value.depth += 1
            if let matrix, CGPDFArrayGetCount(matrix) == 6 {
                var v = [CGFloat](repeating: 0, count: 6)
                for index in v.indices { CGPDFArrayGetNumber(matrix, index, &v[index]) }
                value.transform = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(saved)
            }
            if let bbox, CGPDFArrayGetCount(bbox) == 4 {
                var v = [CGFloat](repeating: 0, count: 4)
                for index in v.indices { CGPDFArrayGetNumber(bbox, index, &v[index]) }
                value.append(CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]).applying(value.transform), kind: .form)
            }
            value.path = CGMutablePath()
            // Missing resource categories fall back to the parent content stream.
            scan(CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, CGPDFScannerGetContentStream(scanner)), value)
        }
    }
}
