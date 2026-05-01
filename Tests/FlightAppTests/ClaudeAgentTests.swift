import Foundation
import XCTest
import FlightCore
@testable import FlightApp

final class ClaudeAgentTests: XCTestCase {
    func testResultEventWithErrorSurfacesSystemMessage() throws {
        // Repro of the "claude -p --resume <missing-sid>" output path:
        // claude emits a single result event with is_error: true and an
        // errors array, no assistant event. Flight used to drop these on
        // the floor, leaving the chat silent. Now we render them.
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":0,"errors":["No conversation found with session ID: 00000000-0000-0000-0000-000000000000"],"session_id":"abc","duration_ms":0,"duration_api_ms":0,"total_cost_usd":0,"usage":{}}"#

        let event = try JSONDecoder().decode(StreamEvent.self, from: Data(line.utf8))
        XCTAssertEqual(event.isError, true)
        XCTAssertEqual(event.errors, ["No conversation found with session ID: 00000000-0000-0000-0000-000000000000"])

        let messages = event.toAgentMessages()
        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.role, .system)
        guard case .text(let body) = message.content else {
            return XCTFail("expected text content, got \(message.content)")
        }
        XCTAssertTrue(body.contains("No conversation found"), "body should include claude's error text, got: \(body)")
    }

    func testResultEventWithoutErrorIsStillDropped() throws {
        // Successful result events carry the full final assistant text in
        // earlier `assistant` events; the `result` event itself is just a
        // bookkeeping signal and shouldn't render anything.
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"pong","session_id":"abc","duration_ms":1,"duration_api_ms":1,"num_turns":1,"total_cost_usd":0,"usage":{}}"#

        let event = try JSONDecoder().decode(StreamEvent.self, from: Data(line.utf8))
        XCTAssertEqual(event.isError, false)
        XCTAssertTrue(event.toAgentMessages().isEmpty)
    }

    func testResultEventErrorWithEmptyErrorsHasFallbackBody() throws {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":[],"session_id":"abc","duration_ms":0,"duration_api_ms":0,"num_turns":0,"total_cost_usd":0,"usage":{}}"#

        let event = try JSONDecoder().decode(StreamEvent.self, from: Data(line.utf8))
        let messages = event.toAgentMessages()
        XCTAssertEqual(messages.count, 1)
        guard case .text(let body) = try XCTUnwrap(messages.first).content else {
            return XCTFail("expected text content")
        }
        XCTAssertTrue(body.contains("error"), "expected fallback to mention error, got: \(body)")
    }

    func testStreamJSONInputLineUsesTextContentWithoutImages() throws {
        let line = try XCTUnwrap(ClaudeAgent.makeStreamJSONInputLine(
            message: "Explain the failing test",
            images: []
        ))

        let root = try parseObject(line)
        XCTAssertEqual(root["type"] as? String, "user")

        let message = try XCTUnwrap(root["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
        XCTAssertEqual(message["content"] as? String, "Explain the failing test")
    }

    func testStreamJSONInputLineIncludesBase64ImageBlocks() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let line = try XCTUnwrap(ClaudeAgent.makeStreamJSONInputLine(
            message: "What changed in this screenshot?",
            images: [imageData]
        ))

        let root = try parseObject(line)
        let message = try XCTUnwrap(root["message"] as? [String: Any])
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        let imageBlock = content[0]
        XCTAssertEqual(imageBlock["type"] as? String, "image")
        let source = try XCTUnwrap(imageBlock["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())

        XCTAssertEqual(content[1]["type"] as? String, "text")
        XCTAssertEqual(content[1]["text"] as? String, "What changed in this screenshot?")
    }

    func testRemoteImageCommandUploadsAttachmentsBeforePromptingClaude() {
        let command = ClaudeAgent.makeRemoteCommand(
            message: "What is in this image?",
            images: [Data([1, 2, 3, 4])],
            claudeArgs: [
                "claude",
                "-p",
                "--output-format", "stream-json",
                "--verbose",
                "--dangerously-skip-permissions",
            ],
            uploadsImages: true
        )

        XCTAssertTrue(command.contains("flight-attachments-"))
        XCTAssertTrue(command.contains("python3 -c "))
        XCTAssertTrue(command.contains("claude -p \"$(cat \"$prompt_file\")\""))
        XCTAssertFalse(command.contains("'--input-format'"))
        XCTAssertFalse(command.contains("/tmp/flight-prompt.txt"))
        XCTAssertFalse(command.contains("What is in this image?"))
    }

    func testRemoteAttachmentUploadLineCarriesImageBytes() throws {
        let imageData = Data([1, 2, 3, 4])
        let line = try XCTUnwrap(ClaudeAgent.makeRemoteAttachmentUploadLine(
            message: "Inspect this",
            images: [imageData]
        ))

        let root = try parseObject(line)
        XCTAssertEqual(root["message"] as? String, "Inspect this")
        let images = try XCTUnwrap(root["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["filename"] as? String, "image-1.png")
        XCTAssertEqual(images[0]["media_type"] as? String, "image/png")
        XCTAssertEqual(images[0]["data"] as? String, imageData.base64EncodedString())
    }

    private func parseObject(_ line: String) throws -> [String: Any] {
        let data = try XCTUnwrap(line.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
