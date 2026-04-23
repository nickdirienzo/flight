import Foundation

public enum WorktreeSetupSource {
    case settings
    case file(path: String)
}

public enum WorktreeSetupService {
    /// Best-effort synchronous check used to render the setup block in the UI
    /// *before* git has cut the worktree. Looks at the settings field first,
    /// then peeks at the source repo's working tree for `.flight/worktree-setup`
    /// (which is what the worktree will inherit at HEAD).
    public static func willRunSetup(project: Project) -> Bool {
        if let script = project.setupScript?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty {
            return true
        }
        // Remote-only projects have no local clone, so no on-disk
        // `.flight/worktree-setup` to inherit from.
        guard let projectPath = project.path else { return false }
        let sourcePath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".flight")
            .appendingPathComponent("worktree-setup")
            .path
        return FileManager.default.fileExists(atPath: sourcePath)
    }

    /// Resolves which setup script (if any) should run for a freshly created
    /// worktree. Settings field wins when set, so users can prototype a script
    /// locally without committing `.flight/worktree-setup` to the repo.
    public static func resolveScript(project: Project, worktreePath: String) -> (content: String, source: WorktreeSetupSource)? {
        if let script = project.setupScript?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty {
            return (project.setupScript ?? script, .settings)
        }

        let scriptPath = URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".flight")
            .appendingPathComponent("worktree-setup")
            .path
        guard FileManager.default.fileExists(atPath: scriptPath),
              let content = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
            return nil
        }
        return (content, .file(path: scriptPath))
    }

    /// Runs the resolved script in the worktree, streaming each output line
    /// through `onLine`. Throws on non-zero exit; the caller decides what to
    /// do (typically: don't start the agent, surface the error, leave the
    /// worktree on disk for inspection).
    public static func run(
        scriptContent: String,
        in worktreePath: String,
        onLine: @escaping @MainActor (String) -> Void
    ) async throws {
        _ = try await ShellService.runScriptStreaming(
            scriptContent: scriptContent,
            in: worktreePath,
            onLine: onLine
        )
    }
}
