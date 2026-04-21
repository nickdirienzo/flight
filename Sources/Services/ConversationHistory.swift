import Foundation
import FlightCore

/// Rebuilds a conversation's rendered history from the two on-disk logs:
///   - Flight's own event log (`FlightEventLog`) — setup/provision/system
///     notes, interrupts, clears, remote-imported messages.
///   - Claude's session jsonl — user and assistant messages for local
///     sessions (not available for remote).
///
/// Events are merged by timestamp, then any `clear` marker truncates the
/// prefix so cleared-then-resumed conversations start fresh in the UI.
enum ConversationHistory {
    static func hydrate(
        conversationID: UUID,
        worktreePath: String,
        sessionID: String?,
        isRemote: Bool
    ) -> [AgentMessage] {
        migrateLegacyChatFile(conversationID: conversationID, isRemote: isRemote)
        let flightEvents = FlightEventLog.load(conversationID: conversationID)

        var claudeMessages: [AgentMessage] = []
        if !isRemote, let sessionID, !worktreePath.isEmpty {
            claudeMessages = ClaudeSessionReader.readMessages(
                worktreePath: worktreePath,
                sessionID: sessionID
            )
        }

        // Drop everything strictly before the most recent clear marker.
        let cutoff = flightEvents
            .filter { $0.kind == .clear }
            .map(\.timestamp)
            .max()

        var merged: [AgentMessage] = []
        merged.reserveCapacity(flightEvents.count + claudeMessages.count)

        for event in flightEvents {
            if let cutoff, event.timestamp < cutoff { continue }
            if let msg = event.toAgentMessage() { merged.append(msg) }
        }
        for msg in claudeMessages {
            if let cutoff, msg.timestamp < cutoff { continue }
            merged.append(msg)
        }

        // Stable sort — preserves ordering of events that share a timestamp
        // (e.g. a burst of streamed tool_use blocks with the same epoch).
        merged.sort { $0.timestamp < $1.timestamp }
        return merged
    }

    /// One-shot conversion from the pre-event-log `chat/<id>.json` snapshot
    /// format into `flight-events/<id>.jsonl`. Runs at most once per
    /// conversation (legacy file is deleted after successful backfill).
    ///
    /// For **remote** worktrees, every message is preserved as a
    /// `remoteMessage` event — there's no claude jsonl locally, so this log
    /// is the only record of the transcript.
    ///
    /// For **local** worktrees, we only backfill non-user/non-assistant
    /// messages (setup logs, provision logs, system notes). Claude's own
    /// session jsonl already holds user/assistant turns; writing them here
    /// too would double them on next hydrate.
    private static func migrateLegacyChatFile(conversationID: UUID, isRemote: Bool) {
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("flight")
            .appendingPathComponent("chat")
            .appendingPathComponent("\(conversationID.uuidString).json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyURL.path) else { return }

        guard let data = try? Data(contentsOf: legacyURL),
              let messages = try? JSONDecoder().decode([AgentMessage].self, from: data) else {
            // Leave the file so we can inspect what didn't parse.
            return
        }

        for message in messages {
            guard let event = convertLegacyMessage(message, isRemote: isRemote) else { continue }
            FlightEventLog.append(event, conversationID: conversationID)
        }
        try? fm.removeItem(at: legacyURL)
    }

    private static func convertLegacyMessage(_ message: AgentMessage, isRemote: Bool) -> FlightEvent? {
        switch (message.role, message.content) {
        case (.system, .setupLog(let text)):
            return FlightEvent(id: message.id, timestamp: message.timestamp, kind: .setupLog, text: text, role: nil, content: nil)
        case (.system, .provisionLog(let text)):
            return FlightEvent(id: message.id, timestamp: message.timestamp, kind: .provisionLog, text: text, role: nil, content: nil)
        case (.system, .text(let text)):
            // Surface the old "Interrupted" system marker as the real thing.
            if text == "Interrupted" {
                return FlightEvent(id: message.id, timestamp: message.timestamp, kind: .interrupt, text: nil, role: nil, content: nil)
            }
            return FlightEvent(id: message.id, timestamp: message.timestamp, kind: .systemNote, text: text, role: nil, content: nil)
        case (.system, .permissionRequest):
            // Ephemeral approval prompts — not worth persisting.
            return nil
        case (.user, _), (.assistant, _):
            guard isRemote else { return nil }
            return FlightEvent(id: message.id, timestamp: message.timestamp, kind: .remoteMessage, text: nil, role: message.role, content: message.content)
        default:
            return nil
        }
    }
}
