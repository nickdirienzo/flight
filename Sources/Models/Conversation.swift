import Foundation

@Observable
final class Conversation: Identifiable {
    let id: UUID
    var name: String
    var messages: [AgentMessage]
    var sessionID: String?
    var agentBusy: Bool = false
    var agent: ClaudeAgent?

    init(
        id: UUID = UUID(),
        name: String = "Chat",
        sessionID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.messages = []
        self.sessionID = sessionID
    }
}

struct ConversationConfig: Codable {
    let id: UUID
    var name: String
    var sessionID: String?

    init(from conversation: Conversation) {
        self.id = conversation.id
        self.name = conversation.name
        self.sessionID = conversation.sessionID
    }

    func toConversation() -> Conversation {
        let conv = Conversation(id: id, name: name, sessionID: sessionID)
        conv.messages = ConfigService.loadMessages(conversationID: id)
        return conv
    }
}
