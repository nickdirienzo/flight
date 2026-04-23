import Foundation
import Observation

/// Effort level passed to `claude --effort`. `nil` case defers to the CLI default.
public enum ConversationEffort: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case xhigh
    case max
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra High"
        case .max: return "Max"
        }
    }
}

/// A message the user submitted before the worktree finished provisioning.
/// Held on the conversation until the real (possibly remote) agent spawns,
/// then flushed through `agent.send`.
public struct PendingSend {
    public let text: String
    public let images: [Data]

    public init(text: String, images: [Data]) {
        self.text = text
        self.images = images
    }
}

@Observable
public final class Conversation: Identifiable {
    public let id: UUID
    public var name: String
    public private(set) var messages: [AgentMessage]
    public private(set) var sections: [ChatSection] = []
    public var sessionID: String?
    public var agentBusy: Bool = false
    public var planMode: Bool = false
    /// Raw `claude --model` ID (e.g. "claude-opus-4-6[1m]"). `nil` = CLI default.
    public var modelID: String?
    public var effort: ConversationEffort?
    public var agent: ClaudeAgent?
    public var pendingSend: PendingSend?

    /// True while the session has been handed off to an interactive remote
    /// `claude` process (visible in the mobile app). Flight should sync the
    /// transcript before resuming its own `-p` turns.
    public var remoteSessionActive: Bool = false

    /// Number of local messages at the moment the remote session was opened.
    /// Used to detect which messages in the remote transcript are "new".
    public var handoffMessageCount: Int?

    public init(
        id: UUID = UUID(),
        name: String = "Chat",
        sessionID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.messages = []
        self.sessionID = sessionID
    }

    // MARK: - Message Mutation (always rebuilds sections)

    public func appendMessage(_ message: AgentMessage) {
        messages.append(message)
        sections = ChatSection.build(from: messages)
    }

    public func appendMessages(_ newMessages: [AgentMessage]) {
        messages.append(contentsOf: newMessages)
        sections = ChatSection.build(from: messages)
    }

    public func setMessages(_ newMessages: [AgentMessage]) {
        messages = newMessages
        sections = ChatSection.build(from: messages)
    }

    public func clearMessages() {
        messages.removeAll()
        sections = []
    }
}

public struct ConversationConfig: Codable {
    public let id: UUID
    public var name: String
    public var sessionID: String?
    public var remoteSessionActive: Bool?
    public var handoffMessageCount: Int?
    public var modelID: String?
    public var effort: ConversationEffort?

    public init(from conversation: Conversation) {
        self.id = conversation.id
        self.name = conversation.name
        self.sessionID = conversation.sessionID
        self.remoteSessionActive = conversation.remoteSessionActive ? true : nil
        self.handoffMessageCount = conversation.handoffMessageCount
        self.modelID = conversation.modelID
        self.effort = conversation.effort
    }

    public func toConversation(worktreePath: String, isRemote: Bool) -> Conversation {
        let conv = Conversation(id: id, name: name, sessionID: sessionID)
        conv.setMessages(ConversationHistory.hydrate(
            conversationID: id,
            worktreePath: worktreePath,
            sessionID: sessionID,
            isRemote: isRemote
        ))
        conv.remoteSessionActive = remoteSessionActive ?? false
        conv.handoffMessageCount = handoffMessageCount
        conv.modelID = modelID
        conv.effort = effort
        return conv
    }
}
