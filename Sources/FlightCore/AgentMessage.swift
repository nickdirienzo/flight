import Foundation

public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

public enum MessageContent: Codable, Equatable {
    case text(String)
    case toolUse(name: String, input: String)
    case toolResult(content: String)
    case permissionRequest(requestID: String, description: String)
    case provisionLog(String)
    case setupLog(String)
}

public struct AgentMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public let content: MessageContent
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: MessageContent,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    public var textContent: String {
        switch content {
        case .text(let text):
            return text
        case .toolUse(let name, let input):
            return "[\(name)] \(input)"
        case .toolResult(let content):
            return content
        case .permissionRequest(_, let description):
            return description
        case .provisionLog(let line):
            return line
        case .setupLog(let line):
            return line
        }
    }

    public var isToolUse: Bool {
        if case .toolUse = content { return true }
        return false
    }

    public var isToolResult: Bool {
        if case .toolResult = content { return true }
        return false
    }

    public var isPermissionRequest: Bool {
        if case .permissionRequest = content { return true }
        return false
    }

    public var isProvisionLog: Bool {
        if case .provisionLog = content { return true }
        return false
    }

    public var isSetupLog: Bool {
        if case .setupLog = content { return true }
        return false
    }

    public var planContent: String? {
        guard case .toolUse(let name, let input) = content else { return nil }
        guard let data = input.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // ExitPlanMode has "plan" field
        if name == "ExitPlanMode", let plan = dict["plan"] as? String {
            return plan
        }

        // Write to .claude/plans/ has "content" field
        if name == "Write",
           let path = dict["file_path"] as? String,
           path.contains(".claude/plans/"),
           let content = dict["content"] as? String {
            return content
        }

        return nil
    }

    public var toolName: String? {
        guard case .toolUse(let name, _) = content else { return nil }
        return name
    }

    public var toolDescription: String? {
        guard case .toolUse(_, let input) = content,
              let data = input.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = dict["description"] as? String else {
            return nil
        }
        return desc
    }
}
