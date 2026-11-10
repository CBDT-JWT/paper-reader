import Foundation

public struct LibraryFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var parentID: UUID?
    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) { self.id = id; self.name = name; self.parentID = parentID }
}
public struct PDFPoint: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ point: CGPoint) { self.init(x: point.x, y: point.y) }
    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
public enum AnnotationKind: String, Codable, CaseIterable, Sendable { case highlight, line, rectangle, ink }
public struct PaperAnnotation: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var page: Int
    public var kind: AnnotationKind
    public var rect: PDFRect
    public var points: [PDFPoint]
    public var color: String
    public var lineWidth: Double
    public init(id: UUID = UUID(), page: Int, kind: AnnotationKind, rect: PDFRect, points: [PDFPoint] = [], color: String = "gold", lineWidth: Double = 2) {
        self.id = id; self.page = page; self.kind = kind; self.rect = rect; self.points = points; self.color = color; self.lineWidth = lineWidth
    }
}
public struct Bibliography: Codable, Equatable, Sendable {
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String
    public var doi: String
    public var abstract: String
    public var volume: String
    public var issue: String
    public var pages: String
    public var kind: String
    public var origin: String
    public var arxivID: String?
    public init(title: String = "", authors: [String] = [], year: Int? = nil, venue: String = "", doi: String = "", abstract: String = "", volume: String = "", issue: String = "", pages: String = "", kind: String = "article", origin: String = "manual") {
        self.title = title; self.authors = authors; self.year = year; self.venue = venue; self.doi = doi; self.abstract = abstract
        self.volume = volume; self.issue = issue; self.pages = pages; self.kind = kind; self.origin = origin
    }
    public enum Style: String, CaseIterable, Sendable { case bibtex = "BibTeX", apa = "APA", ieee = "IEEE", gbt = "GB/T 7714" }
    public func citation(_ style: Style) -> String {
        let date = year.map(String.init) ?? "n.d."
        let people: String
        switch style {
        case .apa:
            let names = authors.map { Self.formattedName($0, style: style) }
            people = names.count > 1 ? names.dropLast().joined(separator: ", ") + (names.count == 2 ? " & " : ", & ") + names.last! : names.first ?? ""
        case .ieee: people = authors.map { Self.formattedName($0, style: style) }.joined(separator: ", ")
        case .gbt: people = authors.prefix(3).map { Self.formattedName($0, style: style) }.joined(separator: ", ") + (authors.count > 3 ? ", et al" : "")
        case .bibtex: people = authors.joined(separator: ", ")
        }
        let doiURL = doi.isEmpty ? arxivID.map { "https://arxiv.org/abs/\($0)" } ?? "" : "https://doi.org/\(doi)"
        switch style {
        case .bibtex:
            func escaped(_ s: String) -> String {
                let special: [Character: String] = ["\\": "\\textbackslash{}", "{": "\\{", "}": "\\}", "&": "\\&", "%": "\\%", "_": "\\_", "#": "\\#"]
                return s.map { special[$0] ?? String($0) }.joined()
            }
            let key = (authors.first?.split(separator: ",").first.map(String.init) ?? "paper").filter(\.isLetter) + (year.map(String.init) ?? "")
            let fields = [("title", title), ("author", authors.map(escaped).joined(separator: " and ")), ("year", year.map(String.init) ?? ""), (kind == "proceedings-article" ? "booktitle" : "journal", venue), ("volume", volume), ("number", issue), ("pages", pages), ("doi", doi), ("eprint", arxivID ?? ""), ("archivePrefix", arxivID == nil ? "" : "arXiv")]
            return "@\(kind == "proceedings-article" ? "inproceedings" : kind == "preprint" ? "misc" : "article"){\(key),\n" + fields.filter { !$0.1.isEmpty }.map { "  \($0.0) = {\($0.0 == "author" ? $0.1 : escaped($0.1))}" }.joined(separator: ",\n") + "\n}"
        case .apa:
            return [people.isEmpty ? nil : people + ".", "(\(date)).", title + ".", venue.isEmpty ? nil : venue + (volume.isEmpty ? "" : ", \(volume)" + (issue.isEmpty ? "" : "(\(issue))")) + (pages.isEmpty ? "" : ", \(pages)") + ".", doiURL.isEmpty ? nil : doiURL].compactMap { $0 }.joined(separator: " ")
        case .ieee:
            return [people.isEmpty ? nil : people + ",", "“\(title),”", venue.isEmpty ? nil : venue + ",", volume.isEmpty ? nil : "vol. \(volume),", issue.isEmpty ? nil : "no. \(issue),", pages.isEmpty ? nil : "pp. \(pages),", date + ".", doi.isEmpty ? nil : "doi: \(doi)."].compactMap { $0 }.joined(separator: " ")
        case .gbt:
            let type = kind == "proceedings-article" ? "C" : kind == "journal-article" || kind == "article" ? "J" : "Z"
            return [people.isEmpty ? nil : people + ".", "\(title)[\(type)].", venue.isEmpty ? nil : venue + ",", date + (volume.isEmpty ? "" : ", \(volume)" + (issue.isEmpty ? "" : "(\(issue))")) + (pages.isEmpty ? "" : ": \(pages)") + ".", doi.isEmpty ? nil : "DOI: \(doi)."].compactMap { $0 }.joined(separator: " ")
        }
    }
    private static func formattedName(_ source: String, style: Style) -> String {
        let parts = source.components(separatedBy: ",")
        guard parts.count > 1 else { return source }
        let family = parts[0].trimmingCharacters(in: .whitespaces), given = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let initials = given.split { !$0.isLetter }.compactMap { $0.first.map { String($0) + "." } }.joined(separator: " ")
        if style == .apa { return family + (initials.isEmpty ? "" : ", " + initials) }
        if style == .ieee { return (initials.isEmpty ? "" : initials + " ") + family }
        let chinese = family.unicodeScalars.contains { (0x4e00...0x9fff).contains(Int($0.value)) }
        return chinese ? family + given : family.uppercased() + (initials.isEmpty ? "" : " " + initials.replacingOccurrences(of: ".", with: ""))
    }
}
