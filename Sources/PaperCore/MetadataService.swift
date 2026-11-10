import Foundation

public enum MetadataService {
    public static func doi(in text: String) -> String? {
        let pattern = #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)")).lowercased()
    }
    public static func fetch(doi: String) async throws -> Bibliography {
        let cleaned = doi.replacingOccurrences(of: "https://doi.org/", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.doi(in: cleaned) == cleaned.lowercased(), var components = URLComponents(string: "https://api.crossref.org/works/") else { throw LibraryError.invalidPath }
        components.path += cleaned
        var request = URLRequest(url: components.url!); request.setValue("PaperReader/0.2 (macOS research reader)", forHTTPHeaderField: "User-Agent"); request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decodeCrossref(data)
    }
    public static func decodeCrossref(_ data: Data) throws -> Bibliography {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let value = root?["message"] as? [String: Any], let title = (value["title"] as? [String])?.first, !title.isEmpty else { throw URLError(.cannotParseResponse) }
        let authors = (value["author"] as? [[String: Any]] ?? []).map { item in
            let family = item["family"] as? String ?? item["name"] as? String ?? ""
            let given = item["given"] as? String ?? ""
            return family + (given.isEmpty ? "" : ", " + given)
        }.filter { !$0.isEmpty }
        let date = value["published"] as? [String: Any] ?? value["issued"] as? [String: Any]
        let year = (date?["date-parts"] as? [[Int]])?.first?.first
        let abstract = (value["abstract"] as? String ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return Bibliography(title: title, authors: authors, year: year, venue: (value["container-title"] as? [String])?.first ?? "", doi: value["DOI"] as? String ?? "", abstract: abstract, volume: value["volume"] as? String ?? "", issue: value["issue"] as? String ?? "", pages: value["page"] as? String ?? "", kind: value["type"] as? String ?? "article", origin: "Crossref")
    }
}
