import Foundation

enum WorktreeStatus: String {
    case creating
    case idle
    case running
    case error
    case done
}

@Observable
final class Worktree: Identifiable {
    let id: UUID
    var branch: String
    var path: String
    var status: WorktreeStatus
    var conversations: [Conversation]
    var activeConversationID: UUID?
    var prNumber: Int?
    var ciStatus: CIStatus?

    // Remote mode
    var isRemote: Bool
    var workspaceName: String?

    var activeConversation: Conversation? {
        conversations.first { $0.id == activeConversationID }
    }

    /// Whether any conversation in this worktree has a busy agent
    var anyAgentBusy: Bool {
        conversations.contains { $0.agentBusy }
    }

    /// Whether any conversation has a running agent
    var anyAgentRunning: Bool {
        conversations.contains { $0.agent?.isRunning == true }
    }

    init(
        id: UUID = UUID(),
        branch: String,
        path: String,
        status: WorktreeStatus = .idle,
        prNumber: Int? = nil,
        isRemote: Bool = false,
        workspaceName: String? = nil
    ) {
        self.id = id
        self.branch = branch
        self.path = path
        self.status = status
        self.conversations = []
        self.prNumber = prNumber
        self.isRemote = isRemote
        self.workspaceName = workspaceName
    }

    /// Ensure at least one conversation exists, creating a default if needed
    @discardableResult
    func ensureConversation() -> Conversation {
        if let active = activeConversation { return active }
        if let first = conversations.first {
            activeConversationID = first.id
            return first
        }
        let conv = Conversation()
        conversations.append(conv)
        activeConversationID = conv.id
        return conv
    }
}

struct WorktreeConfig: Codable {
    let id: UUID
    let branch: String
    let path: String
    var prNumber: Int?
    var isRemote: Bool?
    var workspaceName: String?
    var conversations: [ConversationConfig]?
    var activeConversationID: UUID?

    // Legacy field for migration
    var sessionID: String?

    init(from worktree: Worktree) {
        self.id = worktree.id
        self.branch = worktree.branch
        self.path = worktree.path
        self.prNumber = worktree.prNumber
        self.isRemote = worktree.isRemote
        self.workspaceName = worktree.workspaceName
        self.conversations = worktree.conversations.map { ConversationConfig(from: $0) }
        self.activeConversationID = worktree.activeConversationID
        self.sessionID = nil
    }

    func toWorktree() -> Worktree {
        let wt = Worktree(
            id: id, branch: branch, path: path,
            prNumber: prNumber,
            isRemote: isRemote ?? false, workspaceName: workspaceName
        )

        if let convConfigs = conversations, !convConfigs.isEmpty {
            wt.conversations = convConfigs.map { $0.toConversation() }
            wt.activeConversationID = activeConversationID ?? wt.conversations.first?.id
        } else if let legacySessionID = sessionID {
            // Migrate old single-session worktree to a conversation
            let conv = Conversation(name: "Chat", sessionID: legacySessionID)
            conv.messages = ConfigService.loadMessages(conversationID: id) // try legacy ID
            wt.conversations = [conv]
            wt.activeConversationID = conv.id
        } else {
            // No conversations yet — will be created on demand
        }

        return wt
    }
}
