import Foundation

/// Forgejo/Gitea forge provider using the REST API.
///
/// Authentication: reads the API token from the environment variable
/// specified by `tokenEnvVar` (defaults to FORGEJO_TOKEN).
///
/// The base URL should point to your Forgejo instance root
/// (e.g. "https://git.example.com" or "http://localhost:3000").

/// Local variant: resolves owner/repo from the `origin` remote of a
/// checked-out repo. Good for projects where Flight has a local clone.
public struct LocalForgejoForge: ForgeProvider {
    public let displayName = "Forgejo"
    public let repoPath: String
    public let baseURL: String
    public let tokenEnvVar: String

    public init(repoPath: String, baseURL: String, tokenEnvVar: String? = nil) {
        self.repoPath = repoPath
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.tokenEnvVar = tokenEnvVar ?? "FORGEJO_TOKEN"
    }

    public func getChecks(prNumber: Int) async throws -> [CICheck] {
        let (owner, repo) = try await parseRemote(in: repoPath)
        return try await ForgejoAPI.getChecks(
            prNumber: prNumber, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    public func getFailedLogs(prNumber: Int) async throws -> String {
        let (owner, repo) = try await parseRemote(in: repoPath)
        return try await ForgejoAPI.getFailedLogs(
            prNumber: prNumber, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    public func getPRStatus(prNumber: Int) async throws -> PRStatus {
        let (owner, repo) = try await parseRemote(in: repoPath)
        return try await ForgejoAPI.getPRStatus(
            prNumber: prNumber, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    public func getPRNumber(branch: String) async -> Int? {
        guard let (owner, repo) = try? await parseRemote(in: repoPath) else { return nil }
        return await ForgejoAPI.getPRNumber(
            branch: branch, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    private func parseRemote(in path: String) async throws -> (owner: String, repo: String) {
        let output = try await ShellService.run("git remote get-url origin", in: path)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle SSH (git@host:owner/repo.git) and HTTP (https://host/owner/repo.git)
        let cleaned: String
        if trimmed.contains("@") {
            cleaned = trimmed.components(separatedBy: ":").last ?? trimmed
        } else {
            cleaned = URL(string: trimmed)?.pathComponents
                .suffix(2).joined(separator: "/") ?? trimmed
        }

        let parts = cleaned
            .replacingOccurrences(of: ".git", with: "")
            .components(separatedBy: "/")
            .filter { !$0.isEmpty }

        guard parts.count >= 2 else {
            throw ForgeError.apiError("Could not parse owner/repo from remote: \(trimmed)")
        }
        return (parts[parts.count - 2], parts[parts.count - 1])
    }
}

/// Remote variant: owner/repo are supplied directly; no local clone required.
public struct RemoteForgejoForge: ForgeProvider {
    public let displayName = "Forgejo"
    public let owner: String
    public let repo: String
    public let baseURL: String
    public let tokenEnvVar: String

    public init(owner: String, repo: String, baseURL: String, tokenEnvVar: String? = nil) {
        self.owner = owner
        self.repo = repo
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.tokenEnvVar = tokenEnvVar ?? "FORGEJO_TOKEN"
    }

    public func getChecks(prNumber: Int) async throws -> [CICheck] {
        try await ForgejoAPI.getChecks(
            prNumber: prNumber, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    public func getFailedLogs(prNumber: Int) async throws -> String {
        try await ForgejoAPI.getFailedLogs(
            prNumber: prNumber, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    public func getPRStatus(prNumber: Int) async throws -> PRStatus {
        try await ForgejoAPI.getPRStatus(
            prNumber: prNumber, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }

    public func getPRNumber(branch: String) async -> Int? {
        await ForgejoAPI.getPRNumber(
            branch: branch, owner: owner, repo: repo,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
    }
}

// MARK: - Shared Forgejo REST helpers

private enum ForgejoAPI {
    static func getChecks(
        prNumber: Int, owner: String, repo: String,
        baseURL: String, tokenEnvVar: String
    ) async throws -> [CICheck] {
        // Get the PR to find the head SHA
        let pr: [String: Any] = try await apiRequest(
            method: "GET",
            path: "/api/v1/repos/\(owner)/\(repo)/pulls/\(prNumber)",
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )

        guard let head = pr["head"] as? [String: Any],
              let sha = head["sha"] as? String else {
            return []
        }

        let statuses: [[String: Any]] = try await apiRequest(
            method: "GET",
            path: "/api/v1/repos/\(owner)/\(repo)/statuses/\(sha)",
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )

        return statuses.compactMap { status in
            guard let name = status["context"] as? String,
                  let state = status["status"] as? String else { return nil }
            let mapped = switch state {
            case "success": "SUCCESS"
            case "failure", "error": "FAILURE"
            case "pending": "PENDING"
            default: "PENDING"
            }
            let link = status["target_url"] as? String
            return CICheck(name: name, state: mapped, link: link)
        }
    }

    static func getFailedLogs(
        prNumber: Int, owner: String, repo: String,
        baseURL: String, tokenEnvVar: String
    ) async throws -> String {
        let runs: [String: Any] = try await apiRequest(
            method: "GET",
            path: "/api/v1/repos/\(owner)/\(repo)/actions/runs",
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )

        guard let workflows = runs["workflow_runs"] as? [[String: Any]] else {
            return "No CI runs found."
        }

        let failed = workflows.filter { ($0["conclusion"] as? String) == "failure" }
        guard let latest = failed.first,
              let runID = latest["id"] as? Int else {
            return "No failed runs found."
        }

        let jobs: [String: Any] = try await apiRequest(
            method: "GET",
            path: "/api/v1/repos/\(owner)/\(repo)/actions/runs/\(runID)/jobs",
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )

        guard let jobList = jobs["jobs"] as? [[String: Any]] else {
            return "No jobs found for run \(runID)."
        }

        var logOutput = ""
        for job in jobList {
            guard (job["conclusion"] as? String) == "failure",
                  let jobID = job["id"] as? Int,
                  let jobName = job["name"] as? String else { continue }

            let logText = try await rawAPIRequest(
                method: "GET",
                path: "/api/v1/repos/\(owner)/\(repo)/actions/runs/\(runID)/jobs/\(jobID)/logs",
                baseURL: baseURL, tokenEnvVar: tokenEnvVar
            )
            logOutput += "=== \(jobName) ===\n\(logText)\n\n"
        }

        return logOutput.isEmpty ? "No failed job logs found." : logOutput
    }

    static func getPRStatus(
        prNumber: Int, owner: String, repo: String,
        baseURL: String, tokenEnvVar: String
    ) async throws -> PRStatus {
        let rawReviews: [[String: Any]] = try await apiRequest(
            method: "GET",
            path: "/api/v1/repos/\(owner)/\(repo)/pulls/\(prNumber)/reviews",
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )

        var latestByUser: [String: PRReview] = [:]
        for r in rawReviews {
            let author = (r["user"] as? [String: Any])?["login"] as? String ?? "unknown"
            let state = r["state"] as? String ?? "PENDING"
            let mapped: String = switch state.uppercased() {
            case "APPROVED": "APPROVED"
            case "REQUEST_CHANGES": "CHANGES_REQUESTED"
            case "COMMENT": "COMMENTED"
            default: "PENDING"
            }
            latestByUser[author] = PRReview(author: author, state: mapped)
        }

        let reviews = Array(latestByUser.values)
        let decision: String? = if reviews.contains(where: { $0.state == "CHANGES_REQUESTED" }) {
            "CHANGES_REQUESTED"
        } else if reviews.contains(where: { $0.state == "APPROVED" }) {
            "APPROVED"
        } else {
            nil
        }

        return PRStatus(reviews: reviews, reviewDecision: decision)
    }

    static func getPRNumber(
        branch: String, owner: String, repo: String,
        baseURL: String, tokenEnvVar: String
    ) async -> Int? {
        guard let pulls: [[String: Any]] = try? await apiRequest(
            method: "GET",
            path: "/api/v1/repos/\(owner)/\(repo)/pulls?state=open&head=\(owner):\(branch)&limit=1",
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        ), let first = pulls.first,
           let number = first["number"] as? Int else { return nil }
        return number
    }

    // MARK: - HTTP

    private static func token(_ envVar: String) -> String? {
        ProcessInfo.processInfo.environment[envVar]
    }

    static func apiRequest<T>(
        method: String, path: String, body: [String: Any]? = nil,
        baseURL: String, tokenEnvVar: String
    ) async throws -> T {
        let raw = try await rawAPIRequest(
            method: method, path: path, body: body,
            baseURL: baseURL, tokenEnvVar: tokenEnvVar
        )
        guard let data = raw.data(using: .utf8) else {
            throw ForgeError.apiError("Empty response")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? T else {
            throw ForgeError.apiError("Unexpected response format")
        }
        return json
    }

    static func rawAPIRequest(
        method: String, path: String, body: [String: Any]? = nil,
        baseURL: String, tokenEnvVar: String
    ) async throws -> String {
        var curlCmd = "curl -s -X \(method)"

        if let tok = token(tokenEnvVar) {
            curlCmd += " -H 'Authorization: token \(tok)'"
        }

        if let body {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            let bodyStr = String(data: bodyData, encoding: .utf8) ?? "{}"
            curlCmd += " -H 'Content-Type: application/json' -d '\(bodyStr)'"
        }

        curlCmd += " '\(baseURL)\(path)'"
        return try await ShellService.run(curlCmd)
    }
}
