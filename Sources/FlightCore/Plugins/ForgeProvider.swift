import Foundation

// MARK: - Forge Provider Protocol

/// A forge is a git hosting platform that manages pull requests and CI.
/// Implementations wrap platform-specific CLIs or APIs (gh, tea, curl, etc.)
/// and bake the repo location (local path or owner/repo) in at construction
/// time, so call sites don't need to juggle paths.
public protocol ForgeProvider {
    /// Human-readable name for UI display (e.g. "GitHub", "Forgejo")
    var displayName: String { get }

    /// Gets CI check status for a PR.
    func getChecks(prNumber: Int) async throws -> [CICheck]

    /// Gets failed CI logs for a PR's latest run.
    func getFailedLogs(prNumber: Int) async throws -> String

    /// Gets PR review status (reviews, review decision).
    func getPRStatus(prNumber: Int) async throws -> PRStatus

    /// Looks up the PR number for a branch. Returns nil if no PR exists.
    func getPRNumber(branch: String) async -> Int?
}

// MARK: - Forge Type

public enum ForgeType: String, Codable, CaseIterable, Identifiable {
    case github
    case forgejo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .forgejo: return "Forgejo"
        }
    }

    /// Creates a provider for a locally cloned repo. Uses `gh` in the repo
    /// directory (for GitHub) or parses `origin` (for Forgejo).
    public func makeLocalProvider(config: ForgeConfig, repoPath: String) -> ForgeProvider {
        switch self {
        case .github:
            return LocalGitHubForge(repoPath: repoPath)
        case .forgejo:
            return LocalForgejoForge(
                repoPath: repoPath,
                baseURL: config.baseURL ?? "http://localhost:3000",
                tokenEnvVar: config.tokenEnvVar
            )
        }
    }

    /// Creates a provider for a remote-only project where there is no local
    /// clone. Requires `owner` and `repo` to be set on the config.
    public func makeRemoteProvider(config: ForgeConfig) -> ForgeProvider? {
        guard let owner = config.owner, let repo = config.repo else { return nil }
        switch self {
        case .github:
            return RemoteGitHubForge(owner: owner, repo: repo)
        case .forgejo:
            return RemoteForgejoForge(
                owner: owner,
                repo: repo,
                baseURL: config.baseURL ?? "http://localhost:3000",
                tokenEnvVar: config.tokenEnvVar
            )
        }
    }

    /// Detect forge type from a git remote URL.
    /// Returns nil for unrecognized hosts (user must configure manually).
    public static func detect(remoteURL: String) -> ForgeType? {
        let lower = remoteURL.lowercased()
        if lower.contains("github.com") { return .github }
        // Forgejo/Gitea instances vary by host — can't auto-detect.
        // User sets these explicitly via forgeConfig.
        return nil
    }

    /// Detect forge type by reading the origin remote of a repo.
    public static func detect(inRepo path: String) async -> ForgeType? {
        guard let output = try? await ShellService.run("git remote get-url origin", in: path) else {
            return nil
        }
        return detect(remoteURL: output)
    }
}

// MARK: - Forge Config (persisted per-project)

public struct ForgeConfig: Codable {
    public var type: ForgeType

    // For self-hosted forges (Forgejo, GitLab, etc.)
    public var baseURL: String?

    // Environment variable name that holds the API token (e.g. "FORGEJO_TOKEN")
    // Avoids storing secrets in the config file.
    public var tokenEnvVar: String?

    // Owner and repo for remote-only projects (no local clone). Local
    // projects can leave these nil and resolve owner/repo via the git
    // remote at call time.
    public var owner: String?
    public var repo: String?

    public init(
        type: ForgeType,
        baseURL: String? = nil,
        tokenEnvVar: String? = nil,
        owner: String? = nil,
        repo: String? = nil
    ) {
        self.type = type
        self.baseURL = baseURL
        self.tokenEnvVar = tokenEnvVar
        self.owner = owner
        self.repo = repo
    }
}

// MARK: - Errors

public enum ForgeError: Error, LocalizedError {
    case noForgeConfigured
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .noForgeConfigured:
            return "No forge configured for this project. Set one in project settings."
        case .apiError(let message):
            return "Forge API error: \(message)"
        }
    }
}
