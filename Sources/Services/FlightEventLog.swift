import Foundation

/// Append-only JSONL log of Flight's own events, keyed by conversation.
/// Single writer (Flight) → no race with claude's session jsonl.
///
/// File layout: `~/flight/flight-events/<conversationID>.jsonl`.
enum FlightEventLog {
    static var baseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("flight")
            .appendingPathComponent("flight-events")
    }

    static func fileURL(conversationID: UUID) -> URL {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("\(conversationID.uuidString).jsonl")
    }

    /// Appends one event as a single JSONL line. Atomic relative to other
    /// callers on the same file because we open-append-close per call.
    static func append(_ event: FlightEvent, conversationID: UUID) {
        let url = fileURL(conversationID: conversationID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A) // newline

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Reads all events for a conversation. Malformed lines are skipped —
    /// this is a best-effort log, not a transaction store.
    static func load(conversationID: UUID) -> [FlightEvent] {
        let url = fileURL(conversationID: conversationID)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var events: [FlightEvent] = []
        events.reserveCapacity(256)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(FlightEvent.self, from: lineData) {
                events.append(event)
            }
        }
        return events
    }

    static func delete(conversationID: UUID) {
        let url = fileURL(conversationID: conversationID)
        try? FileManager.default.removeItem(at: url)
    }
}
