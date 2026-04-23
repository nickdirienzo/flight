import Foundation
import FlightCore

/// In-memory registry of worktrees the server has provisioned. Each entry
/// wraps one `git worktree` Flight has cut; the HTTP routes reference them
/// by `id` (the branch name). Chat turns look up the session here to find
/// the worktree path to cd into and the claude session ID to `--resume`.
///
/// Sessions are process-scoped. A server restart re-scans `~/flight/config.json`
/// via `ConfigService.load()` to rebuild the active set from on-disk
/// worktrees — claude's own jsonl continues to hold the transcript.
actor SessionStore {
    struct Session: Codable, Sendable {
        /// Opaque handle for HTTP callers. We use the branch because it's
        /// unique per repo and URL-safe for the caller to slot into paths.
        let id: String
        let repoPath: String
        let branch: String
        let worktreePath: String
        var claudeSessionID: String?

        init(id: String, repoPath: String, branch: String, worktreePath: String, claudeSessionID: String? = nil) {
            self.id = id
            self.repoPath = repoPath
            self.branch = branch
            self.worktreePath = worktreePath
            self.claudeSessionID = claudeSessionID
        }
    }

    private var sessions: [String: Session] = [:]

    func add(_ session: Session) {
        sessions[session.id] = session
    }

    func get(_ id: String) -> Session? {
        sessions[id]
    }

    func list() -> [Session] {
        Array(sessions.values).sorted { $0.branch < $1.branch }
    }

    func updateClaudeSession(id: String, claudeSessionID: String) {
        sessions[id]?.claudeSessionID = claudeSessionID
    }

    func remove(_ id: String) {
        sessions.removeValue(forKey: id)
    }

    /// Rebuild the session set from on-disk Flight config at startup. Only
    /// local worktrees are eligible — remote worktrees need the .flight/connect
    /// wrapper that's project-scoped, not server-scoped.
    func hydrateFromConfig() {
        let config = ConfigService.load()
        for projectConfig in config.projects {
            guard let repoPath = projectConfig.path else { continue }
            for wt in projectConfig.worktreeConfigs where wt.isRemote != true {
                let session = Session(
                    id: wt.branch,
                    repoPath: repoPath,
                    branch: wt.branch,
                    worktreePath: wt.path,
                    claudeSessionID: wt.conversations?.first?.sessionID
                )
                sessions[session.id] = session
            }
        }
    }
}
