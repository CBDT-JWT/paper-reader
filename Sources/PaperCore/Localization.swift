import Foundation

public enum AppLanguage {
    public static var code: String { Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en" }
    private static let english: [String: String] = {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "json"), let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()
    private static let patterns: [(NSRegularExpression, String)] = english.compactMap { key, value in
        guard key.contains("%@") else { return nil }
        let pattern = "^" + key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([\\s\\S]*?)") + "$"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }; return (expression, value)
    }
    public static func text(_ source: String) -> String {
        guard code == "en" else { return source }
        if let value = english[source] { return value }
        for (pattern, value) in patterns {
            if let match = pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) {
                let arguments: [CVarArg] = (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: source).map { String(source[$0]) as NSString } ?? "" as NSString }
                return String(format: value, arguments: arguments)
            }
        }
        return source
    }
}
/// Chinese source keys are kept stable; all user-facing copy resolves through the system language.
public func L(_ source: String) -> String { AppLanguage.text(source) }
