import Foundation
import PaperCore

extension AIConfiguration {
    var isAvailable: Bool {
        if backend.usesCLI {
            let path = backend == .codex ? codexPath : agentPath
            return FileManager.default.isExecutableFile(atPath: (path as NSString).expandingTildeInPath)
        }
        return !model.isEmpty && (backend == .localHTTP || !key.isEmpty)
    }
    func makeProvider() throws -> any AIProvider {
        let provider: any AIProvider
        if self.backend == .codex {
            let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-AI", isDirectory: true)
            try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
            provider = CodexAIProvider(executable: self.codexPath, model: self.model, cwd: cwd, effort: self.effort, fastMode: self.fastMode)
        } else if self.backend == .claudeCode {
            provider = ClaudeCodeProvider(executable: self.agentPath, model: self.model, effort: self.effort, fastMode: self.fastMode)
        } else if self.backend.usesACP {
            provider = ACPAgentProvider(executable: self.agentPath, backend: self.backend, model: self.model, selections: self.agentSelections)
        } else {
            guard let base = URL(string: self.endpoint) else { throw AIError.message(L("无效的模型服务地址。")) }
            provider = CloudAIProvider(baseURL: base, model: self.model, key: self.backend == .cloud ? self.key : "", reasoningEffort: self.effort)
        }
        return provider
    }
}
