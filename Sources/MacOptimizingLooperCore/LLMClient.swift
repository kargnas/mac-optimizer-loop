import Foundation

public struct ChatMessage: Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatResponseChoice: Codable {
    public let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
    }
}

public struct ChatResponse: Codable {
    public let choices: [ChatResponseChoice]

    public init(choices: [ChatResponseChoice]) {
        self.choices = choices
    }
}

public struct ChatRequest {
    public let model: String
    public let system: String
    public let user: String
    public let maxTokens: Int
    public let temperature: Double
    /// Reasoning level passed to the backend (claude `--effort`, codex
    /// `model_reasoning_effort`). Provider-relative; clamped by the caller.
    public let effort: String
    /// Requests the provider's faster service tier when the chosen model supports it
    /// (codex `service_tier=priority`). No-op for providers without a fast tier.
    public let fastMode: Bool
    /// JSON Schema (as a string) the final answer must conform to. Only used by
    /// providers that advertise `supportsStructuredOutput` (codex `--output-schema`);
    /// nil means a plain free-form text answer.
    public let outputSchema: String?

    public init(
        model: String,
        system: String,
        user: String,
        maxTokens: Int,
        temperature: Double,
        effort: String = "low",
        fastMode: Bool = false,
        outputSchema: String? = nil
    ) {
        self.model = model
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.effort = effort
        self.fastMode = fastMode
        self.outputSchema = outputSchema
    }
}

public protocol LLMClient {
    func complete(_ request: ChatRequest) async throws -> ChatResponse
}

public enum LLMError: Error, Equatable {
    case missingClaudeCLI
    /// A configured provider's CLI executable could not be located. The associated
    /// value is the provider's display name (e.g. "Codex") for user-facing messages.
    case missingProviderCLI(String)
    case processFailed(Int32, String)
    case invalidResponse
    case decoding(String)
}
