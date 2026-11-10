import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }
    public var object: [String: JSONValue] { if case .object(let o) = self { return o }; return [:] }
    public var text: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "null" }
    public static func parse(_ text: String) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: Data(text.utf8)) }
}
public struct AIMessage: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var role: String
    public var content: String
    public var date: Date
    public init(id: UUID = UUID(), role: String, content: String, date: Date = .now) { self.id = id; self.role = role; self.content = content; self.date = date }
}
public struct AITool: Sendable {
    public let name: String; public let description: String; public let schema: JSONValue
    public init(_ name: String, _ description: String, properties: [String: JSONValue] = [:], required: [String] = []) {
        self.name = name; self.description = description
        self.schema = .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])
    }
}
public struct AIToolCall: Sendable { public var name: String; public var arguments: JSONValue; public init(name: String, arguments: JSONValue) { self.name = name; self.arguments = arguments } }
public enum AIEvent: Sendable { case text(String), status(String) }
public struct AIImage: Sendable {
    public let data: Data
    public let mimeType: String
    public init(data: Data, mimeType: String = "image/png") { self.data = data; self.mimeType = mimeType }
    public var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}
public struct AIRequest: Sendable {
    public let images: [AIImage]
    public let messages: [AIMessage]
    public let tools: [AITool]
    public let handleTool: @Sendable (AIToolCall) async throws -> JSONValue
    public init(messages: [AIMessage], images: [AIImage] = [], tools: [AITool], handleTool: @escaping @Sendable (AIToolCall) async throws -> JSONValue) { self.messages = messages; self.images = images; self.tools = tools; self.handleTool = handleTool }
}
public protocol AIProvider: Sendable { func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> }
public enum AIError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// OpenAI-compatible chat-completions transport, also usable with a local HTTP inference server.
public struct CloudAIProvider: AIProvider {
    public let baseURL: URL
    public let model: String
    private let key: String
    public init(baseURL: URL, model: String, key: String) { self.baseURL = baseURL; self.model = model; self.key = key }
    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do { try await run(request, continuation: continuation); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private func run(_ request: AIRequest, continuation: AsyncThrowingStream<AIEvent, Error>.Continuation) async throws {
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.host != nil, baseURL.scheme == "https" || baseURL.scheme == "http" && local, !model.isEmpty else { throw AIError.message(L("请配置有效的模型和 HTTPS 服务地址。")) }
        var messages = request.messages.map { JSONValue.object(["role": .string($0.role), "content": .string($0.content)]) }
        if !request.images.isEmpty, let last = messages.indices.last {
            messages[last] = .object(["role": .string("user"), "content": .array([.object(["type": .string("text"), "text": .string(request.messages.last?.content ?? "")])] + request.images.map { .object(["type": .string("image_url"), "image_url": .object(["url": .string($0.dataURL), "detail": .string("high")])]) })])
        }
        for _ in 0..<10 {
            try Task.checkCancellation()
            var body: [String: JSONValue] = ["model": .string(model), "messages": .array(messages), "stream": .bool(true)]
            if !request.tools.isEmpty { body["tools"] = .array(request.tools.map { .object(["type": .string("function"), "function": .object(["name": .string($0.name), "description": .string($0.description), "parameters": $0.schema])]) }) }
            var call = URLRequest(url: baseURL.appendingPathComponent("chat/completions")); call.httpMethod = "POST"; call.timeoutInterval = 180
            call.setValue("application/json", forHTTPHeaderField: "Content-Type"); call.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if !key.isEmpty { call.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            call.httpBody = try JSONEncoder().encode(JSONValue.object(body))
            let (bytes, response) = try await URLSession.shared.bytes(for: call)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIError.message(L("模型服务请求失败，HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)。请检查配置与账户权限。")) }
            var text = "", calls: [Int: (id: String, name: String, arguments: String)] = [:]
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if data == "[DONE]" { break }
                let event = try JSONValue.parse(data)
                if let error = event["error"]["message"].string { throw AIError.message(error) }
                let delta = event["choices"].array.first?["delta"] ?? .null
                if let part = delta["content"].string { text += part; continuation.yield(.text(part)) }
                for entry in delta["tool_calls"].array {
                    let index = Int(entry["index"].number ?? 0)
                    var stored = calls[index] ?? ("", "", "")
                    stored.id += entry["id"].string ?? ""; stored.name += entry["function"]["name"].string ?? ""; stored.arguments += entry["function"]["arguments"].string ?? ""
                    calls[index] = stored
                }
            }
            guard !calls.isEmpty else { return }
            let ordered = calls.keys.sorted().compactMap { calls[$0] }
            messages.append(.object(["role": .string("assistant"), "content": .string(text), "tool_calls": .array(ordered.map { .object(["id": .string($0.id), "type": .string("function"), "function": .object(["name": .string($0.name), "arguments": .string($0.arguments)])]) })]))
            var toolImages: [String] = []
            for tool in ordered {
                guard request.tools.contains(where: { $0.name == tool.name }) else { throw AIError.message(L("模型请求了未经授权的工具。")) }
                continuation.yield(.status(tool.name))
                let result: JSONValue
                do { result = try await request.handleTool(AIToolCall(name: tool.name, arguments: try JSONValue.parse(tool.arguments))) }
                catch { result = .object(["error": .string(error.localizedDescription)]) }
                var value = result.object
                let image = value.removeValue(forKey: "imageDataURL")?.string
                messages.append(.object(["role": .string("tool"), "tool_call_id": .string(tool.id), "content": .string(image == nil ? result.text : JSONValue.object(value).text)]))
                if let image { toolImages.append(image) }
            }
            if !toolImages.isEmpty {
                let content: [JSONValue] = [.object(["type": .string("text"), "text": .string("Verified PDF page images returned by research tools.")])] + toolImages.map { .object(["type": .string("image_url"), "image_url": .object(["url": .string($0), "detail": .string("high")])]) }
                messages.append(.object(["role": .string("user"), "content": .array(content)]))
            }
        }
        throw AIError.message(L("工具调用次数已达到限制，请缩小问题范围。"))
    }
}
public extension JSONValue { var number: Double? { if case .number(let n) = self { return n }; return nil } }
