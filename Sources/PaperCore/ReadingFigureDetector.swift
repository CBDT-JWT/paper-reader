import Foundation

public struct ReadingGraphic: Sendable {
    public enum Kind: Sendable { case image, form, path }
    public let rect: PDFRect
    public let kind: Kind
    public init(rect: PDFRect, kind: Kind) { self.rect = rect; self.kind = kind }
}

/// Graphics provide the boundary. Nearby figure captions distinguish vector diagrams
/// from display equations, table rules, page decorations and whole-page PDF forms.
public enum ReadingFigureDetector {
    public static func regions(graphics: [ReadingGraphic], lines: [ReadingLine], bounds: PDFRect) -> [PDFRect] {
        let captions = lines.filter { isCaption($0.text) }
        let heights = lines.filter { $0.text.filter(\.isLetter).count > 30 }.map(\.rect.height).sorted()
        let bodyHeight = heights.isEmpty ? 10 : heights[heights.count / 2]
        let proseLines = lines.filter { !isCaption($0.text) && $0.text.filter(\.isLetter).count > 35 && $0.rect.height >= bodyHeight * 0.85 }
        var result: [CGRect] = []
        for graphic in graphics.sorted(by: { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }) {
            var region = graphic.rect.cgRect.intersection(bounds.cgRect)
            guard !region.isNull, region.width >= 28, region.height >= 18,
                  region.width * region.height < bounds.width * bounds.height * 0.75 else { continue }
            if result.contains(where: { $0.contains(region) }) { continue }
            let nearby = captions.filter { line in
                let rect = line.rect.cgRect
                let overlap = max(0, min(rect.maxX, region.maxX) - max(rect.minX, region.minX))
                let below = region.minY - rect.maxY, above = rect.minY - region.maxY
                return overlap > min(rect.width, region.width) * 0.35 &&
                    ((below >= -12 && below < 48) || (above >= -12 && above < 32))
            }
            let below = nearby.filter { $0.rect.cgRect.midY < region.midY }
            let caption = (below.isEmpty ? nearby : below).min { verticalDistance($0.rect.cgRect, region) < verticalDistance($1.rect.cgRect, region) }
            if graphic.kind != .image {
                guard let caption else { continue }
                // A form can wrap an entire page or a paragraph. Body prose between
                // the graphic and caption also prevents associating an unrelated formula.
                let prose = proseLines.filter { line in
                    let rect = line.rect.cgRect
                    return line.id != caption.id && rect.width > min(100, region.width * 0.55) &&
                        rect.midX > region.minX && rect.midX < region.maxX &&
                        rect.midY > min(caption.rect.y, region.minY) && rect.midY < max(caption.rect.cgRect.maxY, region.maxY)
                }
                guard prose.count < 3 else { continue }
            }
            if let caption {
                region = captionBlock(start: caption, lines: lines).reduce(region) { $0.union($1.rect.cgRect) }
            }
            guard region.height >= 18 else { continue }
            if result.contains(where: { $0.contains(region) }) { continue }
            while let index = result.firstIndex(where: { $0.intersects(region) }) { region = region.union(result.remove(at: index)) }
            result.append(region)
        }
        return result.map(PDFRect.init)
    }

    private static func isCaption(_ text: String) -> Bool {
        text.range(of: #"\b(?:Figure|Fig\.?)[\s\u00a0]*\d+[\s\u00a0]*[:：.]|^(?:Figure|Fig\.?)\s*\d+\b|\u56fe\s*\d+\s*[:：.]"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func verticalDistance(_ a: CGRect, _ b: CGRect) -> Double {
        max(a.minY - b.maxY, b.minY - a.maxY, 0)
    }

    private static func captionBlock(start: ReadingLine, lines: [ReadingLine]) -> [ReadingLine] {
        var block = [start], previous = start
        while block.count < 20 {
            let candidates = lines.filter { line in
                line.rect.y < previous.rect.y - 1 && abs(line.rect.x - start.rect.x) < max(3, start.rect.height * 0.4)
            }
            guard let next = candidates.max(by: { $0.rect.y < $1.rect.y }),
                  previous.rect.y - next.rect.cgRect.maxY < max(3.5, previous.rect.height * 0.5),
                  next.rect.height >= start.rect.height * 0.75, next.rect.height <= start.rect.height * 1.25 else { break }
            block.append(next)
            previous = next
        }
        return block
    }
}
