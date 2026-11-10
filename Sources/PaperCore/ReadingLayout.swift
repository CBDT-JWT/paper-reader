import Foundation

public struct ReadingLine: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var rect: PDFRect
    public var column: Int
    public init(id: Int, text: String, rect: PDFRect, column: Int = 0) { self.id = id; self.text = text; self.rect = rect; self.column = column }
}
public struct ReadingLayout: Sendable {
    public let bounds: PDFRect
    public var lines: [ReadingLine]
    public var columnCount: Int
    public init(bounds: PDFRect, lines input: [ReadingLine]) {
        self.bounds = bounds
        let widths = input.map { $0.rect.width }.sorted()
        let typical = widths.isEmpty ? bounds.width : widths[widths.count / 2]
        let body = input.filter { $0.rect.width < min(bounds.width * 0.66, typical * 1.3) && $0.rect.width > 8 }
        var groups: [[ReadingLine]] = []
        for line in body.sorted(by: { $0.rect.x < $1.rect.x }) {
            if let group = groups.indices.max(by: { overlap(line, groups[$0]) < overlap(line, groups[$1]) }), overlap(line, groups[group]) > 0.52 {
                groups[group].append(line)
            } else { groups.append([line]) }
        }
        // Small isolated equations do not establish a new body column.
        groups = groups.filter { $0.count >= max(2, body.count / 14) }.sorted { ($0.map { $0.rect.x }.min() ?? 0) < ($1.map { $0.rect.x }.min() ?? 0) }
        if groups.count < 2 || groups.count > 4 { groups = [] }
        columnCount = max(groups.count, 1)
        self.lines = input.map { line in
            var value = line
            if groups.isEmpty { value.column = 0 }
            else if line.rect.width >= bounds.width * 0.66 { value.column = -1 }
            else {
                let candidates = groups.enumerated().map { (index: $0.offset, score: overlap(line, $0.element)) }
                let best = candidates.max { $0.score < $1.score }
                value.column = (best?.score ?? 0) > 0.35 ? best!.index : -1
            }
            return value
        }
        // Adjacent spanning lines form a block; unrelated titles/captions never share a focus band.
        let spanning = self.lines.indices.filter { self.lines[$0].column < 0 }.sorted { self.lines[$0].rect.y > self.lines[$1].rect.y }
        var block = -1
        var previous: ReadingLine?
        for index in spanning {
            let line = self.lines[index]
            if let previous, previous.rect.y - line.rect.y > max(previous.rect.height, line.rect.height) * 2.5 { block -= 1 }
            self.lines[index].column = block; previous = line
        }
    }
    /// Column-major reading order within each band separated by a spanning title/equation.
    public func readingOrder(manualColumn: Int? = nil, manualCount: Int = 2) -> [ReadingLine] {
        if let column = manualColumn {
            let width = bounds.width / Double(max(1, manualCount))
            let region = CGRect(x: bounds.x + Double(column) * width, y: bounds.y, width: width, height: bounds.height)
            return lines.compactMap { line in
                let rect = line.rect.cgRect.intersection(region); guard !rect.isNull, rect.width > 2 else { return nil }
                var copy = line; copy.rect = PDFRect(rect); copy.column = column; return copy
            }.sorted { $0.rect.y > $1.rect.y }
        }
        let spanning = lines.filter { $0.column < 0 }.sorted { $0.rect.y > $1.rect.y }
        var body = lines.filter { $0.column >= 0 }
        var result: [ReadingLine] = []
        func ordered(_ items: [ReadingLine]) -> [ReadingLine] {
            items.sorted { $0.column == $1.column ? ($0.rect.y == $1.rect.y ? $0.rect.x < $1.rect.x : $0.rect.y > $1.rect.y) : $0.column < $1.column }
        }
        for span in spanning {
            let above = body.filter { $0.rect.y > span.rect.y }
            result += ordered(above); let ids = Set(above.map(\.id)); body.removeAll { ids.contains($0.id) }
            result.append(span)
        }
        result += ordered(body)
        return result
    }
    public func focused(at point: PDFPoint, above: Int, below: Int, manualColumn: Int? = nil, manualCount: Int = 2) -> [ReadingLine] {
        var available = lines
        if let manualColumn {
            let width = bounds.width / Double(max(manualCount, 1))
            let left = bounds.x + width * Double(manualColumn)
            let region = CGRect(x: left, y: bounds.y, width: width, height: bounds.height)
            available = lines.compactMap { line in
                let clipped = line.rect.cgRect.intersection(region)
                guard !clipped.isNull, clipped.width > 2 else { return nil }
                var line = line; line.rect = PDFRect(clipped); line.column = manualColumn; return line
            }
        }
        guard let nearest = available.min(by: { distance(point, $0.rect.cgRect) < distance(point, $1.rect.cgRect) }) else { return [] }
        let spanning = manualColumn == nil && nearest.column >= 0 ? lines.filter { $0.column < 0 } : []
        let ceiling = spanning.filter { $0.rect.y > nearest.rect.y }.map { $0.rect.y }.min() ?? .infinity
        let floor = spanning.filter { $0.rect.y < nearest.rect.y }.map { $0.rect.y }.max() ?? -.infinity
        let column = available.filter { $0.column == nearest.column && $0.rect.y < ceiling && $0.rect.y > floor }.sorted {
            abs($0.rect.y - $1.rect.y) > 2 ? $0.rect.y > $1.rect.y : $0.rect.x < $1.rect.x
        }
        guard let index = column.firstIndex(where: { $0.id == nearest.id }) else { return [] }
        return Array(column[max(0, index - max(above, 0))...min(column.count - 1, index + max(below, 0))])
    }
}
private func overlap(_ line: ReadingLine, _ group: [ReadingLine]) -> Double {
    group.map { other in
        max(0, min(line.rect.x + line.rect.width, other.rect.x + other.rect.width) - max(line.rect.x, other.rect.x)) / min(line.rect.width, other.rect.width)
    }.max() ?? 0
}
private func distance(_ point: PDFPoint, _ rect: CGRect) -> Double {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return dx * dx * 4 + dy * dy
}
