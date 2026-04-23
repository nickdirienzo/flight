import Foundation
import FlightCore
import Hummingbird

// MARK: - Request/Response DTOs

struct CreateSessionRequest: Codable {
    let repoPath: String
    let branch: String?
}

struct SessionResponse: Codable, ResponseEncodable {
    let sessionId: String
    let branch: String
    let worktreePath: String
    let claudeSessionID: String?
}

struct SessionListResponse: Codable, ResponseEncodable {
    let sessions: [SessionResponse]
}

struct ChatRequest: Codable {
    let message: String
}

// MARK: - Router

func buildRouter(store: SessionStore) -> Router<BasicRequestContext> {
    let router = Router()

    router.post("/sessions") { request, context -> SessionResponse in
        let body = try await request.decode(as: CreateSessionRequest.self, context: context)
        let branch = body.branch ?? randomBranch()

        let repoURL = URL(fileURLWithPath: body.repoPath)
        let repoName = repoURL.lastPathComponent
        let worktreePath = ConfigService.worktreePath(repoName: repoName, branch: branch)

        try await GitService.createWorktree(
            repoPath: body.repoPath,
            branch: branch,
            worktreePath: worktreePath
        )

        let session = SessionStore.Session(
            id: branch,
            repoPath: body.repoPath,
            branch: branch,
            worktreePath: worktreePath
        )
        await store.add(session)

        return SessionResponse(
            sessionId: session.id,
            branch: session.branch,
            worktreePath: session.worktreePath,
            claudeSessionID: nil
        )
    }

    router.get("/sessions") { _, _ -> SessionListResponse in
        let all = await store.list()
        return SessionListResponse(sessions: all.map {
            SessionResponse(
                sessionId: $0.id,
                branch: $0.branch,
                worktreePath: $0.worktreePath,
                claudeSessionID: $0.claudeSessionID
            )
        })
    }

    router.post("/sessions/:id/chat") { request, context -> Response in
        guard let id = context.parameters.get("id") else {
            throw HTTPError(.badRequest, message: "Missing session id")
        }
        guard let session = await store.get(id) else {
            throw HTTPError(.notFound, message: "Unknown session id: \(id)")
        }
        let body = try await request.decode(as: ChatRequest.self, context: context)

        let options = ChatStream.LaunchOptions(
            worktreePath: session.worktreePath,
            message: body.message,
            resumeSessionID: session.claudeSessionID
        )

        let headers: HTTPFields = [
            .contentType: "text/event-stream",
            .cacheControl: "no-cache",
        ]

        let responseBody = ResponseBody { writer in
            do {
                for try await line in ChatStream.run(options) {
                    if let sid = ChatStream.extractSessionID(from: line) {
                        await store.updateClaudeSession(id: id, claudeSessionID: sid)
                    }
                    let frame = "data: \(line)\n\n"
                    var buffer = ByteBuffer()
                    buffer.writeString(frame)
                    try await writer.write(buffer)
                }
                var done = ByteBuffer()
                done.writeString("event: done\ndata: {}\n\n")
                try await writer.write(done)
            } catch {
                var buffer = ByteBuffer()
                buffer.writeString("event: error\ndata: \(String(describing: error))\n\n")
                try? await writer.write(buffer)
            }
            try await writer.finish(nil)
        }

        return Response(status: .ok, headers: headers, body: responseBody)
    }

    router.delete("/sessions/:id") { _, context -> HTTPResponse.Status in
        guard let id = context.parameters.get("id") else {
            throw HTTPError(.badRequest, message: "Missing session id")
        }
        guard let session = await store.get(id) else {
            throw HTTPError(.notFound, message: "Unknown session id: \(id)")
        }
        try await GitService.removeWorktree(
            repoPath: session.repoPath,
            worktreePath: session.worktreePath,
            branch: session.branch
        )
        await store.remove(id)
        return .noContent
    }

    return router
}

// MARK: - Helpers

private func randomBranch() -> String {
    let adjectives = ["swift", "bold", "calm", "dark", "keen", "warm", "cool", "fast", "wild", "soft"]
    let nouns = ["fox", "oak", "elm", "owl", "jay", "bee", "ant", "ray", "fin", "gem"]
    let adj = adjectives.randomElement()!
    let noun = nouns.randomElement()!
    let suffix = String(UUID().uuidString.prefix(4)).lowercased()
    return "flight/\(adj)-\(noun)-\(suffix)"
}
