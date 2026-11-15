import Foundation

public struct RelatedPaper: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let authors: [String]
    public let year: Int?
    public let venue: String
    public let doi: String
    public let citationCount: Int
    public let abstract: String
    public let references: [String]
    public let related: [String]
    public var url: URL? { URL(string: doi.isEmpty ? id : "https://doi.org/" + doi) }
}
public struct LiteratureEdge: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case citation, related, sharedReferences }
    public let source: String
    public let target: String
    public let kind: Kind
    public let strength: Int
    public var id: String { source + "|" + target + "|" + kind.rawValue }
}
public struct LiteratureGraph: Codable, Sendable {
    public let rootID: String
    public let papers: [RelatedPaper]
    public let edges: [LiteratureEdge]
    public let fetchedAt: Date
}

public enum RelatedPapersService {
    public static func load(query: String) async throws -> LiteratureGraph {
        let root: RelatedPaper
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.hasPrefix("https://openalex.org/W") || query.range(of: #"^W\d+$"#, options: .regularExpression) != nil {
            root = try await work(String(query.split(separator: "/").last ?? ""))
        } else if let doi = MetadataService.doi(in: query) {
            root = try await work("https://doi.org/" + doi)
        } else {
            let filename = query.replacingOccurrences(of: #"\.pdf$"#, with: "", options: [.regularExpression, .caseInsensitive])
            let cleaned = filename.replacingOccurrences(of: #"^\d+[_ -]+|[_ -](?:DAC|ICCAD|DATE|ISSCC|CVPR|ICML|ICLR|NeurIPS)[_ -]?\d{4}$"#, with: "", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: "_", with: " ")
            let results = try await fetch(path: "works", items: [.init(name: "search", value: cleaned), .init(name: "per_page", value: "5")])["results"].array.compactMap(decode)
            let normalize: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            guard let match = results.first(where: { normalize($0.title).contains(normalize(cleaned)) || normalize(cleaned).contains(normalize($0.title)) }), !cleaned.isEmpty else {
                throw AIError.message(L("未找到匹配文献，请输入 DOI 或完整论文标题。"))
            }
            root = match
        }
        try Task.checkCancellation()
        let shortID = String(root.id.split(separator: "/").last ?? "")
        let citing = try await fetch(path: "works", items: [.init(name: "filter", value: "cites:" + shortID), .init(name: "sort", value: "cited_by_count:desc"), .init(name: "per_page", value: "8")])["results"].array.compactMap(decode)
        var ids: [String] = [], seen: Set<String> = [root.id]
        for id in Array(root.related.prefix(12)) + Array(root.references.prefix(12)) where seen.insert(id).inserted { ids.append(id) }
        var neighbors: [RelatedPaper] = []
        if !ids.isEmpty {
            let filter = ids.compactMap { $0.split(separator: "/").last.map(String.init) }.joined(separator: "|")
            neighbors = try await fetch(path: "works", items: [.init(name: "filter", value: "openalex:" + filter), .init(name: "per_page", value: "30")])["results"].array.compactMap(decode)
        }
        var papers = [root], included: Set<String> = [root.id]
        for paper in neighbors + citing where included.insert(paper.id).inserted { papers.append(paper) }
        var edges: [LiteratureEdge] = []
        for paper in papers {
            for reference in paper.references where included.contains(reference) && reference != paper.id {
                edges.append(.init(source: paper.id, target: reference, kind: .citation, strength: 1))
            }
            if paper.id != root.id, root.related.contains(paper.id) {
                edges.append(.init(source: root.id, target: paper.id, kind: .related, strength: 1))
            }
        }
        // Bibliographic coupling uses actual shared reference IDs returned by OpenAlex.
        for (index, paper) in papers.enumerated() {
            let references = Set(paper.references)
            let candidates = papers.dropFirst(index + 1).map { ($0.id, references.intersection($0.references).count) }.filter { $0.1 >= 3 }.sorted { $0.1 > $1.1 }.prefix(2)
            for (id, count) in candidates { edges.append(.init(source: paper.id, target: id, kind: .sharedReferences, strength: count)) }
        }
        return .init(rootID: root.id, papers: papers, edges: edges, fetchedAt: .now)
    }
    private static func work(_ id: String) async throws -> RelatedPaper {
        guard let result = decode(try await fetch(path: "works/" + id)) else { throw URLError(.cannotParseResponse) }
        return result
    }
    private static func fetch(path: String, items: [URLQueryItem] = []) async throws -> JSONValue {
        var url = URLComponents(string: "https://api.openalex.org")!
        url.path = "/" + path; url.queryItems = items
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30
        request.setValue("PaperReader/0.4.14 (macOS literature explorer)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw AIError.message(L("OpenAlex 请求失败（HTTP \(response.statusCode)），请稍后重试。")) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    private static func decode(_ value: JSONValue) -> RelatedPaper? {
        guard let id = value["id"].string, let title = value["display_name"].string, !title.isEmpty else { return nil }
        let words = value["abstract_inverted_index"].object.flatMap { word, positions in positions.array.compactMap { $0.number.flatMap { Int(exactly: $0).map { ($0, word) } } } }.sorted { $0.0 < $1.0 }.prefix(400).map(\.1).joined(separator: " ")
        let year = value["publication_year"].number.flatMap { Int(exactly: $0) }
        let count = max(0, min(1_000_000_000, value["cited_by_count"].number ?? 0))
        return .init(id: id, title: title,
                     authors: value["authorships"].array.compactMap { $0["author"]["display_name"].string },
                     year: year,
                     venue: value["primary_location"]["source"]["display_name"].string ?? "",
                     doi: (value["doi"].string ?? "").replacingOccurrences(of: "https://doi.org/", with: ""),
                     citationCount: Int(count), abstract: words,
                     references: value["referenced_works"].array.compactMap(\.string), related: value["related_works"].array.compactMap(\.string))
    }
}

public enum LiteratureGraphLayout {
    public static func positions(_ graph: LiteratureGraph) -> [String: CGPoint] {
        let count = graph.papers.count
        guard count > 0 else { return [:] }
        var points: [CGPoint] = graph.papers.enumerated().map { index, _ in
            if index == 0 { return CGPoint(x: 0.5, y: 0.5) }
            let angle = Double(index - 1) * 2 * .pi / Double(max(1, count - 1))
            return CGPoint(x: 0.5 + cos(angle) * 0.36, y: 0.5 + sin(angle) * 0.36)
        }
        let indices = Dictionary(uniqueKeysWithValues: graph.papers.enumerated().map { ($0.element.id, $0.offset) })
        for _ in 0..<160 {
            var forces = Array(repeating: CGPoint.zero, count: count)
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let dx = points[i].x - points[j].x, dy = points[i].y - points[j].y
                    let distance = max(0.008, dx * dx + dy * dy), factor = 0.00012 / distance
                    forces[i].x += dx * factor; forces[i].y += dy * factor
                    forces[j].x -= dx * factor; forces[j].y -= dy * factor
                }
            }
            for edge in graph.edges {
                guard let i = indices[edge.source], let j = indices[edge.target] else { continue }
                let dx = points[j].x - points[i].x, dy = points[j].y - points[i].y
                forces[i].x += dx * 0.018; forces[i].y += dy * 0.018
                forces[j].x -= dx * 0.018; forces[j].y -= dy * 0.018
            }
            for i in points.indices where graph.papers[i].id != graph.rootID {
                points[i].x = min(0.92, max(0.08, points[i].x + min(0.015, max(-0.015, forces[i].x + (0.5 - points[i].x) * 0.003))))
                points[i].y = min(0.84, max(0.08, points[i].y + min(0.015, max(-0.015, forces[i].y + (0.5 - points[i].y) * 0.003))))
            }
        }
        return Dictionary(uniqueKeysWithValues: graph.papers.enumerated().map { ($0.element.id, points[$0.offset]) })
    }
}
