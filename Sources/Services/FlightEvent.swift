import Foundation
import FlightCore

/// Append-only event type for `flight.jsonl`. Flight owns every event in this
/// log; claude owns its own session jsonl. Hydrating a conversation merges
/// the two by timestamp.
///
/// Encoding is a flat tagged struct so lines are easy to eyeball:
///   {"id":"...","timestamp":...,"kind":"setupLog","text":"..."}
struct FlightEvent: Codable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    /// Populated for setupLog, provisionLog, systemNote, interrupt (optional detail).
    let text: String?
    /// Populated for remoteMessage.
    let role: MessageRole?
    /// Populated for remoteMessage. Holds the full MessageContent payload so
    /// tool use/result from a remote stream round-trips without loss.
    let content: MessageContent?

    enum Kind: String, Codable {
        case setupLog
        case provisionLog
        case systemNote
        case interrupt
        case clear
        case remoteMessage
    }

    static func setupLog(_ text: String) -> FlightEvent {
        FlightEvent(id: UUID(), timestamp: Date(), kind: .setupLog, text: text, role: nil, content: nil)
    }

    static func provisionLog(_ text: String) -> FlightEvent {
        FlightEvent(id: UUID(), timestamp: Date(), kind: .provisionLog, text: text, role: nil, content: nil)
    }

    static func systemNote(_ text: String) -> FlightEvent {
        FlightEvent(id: UUID(), timestamp: Date(), kind: .systemNote, text: text, role: nil, content: nil)
    }

    static func interrupt() -> FlightEvent {
        FlightEvent(id: UUID(), timestamp: Date(), kind: .interrupt, text: nil, role: nil, content: nil)
    }

    static func clear() -> FlightEvent {
        FlightEvent(id: UUID(), timestamp: Date(), kind: .clear, text: nil, role: nil, content: nil)
    }

    static func remoteMessage(role: MessageRole, content: MessageContent) -> FlightEvent {
        FlightEvent(id: UUID(), timestamp: Date(), kind: .remoteMessage, text: nil, role: role, content: content)
    }

    /// Convert this event into the AgentMessage the UI renders. `clear`
    /// returns nil because it's a marker, not a message — ConversationHistory
    /// handles it during merge.
    func toAgentMessage() -> AgentMessage? {
        switch kind {
        case .setupLog:
            guard let text else { return nil }
            return AgentMessage(id: id, role: .system, content: .setupLog(text), timestamp: timestamp)
        case .provisionLog:
            guard let text else { return nil }
            return AgentMessage(id: id, role: .system, content: .provisionLog(text), timestamp: timestamp)
        case .systemNote:
            guard let text else { return nil }
            return AgentMessage(id: id, role: .system, content: .text(text), timestamp: timestamp)
        case .interrupt:
            return AgentMessage(id: id, role: .system, content: .text("Interrupted"), timestamp: timestamp)
        case .clear:
            return nil
        case .remoteMessage:
            guard let role, let content else { return nil }
            return AgentMessage(id: id, role: role, content: content, timestamp: timestamp)
        }
    }
}
