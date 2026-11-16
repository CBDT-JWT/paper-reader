import Foundation

public struct DownloadedPaper: Sendable {
    public let file: URL
    public let requestedURL: URL
    public let downloadURL: URL
    public let sourceVersion: String?
    public func cleanup() { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
}

public enum PaperDownloadService {
    public static func download(_ source: URL, fileName: String? = nil) async throws -> DownloadedPaper {
        guard valid(source) else { throw LibraryError.invalidPath }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "PaperReader/0.4.18 (macOS research library)"]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let ieeeID = articleNumber(source)
        let arxiv = arxivPDF(source)
        var queue: [(URL, String?)] = [(arxiv ?? source, nil)]
        if let id = ieeeID {
            queue += [(URL(string: "https://ieeexplore.ieee.org/document/" + id)!, nil),
                     (URL(string: "https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=" + id)!, nil),
                     (URL(string: "https://ieeexplore.ieee.org/stampPDF/getPDF.jsp?tp=&arnumber=" + id + "&ref=")!, nil)]
        }
        var visited: Set<URL> = []
        var doi = ["doi.org", "dx.doi.org"].contains(source.host?.lowercased() ?? "") ? MetadataService.doi(in: source.path) : nil
        var lookedForOpenCopy = false
        while true {
            try Task.checkCancellation()
            if queue.isEmpty {
                guard !lookedForOpenCopy else { break }
                lookedForOpenCopy = true
                if doi == nil, let ieeeID { doi = try? await citationDOI(ieeeID, session: session) }
                if let doi { queue = (try? await openCopies(doi, session: session)) ?? [] }
                if queue.isEmpty { break }
            }
            let (candidate, version) = queue.removeFirst()
            guard visited.count < 12, valid(candidate), visited.insert(candidate).inserted else { continue }
            if arxivPDF(candidate) != nil { await ArxivRateLimiter.shared.wait(); try Task.checkCancellation() }
            var request = URLRequest(url: candidate); request.timeoutInterval = 90
            request.setValue("PaperReader/0.4.18 (macOS research library)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/pdf,text/html;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue(source.absoluteString, forHTTPHeaderField: "Referer")
            do {
                let (temporary, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let finalURL = response.url, valid(finalURL) else { continue }
                let handle = try FileHandle(forReadingFrom: temporary)
                let prefix: Data
                do { prefix = try handle.read(upToCount: 2_000_000) ?? Data(); try handle.close() }
                catch { try? handle.close(); throw error }
                if String(decoding: prefix.prefix(1024), as: UTF8.self).contains("%PDF-") {
                    try Task.checkCancellation()
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-Paper-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    let suggested = fileName ?? arxiv.map { "arXiv-" + $0.lastPathComponent + ".pdf" } ?? ieeeID.map { "IEEE-" + $0 + ".pdf" } ?? response.suggestedFilename ?? "paper.pdf"
                    let file = directory.appendingPathComponent(safeName(suggested))
                    do { try FileManager.default.moveItem(at: temporary, to: file) }
                    catch { try? FileManager.default.removeItem(at: directory); throw error }
                    return .init(file: file, requestedURL: source, downloadURL: finalURL, sourceVersion: version)
                }
                let html = String(decoding: prefix, as: UTF8.self)
                let discovered = links(in: html, relativeTo: finalURL)
                doi = doi ?? discovered.doi
                queue.insert(contentsOf: discovered.pdfs.filter { !visited.contains($0) }.map { ($0, version) }, at: 0)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if Task.isCancelled { throw CancellationError() }
                let failure = error as NSError
                if failure.domain == NSCocoaErrorDomain || failure.domain == NSPOSIXErrorDomain { throw error }
            }
        }
        try Task.checkCancellation()
        throw AIError.message(L("该来源未返回可访问的 PDF，可打开来源网页下载后导入。"))
    }
    public static func isPaperLink(_ url: URL) -> Bool {
        arxivPDF(url) != nil || articleNumber(url) != nil || url.pathExtension.lowercased() == "pdf" || ["doi.org", "dx.doi.org"].contains(url.host?.lowercased() ?? "")
    }
    private static func valid(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
    }
    private static func arxivPDF(_ url: URL) -> URL? {
        guard ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].contains(url.host?.lowercased() ?? "") else { return nil }
        let pieces = url.path.split(separator: "/").map(String.init)
        guard let first = pieces.first, ["abs", "pdf", "html"].contains(first) else { return nil }
        let path = pieces.dropFirst().joined(separator: "/").replacingOccurrences(of: #"\.pdf$"#, with: "", options: .regularExpression)
        guard MetadataService.arxivID(in: "arXiv:" + path) == path else { return nil }
        return URL(string: "https://arxiv.org/pdf/" + path)
    }
    private static func articleNumber(_ url: URL) -> String? {
        guard url.host?.lowercased() == "ieeexplore.ieee.org" else { return nil }
        if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "arnumber" })?.value,
           id.range(of: #"^\d{1,12}$"#, options: .regularExpression) != nil { return id }
        let parts = url.path.split(separator: "/")
        if let index = parts.firstIndex(of: "document"), parts.indices.contains(index + 1) {
            let id = String(parts[index + 1])
            if id.range(of: #"^\d{1,12}$"#, options: .regularExpression) != nil { return id }
        }
        return nil
    }
    private static func safeName(_ suggested: String) -> String {
        let stem = (suggested as NSString).deletingPathExtension
        let clean = stem.map { "/\\:\n\r\t".contains($0) || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? "-" : String($0) }.joined().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var name = ""
        for character in clean {
            guard name.utf8.count + String(character).utf8.count <= 200 else { break }
            name.append(character)
        }
        return (name.isEmpty ? "paper" : name) + ".pdf"
    }
    private static func links(in html: String, relativeTo base: URL) -> (pdfs: [URL], doi: String?) {
        var pdfs: [URL] = [], doi: String?
        func url(_ raw: String) -> URL? {
            let text = raw.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#38;", with: "&").replacingOccurrences(of: "&#x26;", with: "&")
            guard let value = URL(string: text, relativeTo: base)?.absoluteURL, valid(value) else { return nil }
            return value
        }
        let tags = captures(#"<(?:meta|link|iframe|frame)\b[^>]*>"#, in: html)
        for tag in tags {
            var attributes: [String: String] = [:]
            if let regex = try? NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*(["'])(.*?)\2"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let ns = tag as NSString
                for match in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) { attributes[ns.substring(with: match.range(at: 1)).lowercased()] = ns.substring(with: match.range(at: 3)) }
            }
            let name = (attributes["name"] ?? attributes["property"] ?? "").lowercased()
            if attributes["http-equiv"]?.lowercased() == "refresh", let content = attributes["content"],
               let marker = content.range(of: "url=", options: .caseInsensitive) {
                let raw = String(content[marker.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if let value = url(raw), value.pathExtension.lowercased() == "pdf" || value.path.contains("getPDF.jsp") { pdfs.append(value) }
            }
            if name == "citation_doi" { doi = attributes["content"].flatMap(MetadataService.doi) }
            if name == "citation_pdf_url", let raw = attributes["content"], let value = url(raw) { pdfs.append(value) }
            if attributes["type"]?.lowercased() == "application/pdf", let raw = attributes["href"], let value = url(raw) { pdfs.append(value) }
            if let raw = attributes["src"], let value = url(raw), value.pathExtension.lowercased() == "pdf" || value.path.contains("getPDF.jsp") { pdfs.append(value) }
        }
        for field in ["pdfUrl", "pdfPath", "doi"] {
            let pattern = "\\\"" + field + #""\s*:\s*("(?:\\.|[^"\\])*")"#
            guard let raw = captures(pattern, in: html, group: 1).first, let value = try? JSONValue.parse(raw).string else { continue }
            if field == "doi" { doi = doi ?? MetadataService.doi(in: value) }
            else if let value = url(value) { pdfs.append(value) }
        }
        return (pdfs, doi)
    }
    private static func captures(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: group)) }
    }
    private static func citationDOI(_ id: String, session: URLSession) async throws -> String? {
        let url = URL(string: "https://ieeexplore.ieee.org/rest/search/citation/format?recordIds=" + id + "&fromPage=&citations-format=citation-abstract&download-format=download-bibtex")!
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("https://ieeexplore.ieee.org/document/" + id, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        return value["data"].string.flatMap(MetadataService.doi)
    }
    private static func openCopies(_ doi: String, session: URLSession) async throws -> [(URL, String?)] {
        var url = URLComponents(string: "https://api.openalex.org")!
        url.path = "/works/https://doi.org/" + doi
        var request = URLRequest(url: url.url!); request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let work = try JSONDecoder().decode(JSONValue.self, from: data)
        guard work["doi"].string.flatMap(MetadataService.doi)?.lowercased() == doi.lowercased() else { return [] }
        let locations = [work["best_oa_location"]] + work["locations"].array.filter { $0["is_oa"] == .bool(true) }
        var seen: Set<URL> = []
        return Array(locations.compactMap { location -> (URL, String?)? in
            guard let raw = location["pdf_url"].string ?? location["landing_page_url"].string,
                  let url = URL(string: raw), valid(url), seen.insert(url).inserted else { return nil }
            return (arxivPDF(url) ?? url, location["version"].string ?? "open-access")
        }.prefix(4))
    }
}
