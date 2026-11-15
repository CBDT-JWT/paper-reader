import Foundation
import PaperCore

/// A private, per-turn stdio MCP bridge. Agents receive only the app's bounded research tools.
/// Atomic mailbox files stay in a mode-0700 temporary directory and are removed at turn end.
struct ResearchMCPBridge: Sendable {
    let directory: URL
    private let worker: Task<Void, Never>
    var server: JSONValue {
        .object(["name": .string("paper-reader"), "command": .string(Bundle.main.executablePath ?? CommandLine.arguments[0]),
                 "args": .array([.string("--research-mcp")]),
                 "env": .array([.object(["name": .string("PAPER_READER_MCP_MAILBOX"), "value": .string(directory.path)])])])
    }
    var claudeConfiguration: String {
        var value = server.object
        value.removeValue(forKey: "name")
        value["env"] = .object(["PAPER_READER_MCP_MAILBOX": .string(directory.path)])
        return JSONValue.object(["mcpServers": .object(["paper-reader": .object(value)])]).text
    }
    static func start(_ request: AIRequest) throws -> ResearchMCPBridge {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperReader-MCP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let worker = Task.detached {
            do {
                while !Task.isCancelled {
                    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    for file in files where file.lastPathComponent.hasSuffix(".request.json") {
                        try Task.checkCancellation()
                        let message = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
                        let response: JSONValue
                        do {
                            let result = try await result(for: message, request: request)
                            response = .object(["jsonrpc": .string("2.0"), "id": message["id"], "result": result])
                        } catch {
                            response = .object(["jsonrpc": .string("2.0"), "id": message["id"], "error": .object(["code": .number(-32603), "message": .string(error.localizedDescription)])])
                        }
                        try Task.checkCancellation()
                        let output = directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of: ".request.json", with: ".response.json"))
                        try JSONEncoder().encode(response).write(to: output, options: .atomic)
                        try FileManager.default.removeItem(at: file)
                    }
                    try await Task.sleep(for: .milliseconds(30))
                }
            } catch { /* Cancellation or removal closes the turn-scoped mailbox. */ }
        }
        return .init(directory: directory, worker: worker)
    }
    func stop() async {
        worker.cancel()
        await worker.value
        try? FileManager.default.removeItem(at: directory)
    }
    private static func result(for message: JSONValue, request: AIRequest) async throws -> JSONValue {
        switch message["method"].string {
        case "initialize":
            return .object(["protocolVersion": message["params"]["protocolVersion"], "capabilities": .object(["tools": .object([:])]),
                            "serverInfo": .object(["name": .string("Paper Reader"), "version": .string("1.0")])])
        case "ping": return .object([:])
        case "tools/list":
            return .object(["tools": .array(request.tools.map { .object(["name": .string($0.name), "description": .string($0.description), "inputSchema": $0.schema]) })])
        case "tools/call":
            let params = message["params"]
            guard let name = params["name"].string, request.tools.contains(where: { $0.name == name }) else { throw AIError.message(L("工具未获授权。")) }
            do {
                let result = try await request.handleTool(.init(name: name, arguments: params["arguments"]))
                var value = result.object
                let image = value.removeValue(forKey: "imageDataURL")?.string
                var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(image == nil ? result.text : JSONValue.object(value).text)])]
                if let image, let comma = image.firstIndex(of: ",") {
                    let mime = String(image.dropFirst(5).prefix(while: { $0 != ";" }))
                    content.append(.object(["type": .string("image"), "mimeType": .string(mime), "data": .string(String(image[image.index(after: comma)...]))]))
                }
                return .object(["content": .array(content), "isError": .bool(false)])
            } catch {
                return .object(["content": .array([.object(["type": .string("text"), "text": .string(error.localizedDescription)])]), "isError": .bool(true)])
            }
        default: throw AIError.message("Unsupported MCP method")
        }
    }
    /// Runs only in a separate helper invocation, before SwiftUI creates an application.
    static func runHelper() -> Int32 {
        guard let path = ProcessInfo.processInfo.environment["PAPER_READER_MCP_MAILBOX"] else { return 1 }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        while let line = readLine() {
            do {
                let message = try JSONValue.parse(line)
                guard message.object["id"] != nil else { continue }
                let id = UUID().uuidString
                let input = directory.appendingPathComponent(id + ".request.json")
                let output = directory.appendingPathComponent(id + ".response.json")
                try Data(line.utf8).write(to: input, options: .atomic)
                let deadline = Date().addingTimeInterval(300)
                while !FileManager.default.fileExists(atPath: output.path) {
                    guard Date() < deadline, FileManager.default.fileExists(atPath: directory.path) else { return 1 }
                    Thread.sleep(forTimeInterval: 0.02)
                }
                var data = try Data(contentsOf: output)
                try FileManager.default.removeItem(at: output)
                data.append(10)
                try FileHandle.standardOutput.write(contentsOf: data)
            } catch { return 1 }
        }
        return 0
    }
}
