import Foundation

public struct ReadingGlyph: Sendable {
    public let text: String
    public let rect: PDFRect
    public let sourceLine: Int?
    public init(text: String, rect: PDFRect, sourceLine: Int? = nil) { self.text = text; self.rect = rect; self.sourceLine = sourceLine }
}

/// Reconstruct physical lines instead of trusting a PDF's logical/tagged text boxes.
/// This removes near-zero-size LaTeXiT metadata and splits parallel columns at the gutter.
public enum ReadingLineBuilder {
    public static func lines(glyphs: [ReadingGlyph], bounds: PDFRect) -> [ReadingLine] {
        let visible = glyphs.filter { glyph in
            let rect = glyph.rect.cgRect
            return rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite &&
                rect.width >= 0.1 && rect.height >= 2 && rect.height < bounds.height * 0.15 &&
                rect.intersects(bounds.cgRect) && !glyph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.rect.cgRect.midY > $1.rect.cgRect.midY }
        var rows: [[ReadingGlyph]] = []
        var rowRects: [CGRect] = []
        for glyph in visible {
            let rect = glyph.rect.cgRect
            let candidates = max(0, rows.count - 16)..<rows.count
            if let index = candidates.min(by: { abs(rowRects[$0].midY - rect.midY) < abs(rowRects[$1].midY - rect.midY) }),
               (abs(rowRects[index].midY - rect.midY) <= max(2.5, min(rowRects[index].height, rect.height) * 0.5) ||
                rowRects[index].intersection(rect).height > min(rowRects[index].height, rect.height) * 0.55) {
                rows[index].append(glyph); rowRects[index] = rowRects[index].union(rect)
            } else { rows.append([glyph]); rowRects.append(rect) }
        }
        let gutters = columnGutters(in: rows, bounds: bounds)
        var result: [ReadingLine] = []
        for row in rows {
            let ordered = row.sorted { $0.rect.x < $1.rect.x }
            let heights = row.map { $0.rect.height }.sorted()
            let height = heights[heights.count / 2]
            let gutterGap = max(12, min(bounds.width * 0.03, height * 3))
            var text = "", region = CGRect.null, previous: CGRect?
            var previousSource: Int?
            func append() {
                guard !text.isEmpty, !region.isNull else { return }
                result.append(.init(id: result.count, text: text, rect: PDFRect(region.intersection(bounds.cgRect))))
                text = ""; region = .null
            }
            for glyph in ordered {
                let rect = glyph.rect.cgRect
                let gap = previous.map { rect.minX - $0.maxX } ?? 0
                let splitGap = previousSource != nil && previousSource == glyph.sourceLine ? max(24, height * 4) : gutterGap
                let crossesGutter = previous.map { previous in
                    gap >= max(5, height * 0.8) && gutters.contains { previous.maxX < $0 && rect.minX > $0 }
                } ?? false
                if gap > splitGap || crossesGutter { append() }
                else if !text.isEmpty && gap > max(1, height * 0.16) { text += " " }
                text += glyph.text; region = region.union(rect); previous = rect; previousSource = glyph.sourceLine
            }
            append()
        }
        return result
    }

    /// A repeated physical gap overrides a PDF tag that joins text across columns.
    /// Long footer lines and spanning headings can cross a gutter without defining it.
    private static func columnGutters(in rows: [[ReadingGlyph]], bounds: PDFRect) -> [Double] {
        let binWidth = 4.0
        let count = max(1, Int(bounds.width / binWidth))
        var votes = [Int](repeating: 0, count: count)
        for row in rows {
            let ordered = row.sorted { $0.rect.x < $1.rect.x }
            let heights = ordered.map { $0.rect.height }.sorted()
            guard let height = heights.dropFirst(heights.count / 2).first else { continue }
            let letters = ordered.map { $0.text.filter(\.isLetter).count }
            let total = letters.reduce(0, +)
            var leftLetters = 0
            for index in ordered.indices.dropLast() {
                leftLetters += letters[index]
                guard leftLetters >= 12, total - leftLetters >= 12 else { continue }
                let left = ordered[index].rect.cgRect.maxX
                let right = ordered[index + 1].rect.x
                guard right - left >= max(5, height * 0.8) else { continue }
                for bin in votes.indices {
                    let x = bounds.x + (Double(bin) + 0.5) * binWidth
                    if x > bounds.x + bounds.width * 0.16, x < bounds.x + bounds.width * 0.84, x > left, x < right {
                        votes[bin] += 1
                    }
                }
            }
        }
        let minimum = max(4, rows.count / 6)
        var result: [Double] = []
        while let peak = votes.max(), peak >= minimum, result.count < 3,
              let first = votes.firstIndex(of: peak) {
            var end = first
            while end + 1 < count && votes[end + 1] == peak { end += 1 }
            let x = bounds.x + (Double(first + end) / 2 + 0.5) * binWidth
            result.append(x)
            for bin in votes.indices where abs(bounds.x + (Double(bin) + 0.5) * binWidth - x) < bounds.width * 0.12 {
                votes[bin] = 0
            }
        }
        return result.sorted()
    }
}
