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
}
