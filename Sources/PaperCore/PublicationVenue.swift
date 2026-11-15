import Foundation

public enum PublicationVenue {
    public static func label(_ metadata: Bibliography?) -> String? {
        guard let metadata, !metadata.venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = metadata.venueShortName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = name.flatMap { $0.isEmpty ? nil : $0 } ?? abbreviation(metadata.venue)
        let year = (metadata.venueYear ?? metadata.year).map(String.init) ?? ""
        return short.hasSuffix(year) || year.isEmpty ? short : short + year
    }
    public static func abbreviation(_ venue: String) -> String {
        let names = [
            ("design automation conference", "DAC"), ("international conference on computer-aided design", "ICCAD"),
            ("design, automation & test in europe", "DATE"), ("design automation and test in europe", "DATE"),
            ("solid-state circuits conference", "ISSCC"), ("journal of solid-state circuits", "JSSC"),
            ("transactions on computer-aided design", "TCAD"), ("very large scale integration systems", "TVLSI"),
            ("international conference on machine learning", "ICML"), ("learning representations", "ICLR"),
            ("neural information processing systems", "NeurIPS"), ("computer vision and pattern recognition", "CVPR"),
            ("international symposium on circuits and systems", "ISCAS")
        ]
        let normalized = venue.lowercased()
        // More specific journal names precede generic conference-name matching.
        if normalized.contains("transactions on computer-aided design") { return "TCAD" }
        if let match = names.first(where: { normalized.contains($0.0) }) { return match.1 }
        if let regex = try? NSRegularExpression(pattern: #"\(([A-Z][A-Za-z]{1,12})\)"#),
           let match = regex.firstMatch(in: venue, range: NSRange(venue.startIndex..., in: venue)),
           let range = Range(match.range(at: 1), in: venue) { return String(venue[range]) }
        return venue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
