import Foundation
import Observation

public enum WorktreeStatus: String {
    case creating
    case idle
    case running
    case error
    case done
    case deleting
}

@Observable
public final class Worktree: Identifiable {
    public var id: String { branch }
    public var branch: String
    public var path: String
    public var status: WorktreeStatus
    public var conversations: [Conversation]
    public var activeConversationID: UUID?
    public var prNumber: Int?
    public var ciStatus: CIStatus?
    public var prStatus: PRStatus?
    public var ciLogsPaths: [String: String] = [:]  // check name -> log file path
    public var ciLogsFetching = false

    // Remote mode
    public var isRemote: Bool
    public var workspaceName: String?
    /// Optional browser URL for the remote workspace (e.g. a web IDE or
    /// dashboard). Populated from `FLIGHT_OUTPUT: url=...` lines the
    /// provision script emits on stdout.
    public var remoteURL: String?
    /// Path to the repo checkout on the remote workspace, used to open
    /// the worktree in VS Code Remote-SSH. Populated from
    /// `FLIGHT_OUTPUT: repo_path=...`.
    public var remoteRepoPath: String?
    /// SSH-Remote target string for VS Code Remote-SSH (the value that
    /// follows `--remote ssh-remote+`). For Coder this is typically
    /// `coder.<workspace>`; for raw SSH it might be `user@host`.
    /// Populated from `FLIGHT_OUTPUT: ssh_target=...`.
    public var remoteSSHTarget: String?

    public var activeConversation: Conversation? {
        conversations.first { $0.id == activeConversationID }
    }

    public var anyAgentBusy: Bool {
        conversations.contains { $0.agentBusy }
    }

    public var anyAgentRunning: Bool {
        conversations.contains { $0.agent?.isRunning == true }
    }

    public init(
        branch: String,
        path: String,
        status: WorktreeStatus = .idle,
        prNumber: Int? = nil,
        isRemote: Bool = false,
        workspaceName: String? = nil
    ) {
        self.branch = branch
        self.path = path
        self.status = status
        self.conversations = []
        self.prNumber = prNumber
        self.isRemote = isRemote
        self.workspaceName = workspaceName
    }

    @discardableResult
    public func ensureConversation() -> Conversation {
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

public struct WorktreeConfig: Codable {
    public let branch: String
    public let path: String
    public var prNumber: Int?
    public var isRemote: Bool?
    public var workspaceName: String?
    public var remoteURL: String?
    public var remoteRepoPath: String?
    public var remoteSSHTarget: String?
    public var conversations: [ConversationConfig]?
    public var activeConversationID: UUID?

    public init(from worktree: Worktree) {
        self.branch = worktree.branch
        self.path = worktree.path
        self.prNumber = worktree.prNumber
        self.isRemote = worktree.isRemote
        self.workspaceName = worktree.workspaceName
        self.remoteURL = worktree.remoteURL
        self.remoteRepoPath = worktree.remoteRepoPath
        self.remoteSSHTarget = worktree.remoteSSHTarget
        self.conversations = worktree.conversations.map { ConversationConfig(from: $0) }
        self.activeConversationID = worktree.activeConversationID
    }

    public func toWorktree() -> Worktree {
        let wt = Worktree(
            branch: branch, path: path,
            prNumber: prNumber,
            isRemote: isRemote ?? false, workspaceName: workspaceName
        )
        wt.remoteURL = remoteURL
        wt.remoteRepoPath = remoteRepoPath
        wt.remoteSSHTarget = remoteSSHTarget

        if let convConfigs = conversations, !convConfigs.isEmpty {
            wt.conversations = convConfigs.map {
                $0.toConversation(worktreePath: path, isRemote: isRemote ?? false)
            }
            wt.activeConversationID = activeConversationID ?? wt.conversations.first?.id
        }

        return wt
    }
}
