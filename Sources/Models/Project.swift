import Foundation

@Observable
final class Project: Identifiable {
    var id: String { name }
    var name: String
    var path: String
    var worktrees: [Worktree]
    var remoteMode: RemoteModeConfig?

    init(path: String, worktrees: [Worktree] = [], remoteMode: RemoteModeConfig? = nil) {
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.worktrees = worktrees
        self.remoteMode = remoteMode
    }

    var hasRemoteMode: Bool {
        remoteMode != nil
    }
}

struct ProjectConfig: Codable {
    let name: String
    let path: String
    var worktreeConfigs: [WorktreeConfig]
    var remoteMode: RemoteModeConfig?

    init(from project: Project) {
        self.name = project.name
        self.path = project.path
        self.worktreeConfigs = project.worktrees.map { WorktreeConfig(from: $0) }
        self.remoteMode = project.remoteMode
    }

    func toProject() -> Project {
        let project = Project(path: path, remoteMode: remoteMode)
        project.worktrees = worktreeConfigs.map { $0.toWorktree() }
        return project
    }
}
