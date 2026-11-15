import Foundation
import PaperCore

/// ACP v1 over newline-delimited JSON-RPC. File-system and terminal client capabilities are denied.
struct ACPAgentProvider: AIProvider {
    let executable: String
    let backend: AIBackend
    let model: String
    let selections: [String: String]
    struct Catalog: Sendable {
        let models: [String]
        let options: [AgentSessionOption]
    }
    static func catalog(executable: String, backend: AIBackend, model: String) async throws -> Catalog {
        let rpc = CodexRPC(), cwd = try AgentWorkingDirectory.create()
        do {
            try await rpc.start(executable: executable, cwd: cwd, arguments: backend.launchArguments, isolatedDirectories: [cwd])
            try await initialize(rpc)
            var session = try await rpc.request("session/new", .object(["cwd": .string(cwd.path), "mcpServers": .array([])]))
            if !model.isEmpty, let id = session["sessionId"].string {
                if let option = AgentSessionOption.parse(session["configOptions"]).first(where: { $0.category == "model" }) {
                    let updated = try await rpc.request("session/set_config_option", .object(["sessionId": .string(id), "configId": .string(option.id), "value": .string(model)]))
                    var value = session.object
                    value["configOptions"] = updated["configOptions"]
                    session = .object(value)
                } else { _ = try await rpc.request("session/set_model", .object(["sessionId": .string(id), "modelId": .string(model)])) }
            }
            let options = AgentSessionOption.parse(session["configOptions"])
            let models = options.first(where: { $0.category == "model" })?.choices.map(\.value)
                ?? session["models"]["availableModels"].array.compactMap { $0["modelId"].string }
            await rpc.stop()
            try? FileManager.default.removeItem(at: cwd)
            return .init(models: models, options: options)
        } catch {
            await rpc.stop()
            try? FileManager.default.removeItem(at: cwd)
            throw error
        }
    }
    static func initialize(_ rpc: CodexRPC) async throws {
        _ = try await rpc.request("initialize", .object(["protocolVersion": .number(1),
            "clientInfo": .object(["name": .string("paper-reader"), "version": .string("1.0")]),
            "clientCapabilities": .object(["fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]), "terminal": .bool(false)])]))
    }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let rpc = CodexRPC()
            let task = Task {
                var bridge: ResearchMCPBridge?
                var cwd: URL?
                do {
                    let directory = try AgentWorkingDirectory.create(); cwd = directory
                    let mcp = try ResearchMCPBridge.start(request); bridge = mcp
                    try await rpc.start(executable: executable, cwd: directory, arguments: backend.launchArguments, isolatedDirectories: [directory, mcp.directory])
                    await rpc.configure(events: { method, params in
                        guard method == "session/update" else { return }
                        let update = params["update"]
                        if update["sessionUpdate"].string == "agent_message_chunk", let text = update["content"]["text"].string { continuation.yield(.text(text)) }
                    }, tools: request.handleTool)
                    await rpc.configureServerRequests { method, params in
                        guard method == "session/request_permission" else { throw AIError.message(L("工具未获授权。")) }
                        // MCP calls are independently validated by ResearchMCPBridge before execution.
                        // All agent-native requests, including shell and file editing, are rejected.
                        let title = params["toolCall"]["title"].string ?? ""
                        let isResearchTool = request.tools.contains { title == "mcp__paper-reader__\($0.name)" || title == "paper-reader/\($0.name)" }
                        if isResearchTool, let option = params["options"].array.first(where: { $0["kind"].string == "allow_once" })?["optionId"].string {
                            return .object(["outcome": .object(["outcome": .string("selected"), "optionId": .string(option)])])
                        }
                        return .object(["outcome": .object(["outcome": .string("cancelled")])])
                    }
                    try await Self.initialize(rpc)
                    let session = try await rpc.request("session/new", .object(["cwd": .string(directory.path), "mcpServers": .array([mcp.server])]))
                    guard let id = session["sessionId"].string else { throw AIError.message(L("Agent 返回了无效的会话。")) }
                    var options = AgentSessionOption.parse(session["configOptions"])
                    if !model.isEmpty {
                        if let option = options.first(where: { $0.category == "model" }) {
                            let updated = try await rpc.request("session/set_config_option", .object(["sessionId": .string(id), "configId": .string(option.id), "value": .string(model)]))
                            options = AgentSessionOption.parse(updated["configOptions"])
                        } else {
                            _ = try await rpc.request("session/set_model", .object(["sessionId": .string(id), "modelId": .string(model)]))
                        }
                    }
                    for option in options where option.isGenerationOption {
                        guard let selected = selections[option.id], selected != option.currentValue else { continue }
                        guard option.choices.contains(where: { $0.value == selected }) else { throw AIError.message(L("当前 Agent 或模型不支持已选择的选项，请重新读取模型。")) }
                        _ = try await rpc.request("session/set_config_option", .object(["sessionId": .string(id), "configId": .string(option.id), "value": .string(selected)]))
                    }
                    let prompt = request.messages.map { "\($0.role.uppercased()):\n\($0.contextContent)" }.joined(separator: "\n\n")
                    var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(prompt)])]
                    content += request.images.map { .object(["type": .string("image"), "mimeType": .string($0.mimeType), "data": .string($0.data.base64EncodedString())]) }
                    let result = try await rpc.request("session/prompt", .object(["sessionId": .string(id), "prompt": .array(content)]), timeout: 300)
                    if result["stopReason"].string == "cancelled" { throw CancellationError() }
                    await rpc.stop()
                    await mcp.stop()
                    try? FileManager.default.removeItem(at: directory)
                    continuation.finish()
                } catch {
                    await rpc.stop()
                    await bridge?.stop()
                    if let cwd { try? FileManager.default.removeItem(at: cwd) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel(); Task { await rpc.stop() } }
        }
    }
}

enum AgentWorkingDirectory {
    static func create() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-Agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
}
