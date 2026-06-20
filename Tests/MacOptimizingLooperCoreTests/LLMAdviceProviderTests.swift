import XCTest
@testable import MacOptimizingLooperCore

final class LLMAdviceProviderTests: XCTestCase {
    func testAdviseMapsJSONSuggestionsToAdvice() async throws {
        let provider = LLMAdviceProvider(client: StubLLMClient(content: "analysis notes"), responseFormatter: StubResponseFormatter(content: """
        {
          "summary": "Chrome and Xcode are the main contributors.",
          "statusBar": {
            "title": "🚨 2",
            "color": "red"
          },
          "suggestions": [
            {
              "title": "Close unused Chrome tabs",
              "detail": "Chrome is using significant CPU.",
              "rationale": "Reducing active tabs can reduce renderer pressure.",
              "severity": {
                "id": "critical",
                "label": "Critical",
                "icon": "🚨",
                "color": "red",
                "rank": 100
              },
              "suggestedCommand": "open -a 'Activity Monitor'",
              "targetProcessName": "Chrome"
            },
            {
              "title": "Pause an Xcode indexing task",
              "detail": "Xcode is using substantial memory.",
              "rationale": "Waiting for indexing to finish may reduce memory pressure.",
              "severity": {
                "id": "session-trim",
                "label": "Medium",
                "icon": "🟡",
                "color": "yellow",
                "rank": 50
              },
              "suggestedCommand": null,
              "targetProcessName": "Xcode"
            }
          ]
        }
        """))

        let advice = try await provider.advise(for: Fixtures.snapshot)

        XCTAssertEqual(advice.generatedAt, Fixtures.snapshot.timestamp)
        XCTAssertEqual(advice.summary, "Chrome and Xcode are the main contributors.")
        XCTAssertEqual(advice.statusBar.title, "🚨 2")
        XCTAssertEqual(advice.statusBar.color, "red")
        XCTAssertEqual(advice.suggestions.count, 2)
        XCTAssertEqual(advice.suggestions[0].title, "Close unused Chrome tabs")
        XCTAssertEqual(advice.suggestions[0].severity.id, "critical")
        XCTAssertEqual(advice.suggestions[0].severity.icon, "🚨")
        XCTAssertEqual(advice.suggestions[0].severity.color, "red")
        XCTAssertEqual(advice.suggestions[0].suggestedCommand, "open -a 'Activity Monitor'")
        XCTAssertEqual(advice.suggestions[1].severity.id, "session-trim")
        XCTAssertNil(advice.suggestions[1].suggestedCommand)
    }

    func testAdviseThrowsInvalidResponseForMalformedJSONContent() async {
        let provider = LLMAdviceProvider(
            client: StubLLMClient(content: "analysis notes"),
            responseFormatter: StubResponseFormatter(content: "not json")
        )

        await XCTAssertThrowsErrorAsync(try await provider.advise(for: Fixtures.snapshot)) { error in
            XCTAssertEqual(error as? LLMError, .invalidResponse)
        }
    }

    func testMissingSeverityIconThrows() async {
        let provider = LLMAdviceProvider(client: StubLLMClient(content: "analysis notes"), responseFormatter: StubResponseFormatter(content: """
        {
          "summary": "A suggestion has an invalid severity object.",
          "statusBar": {
            "title": "!",
            "color": "red"
          },
          "suggestions": [
            {
              "title": "Check a runaway process",
              "detail": "A process is consuming significant CPU.",
              "rationale": "Severity display data should be treated as a response contract.",
              "severity": {
                "id": "critical",
                "label": "Critical",
                "icon": "",
                "color": "red"
              },
              "suggestedCommand": null,
              "targetProcessName": "Example"
            }
          ]
        }
        """))

        await XCTAssertThrowsErrorAsync(try await provider.advise(for: Fixtures.snapshot)) { error in
            XCTAssertEqual(error as? LLMError, .invalidResponse)
        }
    }

    func testAdviseAllowsEmptySuggestions() async throws {
        let provider = LLMAdviceProvider(client: StubLLMClient(content: "analysis notes"), responseFormatter: StubResponseFormatter(content: """
        { "summary": "No actionable load issue found.", "statusBar": { "title": "0", "color": "gray" }, "suggestions": [] }
        """))

        let advice = try await provider.advise(for: Fixtures.snapshot)

        XCTAssertEqual(advice.summary, "No actionable load issue found.")
        XCTAssertEqual(advice.statusBar.title, "0")
        XCTAssertTrue(advice.suggestions.isEmpty)
    }
}

private struct StubLLMClient: LLMClient {
    let content: String

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        ChatResponse(choices: [
            ChatResponseChoice(message: ChatMessage(role: "assistant", content: content))
        ])
    }
}

private struct StubResponseFormatter: ResponseFormatting {
    let content: String

    func format(analysis: String, languageIdentifier: String, model: String) throws -> String {
        content
    }
}
