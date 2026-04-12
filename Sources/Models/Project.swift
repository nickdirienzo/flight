import Foundation

@Observable
final class Project: Identifiable {
    var id: String { name }
    var name: String
    /// Filesystem path to the local clone. `nil` for remote-only projects
    /// that have no checkout on this machine — those projects only support
    /// remote worktrees and skip every code path that touches a local repo.
    var path: String?
    var worktrees: [Worktree]
    var remoteMode: RemoteModeConfig?
    var forgeConfig: ForgeConfig?
    var setupScript: String?

    init(
        name: String,
        path: String?,
        worktrees: [Worktree] = [],
        remoteMode: RemoteModeConfig? = nil,
        forgeConfig: ForgeConfig? = nil,
        setupScript: String? = nil
    ) {
        self.name = name
        self.path = path
        self.worktrees = worktrees
        self.remoteMode = remoteMode
        self.forgeConfig = forgeConfig
        self.setupScript = setupScript
    }

    /// Convenience for the common local-add case where the name is just
    /// the last path component.
    convenience init(path: String) {
        self.init(
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path
        )
    }

    var isRemoteOnly: Bool { path == nil }

    var hasRemoteMode: Bool {
        remoteMode != nil || RemoteScriptsService.hasAnyScript(project: self)
    }

    /// Returns the forge provider for this project, or nil if none configured.
    /// Local projects get a path-backed provider; remote-only projects get
    /// one that talks directly to `owner/repo` via the forge API.
    var forgeProvider: ForgeProvider? {
        guard let config = forgeConfig else { return nil }
        if let path {
            return config.type.makeLocalProvider(config: config, repoPath: path)
        }
        return config.type.makeRemoteProvider(config: config)
    }
}

struct ProjectConfig: Codable {
    let name: String
    let path: String?
    var worktreeConfigs: [WorktreeConfig]
    var remoteMode: RemoteModeConfig?
    var forgeConfig: ForgeConfig?
    var setupScript: String?

    init(from project: Project) {
        self.name = project.name
        self.path = project.path
        self.worktreeConfigs = project.worktrees.map { WorktreeConfig(from: $0) }
        self.remoteMode = project.remoteMode
        self.forgeConfig = project.forgeConfig
        self.setupScript = project.setupScript
    }

    func toProject() -> Project {
        let project = Project(
            name: name,
            path: path,
            remoteMode: remoteMode,
            forgeConfig: forgeConfig,
            setupScript: setupScript
        )
        project.worktrees = worktreeConfigs.map { $0.toWorktree() }
        return project
    }
}
