import Foundation
import FlightCore

/// Runs one `claude -p` turn as a subprocess and yields each stdout line
/// back through an AsyncThrowingStream. Shape is identical to what
/// ClaudeAgent's `startReading` parses — one JSON object per line — so
/// HTTP callers can tee the bytes straight into an SSE body and get the
/// same stream-json contract the Mac app uses.
///
/// This deliberately does not import ClaudeAgent: that type is
/// MainActor-bound for UI observation. Server-side we need to stream lines
/// to a network socket, which is a different ownership pattern.
enum ChatStream {
    struct LaunchOptions {
        let worktreePath: String
        let message: String
        let resumeSessionID: String?
    }

    /// Emits raw JSONL lines from claude's stdout. The last element in
    /// the stream is a sentinel "result" event, after which the stream
    /// finishes naturally.
    static func run(_ options: LaunchOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

            var args = [
                "claude",
                "-p",
                "--output-format", "stream-json",
                "--input-format", "stream-json",
                "--verbose",
                // Server mode assumes the host is the isolation boundary
                // (the VM or container that provisioned the worktree).
                // The Mac app uses a sandbox; here there's nowhere to
                // prompt a user for permission, so we skip them.
                "--dangerously-skip-permissions",
            ]
            if let sid = options.resumeSessionID {
                args += ["--resume", sid]
            }
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: options.worktreePath)
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            continuation.onTermination = { _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // Push the user turn through stdin and close it — we don't
            // stream additional messages into a single turn; one turn per
            // HTTP request.
            let payload: [String: Any] = [
                "type": "user",
                "message": [
                    "role": "user",
                    "content": options.message,
                ],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
                try? stdinPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))
            }
            try? stdinPipe.fileHandleForWriting.close()

            // Read stdout on a detached task so the continuation can
            // yield without blocking the calling actor.
            let readHandle = stdoutPipe.fileHandleForReading
            Task.detached {
                var lineBuffer = Data()
                while true {
                    let chunk = readHandle.availableData
                    if chunk.isEmpty { break }
                    lineBuffer.append(chunk)

                    while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
                        let lineData = lineBuffer[lineBuffer.startIndex..<newlineIndex]
                        lineBuffer = Data(lineBuffer[lineBuffer.index(after: newlineIndex)...])
                        if lineData.isEmpty { continue }
                        if let line = String(data: Data(lineData), encoding: .utf8) {
                            continuation.yield(line)
                        }
                    }
                }

                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.finish(throwing: ChatStreamError.processFailed(
                        exitCode: process.terminationStatus,
                        stderr: stderr
                    ))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// Best-effort extraction of the session_id from a stream-json line.
    /// Callers use this to update their session store so subsequent turns
    /// can pass `--resume <id>`.
    static func extractSessionID(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
              event.type == "system" else {
            return nil
        }
        return event.sessionID
    }
}

enum ChatStreamError: Error, CustomStringConvertible {
    case processFailed(exitCode: Int32, stderr: String)

    var description: String {
        switch self {
        case .processFailed(let code, let stderr):
            return "claude exited with code \(code): \(stderr)"
        }
    }
}
