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

    public init(model: String, system: String, user: String, maxTokens: Int, temperature: Double) {
        self.model = model
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public protocol LLMClient {
    func complete(_ request: ChatRequest) async throws -> ChatResponse
}

public enum LLMError: Error, Equatable {
    case missingClaudeCLI
    case processFailed(Int32, String)
    case invalidResponse
    case decoding(String)
}
