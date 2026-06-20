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

/// Asks the configured provider (`claude -p` or `codex exec`) whether a shell command
/// is risky BEFORE the app runs it. The user-approved "다시 한번 더 확인" gate on top of
/// the explicit click.
public struct CommandRiskAssessor {
    public init() {}

    /// Runs the classification off the main thread (the underlying CLI call blocks).
    /// Throws only if the CLI invocation itself fails; an ambiguous reply maps to
    /// `.unknown` so the caller still prompts.
    public func assess(
        command: String,
        provider: LLMProviderKind,
        model: String,
        effort: String,
        fastMode: Bool,
        languageIdentifier: String
    ) async throws -> CommandRiskVerdict {
        let systemPrompt = Self.systemPrompt(languageIdentifier: languageIdentifier)
        let structured = provider.supportsStructuredOutput
        return try await Task.detached(priority: .userInitiated) {
            // Build the client inside the detached task from plain Sendable values so
            // nothing non-Sendable crosses the boundary.
            let client = ProviderRegistry.makeClient(kind: provider)
            let response = try await client.complete(ChatRequest(
                model: model,
                system: systemPrompt,
                user: "Classify this macOS shell command:\n\n\(command)",
                maxTokens: 256,
                temperature: 0,
                effort: effort,
                fastMode: fastMode,
                outputSchema: structured ? Self.verdictJSONSchema : nil
            ))
            let text = response.choices.first?.message.content ?? ""
            return structured ? Self.parseStructured(text) : Self.parse(text)
        }.value
    }

    /// JSON schema for the structured (codex) verdict path.
    static let verdictJSONSchema = """
    {"type":"object","additionalProperties":false,"required":["risk","reason"],"properties":{"risk":{"type":"string","enum":["SAFE","DANGEROUS"]},"reason":{"type":"string"}}}
    """

    private struct StructuredVerdict: Decodable {
        let risk: String
        let reason: String
    }

    /// Parses the JSON verdict from a structured provider. Falls back to the lenient
    /// text parser if the payload is not the expected JSON, so a stray wrapper never
    /// silently downgrades to a wrong verdict.
    static func parseStructured(_ text: String) -> CommandRiskVerdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end,
              let data = String(trimmed[start...end]).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(StructuredVerdict.self, from: data) else {
            return parse(text)
        }
        let level: CommandRiskVerdict.Level = decoded.risk.uppercased().contains("DANGEROUS") ? .dangerous : .safe
        return CommandRiskVerdict(level: level, reason: decoded.reason)
    }

    static func systemPrompt(languageIdentifier: String) -> String {
        // English exonym of the target locale (e.g. "Korean", "Japanese",
        // "Portuguese (Brazil)") so the model writes REASON in the user's language.
        let reasonLanguage = Locale(identifier: "en")
            .localizedString(forIdentifier: languageIdentifier) ?? "English"
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
