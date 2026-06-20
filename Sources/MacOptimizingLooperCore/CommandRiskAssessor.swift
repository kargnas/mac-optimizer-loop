import Foundation

/// Verdict from the pre-execution safety check. `unknown` means the check itself
/// could not be completed (e.g. claude CLI missing) — callers MUST treat it like
/// `dangerous` and require explicit confirmation, never run silently.
public struct CommandRiskVerdict: Sendable, Equatable {
    public enum Level: String, Sendable {
        case safe
        case dangerous
        case unknown
    }

    public let level: Level
    public let reason: String

    public init(level: Level, reason: String) {
        self.level = level
        self.reason = reason
    }

    /// Only an explicit `safe` verdict skips the confirmation prompt; anything else
    /// (including `unknown`) is treated as needing the user's go-ahead.
    public var requiresConfirmation: Bool { level != .safe }
}

/// Asks `claude -p` whether a shell command is risky BEFORE the app runs it. This
/// is the user-approved "다시 한번 더 확인" gate on top of the explicit click.
public struct CommandRiskAssessor {
    public init() {}

    /// Runs the classification off the main thread (the underlying claude call
    /// blocks). Throws only if the CLI invocation itself fails; an ambiguous model
    /// reply maps to `.unknown` so the caller still prompts.
    public func assess(
        command: String,
        model: String,
        languageIdentifier: String
    ) async throws -> CommandRiskVerdict {
        let systemPrompt = Self.systemPrompt(languageIdentifier: languageIdentifier)
        return try await Task.detached(priority: .userInitiated) {
            // Construct the client inside the detached task so nothing non-Sendable
            // is captured across the boundary — only plain Strings cross.
            let client = ClaudeCLIClient()
            let response = try await client.complete(ChatRequest(
                model: model,
                system: systemPrompt,
                user: "Classify this macOS shell command:\n\n\(command)",
                maxTokens: 256,
                temperature: 0
            ))
            let text = response.choices.first?.message.content ?? ""
            return Self.parse(text)
        }.value
    }

    static func systemPrompt(languageIdentifier: String) -> String {
        let isKorean = languageIdentifier.lowercased().hasPrefix("ko")
        let reasonLanguage = isKorean ? "Korean" : "English"
        return """
        You are a macOS shell-command safety classifier. Decide whether running the \
        given command could cause data loss, irreversible change, security exposure, \
        or major system disruption (e.g. deleting files, killing critical processes, \
        modifying system config, sudo/privileged changes, network exfiltration).

        Reply with EXACTLY two lines and nothing else:
        RISK: SAFE or RISK: DANGEROUS
        REASON: one short sentence written in \(reasonLanguage)

        Mark RISK: DANGEROUS whenever you are unsure. Do not execute anything.
        """
    }

    /// Parses the two-line verdict leniently. Presence of "DANGEROUS" wins; a clear
    /// "SAFE" with no danger marker is safe; anything else is `.unknown`.
    static func parse(_ text: String) -> CommandRiskVerdict {
        let upper = text.uppercased()
        let reason = extractReason(from: text)

        if upper.contains("DANGEROUS") {
            return CommandRiskVerdict(level: .dangerous, reason: reason)
        }
        // Match "SAFE" but not as part of "UNSAFE".
        if let regex = try? NSRegularExpression(pattern: "(^|[^A-Z])SAFE([^A-Z]|$)"),
           regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)) != nil {
            return CommandRiskVerdict(level: .safe, reason: reason)
        }
        return CommandRiskVerdict(level: .unknown, reason: reason)
    }

    private static func extractReason(from text: String) -> String {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("REASON:") {
                return String(trimmed.dropFirst("REASON:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
