import Foundation
import PaperCore

struct ClaudeCodeProvider: AIProvider {
    let executable: String
    let model: String
    let effort: String
    let fastMode: Bool
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let rpc = CodexRPC(), completion = CodexTurnCompletion()
            let output = ClaudeStreamOutput()
            let task = Task {
                var bridge: ResearchMCPBridge?
                var cwd: URL?
                do {
                    let directory = try AgentWorkingDirectory.create(); cwd = directory
                    let mcp = try ResearchMCPBridge.start(request); bridge = mcp
                    var arguments = ["--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                        "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", mcp.claudeConfiguration,
                        "--allowedTools", "mcp__paper-reader__*", "--permission-mode", "dontAsk", "--disable-slash-commands", "--no-chrome",
                        "--setting-sources", "user", "--settings", JSONValue.object(["disableAllHooks": .bool(true), "enabledPlugins": .object([:]), "fastMode": .bool(fastMode)]).text]
                    if !model.isEmpty { arguments += ["--model", model] }
                    if !effort.isEmpty { arguments += ["--effort", effort] }
                    try await rpc.start(executable: executable, cwd: directory, arguments: arguments, isolatedDirectories: [directory, mcp.directory])
                    await rpc.configure(events: { method, message in
                        if method == "connection/closed" { await completion.finish(error: AIError.message(message["message"].string ?? L("Agent 连接已关闭，请检查程序路径与登录状态。"))); return }
                        guard method == "stream/message" else { return }
                        if message["type"].string == "stream_event", let text = message["event"]["delta"]["text"].string {
                            await output.append(text); continuation.yield(.text(text))
                        }
                        if message["type"].string == "result" {
                            if message["is_error"] == .bool(true) {
                                await completion.finish(error: AIError.message(message["result"].string ?? message["errors"].array.compactMap(\.string).joined(separator: "\n")))
                            } else {
                                if await output.isEmpty, let text = message["result"].string { continuation.yield(.text(text)) }
                                await completion.finish(error: nil)
                            }
                        }
                    }, tools: request.handleTool)
                    let system = request.messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
                    var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(system + "\n\n" + request.messages.filter { $0.role != "system" }.map { "\($0.role.uppercased()):\n\($0.contextContent)" }.joined(separator: "\n\n"))])]
                    content += request.images.map { .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string($0.mimeType), "data": .string($0.data.base64EncodedString())])]) }
                    let input = JSONValue.object(["type": .string("user"), "message": .object(["role": .string("user"), "content": .array(content)])])
                    try await rpc.writeInput(Data((input.text + "\n").utf8))
                    await rpc.closeInput()
                    try await withTaskCancellationHandler { try await completion.wait() } onCancel: {
                        Task { await rpc.stop(); await completion.finish(error: CancellationError()) }
                    }
                    await rpc.stop(); await mcp.stop()
                    try? FileManager.default.removeItem(at: directory)
                    continuation.finish()
                } catch {
                    await rpc.stop(); await bridge?.stop()
                    if let cwd { try? FileManager.default.removeItem(at: cwd) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel(); Task { await rpc.stop(); await completion.finish(error: CancellationError()) } }
        }
    }
}
private actor ClaudeStreamOutput {
    private var count = 0
    var isEmpty: Bool { count == 0 }
    func append(_ text: String) { count += text.count }
}
