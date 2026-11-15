import Foundation
import PaperCore

struct AgentChoice: Codable, Identifiable, Sendable {
    let value: String
    let name: String
    var id: String { value }
}
struct AgentSessionOption: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let currentValue: String
    let choices: [AgentChoice]
    static func parse(_ values: JSONValue) -> [Self] {
        values.array.compactMap { value in
            guard value["type"].string == "select", let id = value["id"].string,
                  let name = value["name"].string, let current = value["currentValue"].string else { return nil }
            let choices = value["options"].array.flatMap { entry -> [JSONValue] in
                entry["options"].array.isEmpty ? [entry] : entry["options"].array
            }.compactMap { option -> AgentChoice? in
                guard let value = option["value"].string, let name = option["name"].string else { return nil }
                return .init(value: value, name: name)
            }
            guard !choices.isEmpty else { return nil }
            return .init(id: id, name: name, category: value["category"].string ?? "", currentValue: current, choices: choices)
        }
    }
}

extension AIBackend {
    var usesACP: Bool { [.qwenCode, .deepseekHarness, .workBuddy].contains(self) }
    var usesCLI: Bool { self == .codex || self == .claudeCode || usesACP }
    var launchArguments: [String] {
        switch self {
        case .deepseekHarness: ["--profile", "acp"]
        default: ["--acp"]
        }
    }
    var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .qwenCode: "qwen"
        case .deepseekHarness: "dsh"
        case .workBuddy: "codebuddy"
        default: "codex"
        }
    }
    var defaultExecutable: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin/\(executableName)", "/opt/homebrew/bin/\(executableName)", "/usr/local/bin/\(executableName)", "\(home)/.npm-global/bin/\(executableName)", "\(home)/.bun/bin/\(executableName)"]
        if let installed = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return installed }
        return paths[1]
    }
}

extension AgentSessionOption {
    var isGenerationOption: Bool {
        let key = (id + " " + category).lowercased()
        guard category != "mode", category != "model", !key.contains("permission"), !key.contains("approval") else { return false }
        return ["thought", "think", "reason", "effort", "fast", "speed"].contains { key.contains($0) }
    }
}
