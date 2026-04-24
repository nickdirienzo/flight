import XCTest
@testable import FlightCore

final class ChatSectionTests: XCTestCase {
    func testBuildGroupsToolMessagesAndPromotesPlan() {
        let readTool = message(
            id: "00000000-0000-0000-0000-000000000001",
            content: .toolUse(name: "Read", input: #"{"file_path":"/tmp/a.txt"}"#)
        )
        let planTool = message(
            id: "00000000-0000-0000-0000-000000000002",
            content: .toolUse(name: "ExitPlanMode", input: #"{"plan":"Add CI"}"#)
        )
        let toolResult = message(
            id: "00000000-0000-0000-0000-000000000003",
            content: .toolResult(content: "done")
        )

        let sections = ChatSection.build(from: [readTool, planTool, toolResult])

        XCTAssertEqual(sections.count, 2)

        guard case .toolGroup(let id, let tools) = sections[0] else {
            return XCTFail("Expected first section to be a tool group")
        }
        XCTAssertEqual(id, readTool.id)
        XCTAssertEqual(tools, [readTool, toolResult])

        guard case .plan(let planMessage) = sections[1] else {
            return XCTFail("Expected second section to be a plan")
        }
        XCTAssertEqual(planMessage, planTool)
    }

    func testBuildFlushesToolGroupBeforeRegularMessage() {
        let toolUse = message(
            id: "00000000-0000-0000-0000-000000000004",
            content: .toolUse(name: "Bash", input: #"{"description":"List files"}"#)
        )
        let toolResult = message(
            id: "00000000-0000-0000-0000-000000000005",
            content: .toolResult(content: "Package.swift")
        )
        let response = message(
            id: "00000000-0000-0000-0000-000000000006",
            content: .text("Done")
        )

        let sections = ChatSection.build(from: [toolUse, toolResult, response])

        XCTAssertEqual(sections.count, 2)

        guard case .toolGroup(let id, let tools) = sections[0] else {
            return XCTFail("Expected first section to be a tool group")
        }
        XCTAssertEqual(id, toolUse.id)
        XCTAssertEqual(tools, [toolUse, toolResult])

        guard case .message(let message) = sections[1] else {
            return XCTFail("Expected second section to be a regular message")
        }
        XCTAssertEqual(message, response)
    }

    func testBuildFlushesSetupLogsBeforeProvisionLogs() {
        let setupLog = message(
            id: "00000000-0000-0000-0000-000000000007",
            content: .setupLog("creating worktree")
        )
        let provisionLog = message(
            id: "00000000-0000-0000-0000-000000000008",
            content: .provisionLog("installing dependencies")
        )

        let sections = ChatSection.build(from: [setupLog, provisionLog])

        XCTAssertEqual(sections.count, 2)

        guard case .setupGroup(let id, let logs) = sections[0] else {
            return XCTFail("Expected first section to be a setup group")
        }
        XCTAssertEqual(id, setupLog.id)
        XCTAssertEqual(logs, [setupLog])

        guard case .provisionGroup(let id, let logs) = sections[1] else {
            return XCTFail("Expected second section to be a provision group")
        }
        XCTAssertEqual(id, provisionLog.id)
        XCTAssertEqual(logs, [provisionLog])
    }

    private func message(id: String, content: MessageContent) -> AgentMessage {
        AgentMessage(
            id: UUID(uuidString: id)!,
            role: .assistant,
            content: content,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }
}
