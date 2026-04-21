import Foundation

/// GitHub forge backed by the `gh` CLI, running in a local repo checkout.
/// `gh` uses the cwd to resolve owner/repo from the git remote.
struct LocalGitHubForge: ForgeProvider {
    let displayName = "GitHub"
    let repoPath: String

    func getChecks(prNumber: Int) async throws -> [CICheck] {
        let output = try await ShellService.run(
            "gh pr checks \(prNumber) --json name,state,link",
            in: repoPath
        )
        guard let data = output.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CICheck].self, from: data)) ?? []
    }

    func getFailedLogs(prNumber: Int) async throws -> String {
        let checksOutput = try await ShellService.run(
            "gh pr checks \(prNumber) --json name,state,link --jq '.[] | select(.state == \"FAILURE\") | .link'",
            in: repoPath
        )

        let lines = checksOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let firstURL = lines.first,
              let url = URL(string: firstURL) else {
            return "No failed checks found."
        }

        let components = url.pathComponents
        if let runsIndex = components.firstIndex(of: "runs"),
           runsIndex + 1 < components.count {
            let runId = components[runsIndex + 1]
            let logs = try await ShellService.run(
                "gh run view \(runId) --log-failed",
                in: repoPath
            )
            return logs
        }

        return "Could not determine run ID from CI check URL."
    }

    func getPRStatus(prNumber: Int) async throws -> PRStatus {
        let output = try await ShellService.run(
            "gh pr view \(prNumber) --json latestReviews,reviewDecision,url",
            in: repoPath
        )
        return try parsePRStatus(
            viewOutput: output,
            commentsOutput: try? await ShellService.run(
                unresolvedThreadsCommand(
                    prNumber: prNumber,
                    ownerArg: #"-F owner="$(gh repo view --json owner --jq .owner.login)""#,
                    nameArg: #"-F name="$(gh repo view --json name --jq .name)""#
                ),
                in: repoPath
            )
        )
    }

    func getPRNumber(branch: String) async -> Int? {
        guard let output = try? await ShellService.run(
            "gh pr view '\(branch)' --json number --jq .number",
            in: repoPath
        ) else { return nil }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// GitHub forge backed by `gh --repo owner/name`, for projects where no
/// local clone exists. Every call is path-independent and works from any cwd.
struct RemoteGitHubForge: ForgeProvider {
    let displayName = "GitHub"
    let owner: String
    let repo: String

    private var repoFlag: String { "--repo \(owner)/\(repo)" }

    func getChecks(prNumber: Int) async throws -> [CICheck] {
        let output = try await ShellService.run(
            "gh pr checks \(prNumber) \(repoFlag) --json name,state,link"
        )
        guard let data = output.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CICheck].self, from: data)) ?? []
    }

    func getFailedLogs(prNumber: Int) async throws -> String {
        let checksOutput = try await ShellService.run(
            "gh pr checks \(prNumber) \(repoFlag) --json name,state,link --jq '.[] | select(.state == \"FAILURE\") | .link'"
        )

        let lines = checksOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let firstURL = lines.first,
              let url = URL(string: firstURL) else {
            return "No failed checks found."
        }

        let components = url.pathComponents
        if let runsIndex = components.firstIndex(of: "runs"),
           runsIndex + 1 < components.count {
            let runId = components[runsIndex + 1]
            let logs = try await ShellService.run(
                "gh run view \(runId) \(repoFlag) --log-failed"
            )
            return logs
        }

        return "Could not determine run ID from CI check URL."
    }

    func getPRStatus(prNumber: Int) async throws -> PRStatus {
        let output = try await ShellService.run(
            "gh pr view \(prNumber) \(repoFlag) --json latestReviews,reviewDecision,url"
        )
        return try parsePRStatus(
            viewOutput: output,
            commentsOutput: try? await ShellService.run(
                unresolvedThreadsCommand(
                    prNumber: prNumber,
                    ownerArg: "-F owner=\(owner)",
                    nameArg: "-F name=\(repo)"
                )
            )
        )
    }

    func getPRNumber(branch: String) async -> Int? {
        guard let output = try? await ShellService.run(
            "gh pr view '\(branch)' \(repoFlag) --json number --jq .number"
        ) else { return nil }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// Builds a `gh api graphql` invocation that returns tab-separated rows for
// both issue-level PR comments and inline review-thread comments on threads
// that have NOT been resolved. The REST `/pulls/:n/comments` endpoint has no
// `isResolved` field — resolution is a GraphQL-only concept on `reviewThreads`.
// Rows are `author\tpath\tline\tbody`; issue comments have empty path/line.
private func unresolvedThreadsCommand(
    prNumber: Int,
    ownerArg: String,
    nameArg: String
) -> String {
    let query = #"query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { comments(first: 100) { nodes { author { login } body } } reviewThreads(first: 100) { nodes { isResolved comments(first: 100) { nodes { author { login } body path line } } } } } } }"#
    let jq = #"(.data.repository.pullRequest.comments.nodes[] | [(.author.login // "unknown"), "", "", .body] | @tsv), (.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .comments.nodes[] | [(.author.login // "unknown"), (.path // ""), ((.line // "") | tostring), .body] | @tsv)"#
    return "gh api graphql \(ownerArg) \(nameArg) -F number=\(prNumber) -f query='\(query)' --jq '\(jq)'"
}

// Shared parsing for `gh pr view --json latestReviews,reviewDecision,url`
// plus inline comments. Extracted so both local and remote impls share it.
private func parsePRStatus(viewOutput: String, commentsOutput: String?) throws -> PRStatus {
    guard let data = viewOutput.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return PRStatus(reviews: [], reviewDecision: nil)
    }

    var reviews: [PRReview] = []
    if let rawReviews = json["latestReviews"] as? [[String: Any]] {
        for r in rawReviews {
            let author = (r["author"] as? [String: Any])?["login"] as? String ?? "unknown"
            let state = r["state"] as? String ?? "PENDING"
            reviews.append(PRReview(author: author, state: state))
        }
    }

    var comments: [PRComment] = []
    if let commentsOutput {
        for line in commentsOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { continue }
            comments.append(PRComment(
                author: parts[0],
                body: parts[3],
                path: parts[1].isEmpty ? nil : parts[1],
                line: Int(parts[2])
            ))
        }
    }

    let decision = json["reviewDecision"] as? String
    let url = json["url"] as? String
    return PRStatus(reviews: reviews, reviewDecision: decision, url: url, comments: comments)
}
