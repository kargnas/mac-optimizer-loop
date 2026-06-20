import XCTest
@testable import MacOptimizingLooperCore

final class PromptBuilderTests: XCTestCase {
    func testAnalysisSystemPromptIsShortAndMacOptimizerFocused() {
        let prompt = PromptBuilder.analysisSystemPrompt(outputLanguageIdentifier: "ko-KR").lowercased()

        XCTAssertTrue(prompt.contains("/mac-optimizer"))
        XCTAssertTrue(prompt.contains("must not"))
        XCTAssertTrue(prompt.contains("ko-kr"))
        XCTAssertFalse(prompt.contains("return strict json matching this schema"))
    }

    func testUserPromptContainsLoadSummaryProcessesAndGuardrail() {
        let prompt = PromptBuilder.userPrompt(for: Fixtures.snapshot)

        XCTAssertTrue(prompt.contains("Use /mac-optimizer"))
        XCTAssertTrue(prompt.contains("CPU: 42%"))
        XCTAssertTrue(prompt.contains("Memory used: 71%"))
        XCTAssertTrue(prompt.contains("Chrome"))
        XCTAssertTrue(prompt.contains("separate CLI formatter pass"))
    }

    func testAdviceProviderUsesConfiguredOutputLanguage() async throws {
        let config = AppConfig(
            model: "sonnet",
            intervalSeconds: 3_600,
            outputLanguageIdentifier: "ko-KR",
            maxTokens: 8192,
            temperature: 0.2
        )
        let client = CapturingLanguageClient()
        let formatter = CapturingResponseFormatter()
        let provider = LLMAdviceProvider(client: client, config: config, responseFormatter: formatter)

        _ = try await provider.advise(for: Fixtures.snapshot)

        XCTAssertEqual(client.capturedLanguageIdentifier, "ko-KR")
        XCTAssertEqual(formatter.capturedLanguageIdentifier, "ko-KR")
        XCTAssertEqual(formatter.capturedModel, "sonnet")
        XCTAssertEqual(formatter.capturedAnalysis, "analysis notes")
    }

    func testUserPromptIncludesMacOptimizerReportWhenAvailable() {
        let report = MacOptimizerReport(scriptPath: "/tmp/mac-optimize.sh", output: "=== SYSTEM INFO ===")
        let prompt = PromptBuilder.userPrompt(for: Fixtures.snapshot, optimizerReport: report)

        XCTAssertTrue(prompt.contains("/tmp/mac-optimize.sh"))
        XCTAssertTrue(prompt.contains("=== SYSTEM INFO ==="))
    }
}

private final class CapturingLanguageClient: LLMClient {
    private(set) var capturedLanguageIdentifier: String?

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        if request.system.contains("ko-KR") {
            capturedLanguageIdentifier = "ko-KR"
        }
        return ChatResponse(choices: [
            ChatResponseChoice(message: ChatMessage(role: "assistant", content: "analysis notes"))
        ])
    }
}

private final class CapturingResponseFormatter: ResponseFormatting {
    private(set) var capturedAnalysis: String?
    private(set) var capturedLanguageIdentifier: String?
    private(set) var capturedModel: String?

    func format(analysis: String, languageIdentifier: String, model: String) throws -> String {
        capturedAnalysis = analysis
        capturedLanguageIdentifier = languageIdentifier
        capturedModel = model
        return #"{"summary":"ok","statusBar":{"title":"0","color":"gray"},"suggestions":[]}"#
    }
}
