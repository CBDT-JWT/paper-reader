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
        let clean = input.filter { $0.rect.height >= 2 && $0.rect.width >= 2 && !$0.text.contains("<latexit") }
        // Axis labels, page numbers and author blocks must not establish the body column width.
        let prose = clean.filter { $0.text.filter { !$0.isWhitespace }.count >= 24 && $0.rect.width > bounds.width * 0.12 }
        let sample = prose.count >= 4 ? prose : clean.filter { $0.rect.width > bounds.width * 0.12 }
        let widths = sample.map { $0.rect.width }.sorted()
        let typical = widths.isEmpty ? bounds.width : widths[widths.count / 2]
        let typicalHeight = median(sample.map { $0.rect.height }, fallback: 12)
        let body = sample.filter { $0.rect.width < min(bounds.width * 0.66, typical * 1.3) && $0.rect.width > 8 && $0.rect.height <= typicalHeight * 1.4 }
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
        self.lines = clean.map { line in
            var value = line
            if groups.isEmpty { value.column = 0 }
            else if line.rect.width >= bounds.width * 0.66 || groups.dropLast().enumerated().contains(where: { index, left in
                let right = groups[index + 1]
                let boundary = (median(left.map { $0.rect.x + $0.rect.width }, fallback: 0) + median(right.map { $0.rect.x }, fallback: bounds.width)) / 2
                return line.rect.x < boundary - 8 && line.rect.x + line.rect.width > boundary + 8
            }) { value.column = -1 }
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
        if manualColumn == nil, columnCount > 1 {
            // Adjacent font boxes can overlap vertically. Prefer the physical baseline
            // nearest the pointer; padding a heading's box can steal the next body line.
            let hit = available.filter { $0.rect.cgRect.contains(point.cgPoint) }.min {
                abs($0.rect.cgRect.midY - point.y) < abs($1.rect.cgRect.midY - point.y)
            }
            if let hit, hit.column < 0 { available = available.filter { $0.column == hit.column } }
            else {
                let columns = (0..<columnCount).compactMap { column -> (Int, CGRect)? in
                    let region = lines.filter { $0.column == column }.reduce(CGRect.null) { $0.union($1.rect.cgRect) }
                    return region.isNull ? nil : (column, region)
                }
                if let column = columns.min(by: { horizontalDistance(point.x, $0.1) < horizontalDistance(point.x, $1.1) })?.0 {
                    available = available.filter { $0.column == column }
                }
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
    /// One aperture contains the selected lines, including their interline whitespace.
    /// Padding stops at the gutter so a window never includes the adjacent column.
    public func focusRectangle(at point: PDFPoint, above: Int, below: Int, manualColumn: Int? = nil, manualCount: Int = 2, padding: Double = 6) -> PDFRect? {
        let selected = focused(at: point, above: above, below: below, manualColumn: manualColumn, manualCount: manualCount)
        guard let first = selected.first else { return nil }
        var limit = bounds.cgRect
        if let manualColumn {
            let width = bounds.width / Double(max(1, manualCount))
            limit = CGRect(x: bounds.x + Double(manualColumn) * width, y: bounds.y, width: width, height: bounds.height).intersection(limit)
        } else if first.column >= 0, columnCount > 1 {
            let own = lines.filter { $0.column == first.column }.reduce(CGRect.null) { $0.union($1.rect.cgRect) }
            let left = lines.filter { $0.column >= 0 && $0.column < first.column }.map { $0.rect.cgRect.maxX }.max()
            let right = lines.filter { $0.column > first.column }.map { $0.rect.cgRect.minX }.min()
            if let left { limit.origin.x = max(limit.minX, (left + own.minX) / 2) }
            let maximum = right.map { min(bounds.cgRect.maxX, (own.maxX + $0) / 2) } ?? bounds.cgRect.maxX
            limit.size.width = max(0, maximum - limit.minX)
        }
        let content = selected.reduce(CGRect.null) { $0.union($1.rect.cgRect) }
        let rectangle = content.insetBy(dx: -max(0, padding), dy: -max(4, padding)).intersection(limit)
        return rectangle.isNull || rectangle.isEmpty ? nil : PDFRect(rectangle)
    }
}
private func median(_ values: [Double], fallback: Double) -> Double { let sorted = values.sorted(); return sorted.isEmpty ? fallback : sorted[sorted.count / 2] }
private func overlap(_ line: ReadingLine, _ group: [ReadingLine]) -> Double {
    // Compare against the group's typical body extent. A centered title or figure label
    // must not bridge otherwise separate columns through a single outlier rectangle.
    let left = median(group.map { $0.rect.x }, fallback: 0)
    let right = median(group.map { $0.rect.x + $0.rect.width }, fallback: 0)
    return max(0, min(line.rect.x + line.rect.width, right) - max(line.rect.x, left)) / max(1, min(line.rect.width, right - left))
}
private func distance(_ point: PDFPoint, _ rect: CGRect) -> Double {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return dx * dx * 4 + dy * dy
}

private func horizontalDistance(_ x: Double, _ rect: CGRect) -> Double { max(rect.minX - x, 0, x - rect.maxX) }
