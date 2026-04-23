import Foundation

// MARK: - Stream JSON Parsing

public struct StreamEvent: Decodable {
    public let type: String
    public let subtype: String?
    public let message: StreamMessage?
    public let result: String?
    public let sessionID: String?
    public let requestID: String?
    public let request: ControlRequest?

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, result, request
        case sessionID = "session_id"
        case requestID = "request_id"
    }

    public struct ControlRequest: Decodable {
        public let subtype: String?
        public let toolName: String?
        public let description: String?
        public let input: [String: AnyCodable]?

        enum CodingKeys: String, CodingKey {
            case subtype, description, input
            case toolName = "tool_name"
        }
    }

    public struct StreamMessage: Decodable {
        public let role: String?
        public let content: StreamContent?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decodeIfPresent(String.self, forKey: .role)
            // content can be a string or an array of content blocks
            if let contentString = try? container.decode(String.self, forKey: .content) {
                content = .text(contentString)
            } else if let blocks = try? container.decode([ContentBlock].self, forKey: .content) {
                content = .blocks(blocks)
            } else {
                content = nil
            }
        }

        enum CodingKeys: String, CodingKey {
            case role, content
        }
    }

    public enum StreamContent {
        case text(String)
        case blocks([ContentBlock])
    }

    public struct ContentBlock: Decodable {
        public let type: String
        public let text: String?
        public let name: String?
        public let input: AnyCodable?
        public let content: String?
    }
}

// Lightweight wrapper to decode arbitrary JSON values
public struct AnyCodable: Decodable {
    public let value: Any

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = "<unknown>"
        }
    }

    public var jsonString: String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: value)
    }
}

extension StreamEvent {
    public func toAgentMessages() -> [AgentMessage] {
        // Skip non-chat events
        if type == "system" || type == "rate_limit_event" || type == "result" { return [] }

        guard let message = message else { return [] }

        // Skip user messages from stream — we add those locally in send()
        if message.role == "user" || type == "user" { return [] }

        let role: MessageRole = .assistant

        guard let content = message.content else { return [] }

        switch content {
        case .text(let text):
            return [AgentMessage(role: role, content: .text(text))]
        case .blocks(let blocks):
            return blocks.compactMap { block in
                switch block.type {
                case "text":
                    guard let text = block.text, !text.isEmpty else { return nil }
                    return AgentMessage(role: role, content: .text(text))
                case "tool_use":
                    let name = block.name ?? "unknown"
                    let input = block.input?.jsonString ?? "{}"
                    return AgentMessage(role: role, content: .toolUse(name: name, input: input))
                case "tool_result":
                    let resultContent = block.content ?? block.text ?? ""
                    return AgentMessage(role: role, content: .toolResult(content: resultContent))
                default:
                    return nil
                }
            }
        }
    }
}
