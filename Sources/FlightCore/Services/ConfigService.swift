import Foundation

/// Settings-level override of the `.flight/<lifecycle>` scripts in a
/// repo. Each field is a shell command string (not a template — no
/// placeholder substitution). Commands run via `zsh -l -c` with env
/// vars set: `FLIGHT_BRANCH` for provision, `FLIGHT_WORKSPACE` for
/// connect/teardown. Connect additionally receives the remote command
/// as `"$@"`.
public struct RemoteModeConfig: Codable {
    public var provision: String
    public var connect: String
    public var teardown: String
    public var list: String?

    public init(provision: String, connect: String, teardown: String, list: String? = nil) {
        self.provision = provision
        self.connect = connect
        self.teardown = teardown
        self.list = list
    }
}

public struct FlightConfig: Codable {
    public var projects: [ProjectConfig]

    public init(projects: [ProjectConfig]) {
        self.projects = projects
    }

    public static let empty = FlightConfig(projects: [])
}

public enum ConfigService {
    /// Root directory for all Flight state (`~/flight`). Used as a stable
    /// cwd for remote-only projects that have no local clone.
    public static var flightHomeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("flight")
    }

    private static var configURL: URL {
        flightHomeURL.appendingPathComponent("config.json")
    }

    public static var worktreesBaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("flight")
            .appendingPathComponent("worktrees")
    }

    private static var logsBaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("flight")
            .appendingPathComponent("logs")
    }

    public static func ensureDirectories() {
        let fm = FileManager.default
        let flightDir = configURL.deletingLastPathComponent()
        try? fm.createDirectory(at: flightDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: worktreesBaseURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logsBaseURL, withIntermediateDirectories: true)
    }

    public static func logFileURL(repoName: String, branch: String) -> URL {
        let repoDir = logsBaseURL.appendingPathComponent(repoName)
        try? FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        let safeBranch = branch.replacingOccurrences(of: "/", with: "-")
        return repoDir.appendingPathComponent("\(safeBranch).log")
    }

    public static func load() -> FlightConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(FlightConfig.self, from: data) else {
            return .empty
        }
        return config
    }

    public static func save(_ config: FlightConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    public static func worktreePath(repoName: String, branch: String) -> String {
        worktreesBaseURL
            .appendingPathComponent(repoName)
            .appendingPathComponent(branch)
            .path
    }

}
