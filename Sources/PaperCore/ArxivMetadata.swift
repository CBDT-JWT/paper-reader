import Foundation

public extension MetadataService {
    static func arxivID(in text: String) -> String? {
        let pattern = #"(?:arxiv\s*:\s*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?|[a-z-]+(?:\.[A-Z]{2})?/\d{7}(?:v\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    static func fetchArxiv(id: String) async throws -> Bibliography {
        guard arxivID(in: "arXiv:" + id) == id else { throw LibraryError.invalidPath }
        await ArxivRateLimiter.shared.wait()
        try Task.checkCancellation()
        var url = URLComponents(string: "https://export.arxiv.org/api/query")!
        url.queryItems = [URLQueryItem(name: "id_list", value: id)]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 25; request.setValue("PaperReader/0.2 (metadata lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decodeArxiv(data)
    }
    static func decodeArxiv(_ data: Data) throws -> Bibliography {
        let delegate = ArxivParser(); let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.value.title.isEmpty, delegate.value.arxivID != nil else { throw URLError(.cannotParseResponse) }
        return delegate.value
    }
}
private final class ArxivParser: NSObject, XMLParserDelegate {
    var value = Bibliography(venue: "arXiv", kind: "preprint", origin: "arXiv")
    var entry = false, current = "", buffer = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "entry" { entry = true }
        current = elementName; buffer = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if entry { buffer += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard entry else { return }
        let text = buffer.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        switch elementName {
        case "title": value.title = text
        case "summary": value.abstract = text
        case "published": value.year = Int(text.prefix(4))
        case "id": value.arxivID = MetadataService.arxivID(in: text)
        case "name":
            let names = text.split(separator: " "); if let family = names.last { value.authors.append(String(family) + (names.count > 1 ? ", " + names.dropLast().joined(separator: " ") : "")) }
        case "arxiv:doi": value.doi = text
        case "entry": entry = false
        default: break
        }
        buffer = ""
    }
}
private actor ArxivRateLimiter {
    static let shared = ArxivRateLimiter()
    private var next = Date.distantPast
    func wait() async {
        let delay = max(0, next.timeIntervalSinceNow); next = Date().addingTimeInterval(delay + 3)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }
}
