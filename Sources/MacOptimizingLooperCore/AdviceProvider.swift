import Foundation

public protocol AdviceProviding {
    func advise(for snapshot: SystemSnapshot, optimizerReport: MacOptimizerReport?) async throws -> Advice
}

public extension AdviceProviding {
    func advise(for snapshot: SystemSnapshot) async throws -> Advice {
        try await advise(for: snapshot, optimizerReport: nil)
    }
}

public struct LLMAdviceResponse: Codable {
    public let summary: String
    public let statusBar: StatusBarDisplay
    public let suggestions: [SuggestionDTO]
}

public struct SuggestionDTO: Codable {
    public let title: String
    public let detail: String
    public let rationale: String
    public let severity: Severity
    public let suggestedCommand: String?
    public let targetProcessName: String?
}

public struct LLMAdviceProvider: AdviceProviding {
    private let client: LLMClient
    private let config: AppConfig
    private let responseFormatter: ResponseFormatting

    public init(
        client: LLMClient,
        config: AppConfig = AppConfig.defaults(environment: [:]),
        responseFormatter: ResponseFormatting = ShellResponseFormatterProvider()
    ) {
        self.client = client
        self.config = config
        self.responseFormatter = responseFormatter
    }

    public func advise(for snapshot: SystemSnapshot, optimizerReport: MacOptimizerReport? = nil) async throws -> Advice {
        let languageIdentifier = config.resolvedOutputLanguageIdentifier()
        let analysisResponse = try await client.complete(ChatRequest(
            model: config.model,
            system: PromptBuilder.analysisSystemPrompt(outputLanguageIdentifier: languageIdentifier),
            user: PromptBuilder.userPrompt(for: snapshot, optimizerReport: optimizerReport),
            maxTokens: config.maxTokens,
            temperature: config.temperature
        ))

        guard let analysis = analysisResponse.choices.first?.message.content,
              !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse
        }

        let content = try responseFormatter.format(
            analysis: analysis,
            languageIdentifier: languageIdentifier,
            model: config.model
        )

        guard let data = Self.extractJSONObject(from: content).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LLMAdviceResponse.self, from: data) else {
            throw LLMError.invalidResponse
        }

        guard !decoded.statusBar.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !decoded.statusBar.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse
        }

        let suggestions = try decoded.suggestions.map { dto in
            guard !dto.severity.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !dto.severity.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !dto.severity.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.invalidResponse
            }

            return Suggestion(
                title: dto.title,
                detail: dto.detail,
                rationale: dto.rationale,
                severity: dto.severity,
                suggestedCommand: dto.suggestedCommand,
                targetProcessName: dto.targetProcessName
            )
        }

        return Advice(
            generatedAt: snapshot.timestamp,
            summary: decoded.summary,
            statusBar: decoded.statusBar,
            suggestions: suggestions
        )
    }

    private static func extractJSONObject(from content: String) -> String {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start <= end else {
            return content
        }
        return String(content[start...end])
    }
}
