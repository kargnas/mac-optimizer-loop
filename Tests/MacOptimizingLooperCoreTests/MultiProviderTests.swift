import XCTest
@testable import MacOptimizingLooperCore

final class MultiProviderTests: XCTestCase {
    // MARK: - Provider kind

    func testResolvedProviderDefaultsToClaude() {
        XCTAssertEqual(LLMProviderKind.resolved(""), .claude)
        XCTAssertEqual(LLMProviderKind.resolved("  CODEX "), .codex)
        XCTAssertEqual(LLMProviderKind.resolved("claude"), .claude)
        XCTAssertEqual(LLMProviderKind.resolved("nonsense"), .claude)
    }

    func testStructuredOutputCapability() {
        XCTAssertFalse(LLMProviderKind.claude.supportsStructuredOutput)
        XCTAssertTrue(LLMProviderKind.codex.supportsStructuredOutput)
    }

    // MARK: - Codex catalog parsing

    func testCodexCatalogParsesModelsEffortsAndPriorityTier() {
        let json = """
        {"models":[
          {"slug":"gpt-5.5","display_name":"GPT-5.5","default_reasoning_level":"medium",
           "supported_reasoning_levels":[{"effort":"low","description":"fast"},{"effort":"high","description":"deep"}],
           "visibility":"list","service_tiers":[{"id":"priority"}]},
          {"slug":"hidden-model","visibility":"hidden",
           "supported_reasoning_levels":[{"effort":"low"}]},
          {"slug":"no-efforts","visibility":"list"}
        ]}
        """
        let catalog = CodexModelCatalog.parse(Data(json.utf8))
        // hidden-model (not listable) and no-efforts (empty levels) are dropped.
        XCTAssertEqual(catalog.models.count, 1)
        let model = try! XCTUnwrap(catalog.models.first)
        XCTAssertEqual(model.slug, "gpt-5.5")
        XCTAssertEqual(model.displayName, "GPT-5.5")
        XCTAssertEqual(model.defaultEffort, "medium")
        XCTAssertEqual(model.effortLevels, ["low", "high"])
        XCTAssertTrue(model.supportsFastMode)
    }

    func testCodexCatalogFastTierViaAdditionalSpeedTiers() {
        let json = """
        {"models":[{"slug":"m","supported_reasoning_levels":[{"effort":"low"}],"additional_speed_tiers":["fast"]}]}
        """
        let catalog = CodexModelCatalog.parse(Data(json.utf8))
        XCTAssertEqual(catalog.models.first?.supportsFastMode, true)
    }

    func testCodexCatalogNoFastTierWhenAbsent() {
        let json = """
        {"models":[{"slug":"m","supported_reasoning_levels":[{"effort":"low"}]}]}
        """
        let catalog = CodexModelCatalog.parse(Data(json.utf8))
        XCTAssertEqual(catalog.models.first?.supportsFastMode, false)
    }

    func testCodexCatalogEmptyOnGarbage() {
        XCTAssertTrue(CodexModelCatalog.parse(Data("not json".utf8)).models.isEmpty)
    }

    // MARK: - Claude catalog

    func testClaudeCatalogIsCuratedWithoutFastMode() {
        let catalog = ClaudeModelCatalog().load()
        XCTAssertTrue(catalog.models.contains { $0.slug == "sonnet" })
        XCTAssertTrue(catalog.models.contains { $0.slug == "opus" })
        // The claude CLI has no fast/service-tier flag, so no model advertises one.
        XCTAssertTrue(catalog.models.allSatisfy { !$0.supportsFastMode })
        XCTAssertEqual(catalog.models.first?.effortLevels, AppConfig.validThinkingLevels)
    }

    // MARK: - Codex client argument construction

    private func codexArgs(_ request: ChatRequest) -> [String] {
        CodexCLIClient().arguments(
            for: request,
            lastMessageURL: URL(fileURLWithPath: "/tmp/out"),
            schemaURL: URL(fileURLWithPath: "/tmp/schema")
        )
    }

    func testCodexArgumentsIncludeModelEffortFastAndSchema() {
        let args = codexArgs(ChatRequest(
            model: "gpt-5.5", system: "sys", user: "user", maxTokens: 0, temperature: 0,
            effort: "high", fastMode: true, outputSchema: "{}"
        ))
        XCTAssertEqual(args.first, "exec")
        XCTAssertTrue(args.contains("--skip-git-repo-check"))
        XCTAssertTrue(adjacent(args, "-m", "gpt-5.5"))
        XCTAssertTrue(adjacent(args, "-c", "model_reasoning_effort=\"high\""))
        XCTAssertTrue(adjacent(args, "-c", "service_tier=\"priority\""))
        XCTAssertTrue(adjacent(args, "--output-schema", "/tmp/schema"))
        XCTAssertTrue(adjacent(args, "-o", "/tmp/out"))
        // System+user are folded into the final prompt argument.
        XCTAssertEqual(args.last, "sys\n\nuser")
    }

    func testCodexArgumentsOmitFastAndSchemaWhenUnset() {
        let args = codexArgs(ChatRequest(
            model: "gpt-5.5", system: "", user: "u", maxTokens: 0, temperature: 0,
            effort: "low", fastMode: false, outputSchema: nil
        ))
        XCTAssertFalse(args.contains("service_tier=\"priority\""))
        XCTAssertFalse(args.contains("--output-schema"))
        XCTAssertTrue(adjacent(args, "-o", "/tmp/out"))
        XCTAssertEqual(args.last, "u")   // empty system → just the user prompt
    }

    func testCombinedPrompt() {
        XCTAssertEqual(CodexCLIClient.combinedPrompt(system: "  ", user: "only"), "only")
        XCTAssertEqual(CodexCLIClient.combinedPrompt(system: "S", user: "U"), "S\n\nU")
    }

    // MARK: - Config provider / fastMode

    func testConfigBackwardCompatDefaultsToClaude() throws {
        let config = try AppConfig.load(environment: [:], fileContents: Data("{\"model\":\"sonnet\"}".utf8))
        XCTAssertEqual(config.provider, "claude")
        XCTAssertEqual(config.resolvedProviderKind, .claude)
        XCTAssertFalse(config.fastMode)
    }

    func testConfigLoadsProviderAndFastMode() throws {
        let json = "{\"provider\":\"codex\",\"fastMode\":true,\"model\":\"gpt-5.5\"}"
        let config = try AppConfig.load(environment: [:], fileContents: Data(json.utf8))
        XCTAssertEqual(config.resolvedProviderKind, .codex)
        XCTAssertTrue(config.fastMode)
        XCTAssertEqual(config.model, "gpt-5.5")
    }

    func testConfigNormalizesUnknownProvider() throws {
        let config = try AppConfig.load(environment: [:], fileContents: Data("{\"provider\":\"weird\"}".utf8))
        XCTAssertEqual(config.provider, "claude")
    }

    // MARK: - Structured risk verdict

    func testParseStructuredVerdict() {
        XCTAssertEqual(CommandRiskAssessor.parseStructured("{\"risk\":\"DANGEROUS\",\"reason\":\"deletes files\"}").level, .dangerous)
        XCTAssertEqual(CommandRiskAssessor.parseStructured("{\"risk\":\"SAFE\",\"reason\":\"read only\"}").level, .safe)
        // Non-JSON falls back to the lenient text parser → unknown (still prompts).
        XCTAssertEqual(CommandRiskAssessor.parseStructured("totally not json").level, .unknown)
    }

    // MARK: - Advice provider structured branch

    func testStructuredProviderSkipsFormatter() async throws {
        let json = """
        {"summary":"all good","statusBar":{"title":"0","color":"green"},"suggestions":[]}
        """
        let provider = LLMAdviceProvider(
            client: JSONStubClient(content: json),
            config: AppConfig.defaults(environment: [:]),
            responseFormatter: FailingFormatter(),
            supportsStructuredOutput: true
        )
        let advice = try await provider.advise(for: Fixtures.snapshot)
        XCTAssertEqual(advice.summary, "all good")
        XCTAssertEqual(advice.statusBar.title, "0")
        XCTAssertTrue(advice.suggestions.isEmpty)
    }

    func testAdviceJSONSchemaIsValidJSON() {
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(PromptBuilder.adviceJSONSchema.utf8)))
    }

    // MARK: - Helpers

    private func adjacent(_ args: [String], _ flag: String, _ value: String) -> Bool {
        for index in args.indices.dropLast() where args[index] == flag && args[index + 1] == value {
            return true
        }
        return false
    }
}

private struct JSONStubClient: LLMClient {
    let content: String
    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        ChatResponse(choices: [ChatResponseChoice(message: ChatMessage(role: "assistant", content: content))])
    }
}

private struct FailingFormatter: ResponseFormatting {
    func format(analysis: String, languageIdentifier: String, model: String) throws -> String {
        XCTFail("formatter must not run on a structured-output provider")
        throw LLMError.invalidResponse
    }
}
