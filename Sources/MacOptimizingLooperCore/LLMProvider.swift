import Foundation

/// The set of LLM CLI backends the app can drive. Adding a provider is one case here
/// plus a client + catalog registered in `ProviderRegistry`. `claude` stays the default
/// so existing configs are unaffected.
public enum LLMProviderKind: String, CaseIterable, Sendable, Equatable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Whether the provider can return a JSON answer constrained to a supplied schema
    /// in a single call. When true, `LLMAdviceProvider` asks for JSON directly and skips
    /// the claude-style free-form → formatter second pass. See the design doc.
    public var supportsStructuredOutput: Bool {
        switch self {
        case .claude: return false   // free-form text; format-json.sh does the JSON pass
        case .codex: return true     // codex exec --output-schema returns final JSON
        }
    }

    /// Resolves a stored config string to a known provider, defaulting to `.claude`
    /// for empty/unknown values so a typo never silently breaks analysis.
    public static func resolved(_ raw: String) -> LLMProviderKind {
        LLMProviderKind(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .claude
    }
}

// MARK: - Catalog

/// One selectable reasoning level for a model, with the CLI's own human description.
public struct ProviderEffort: Equatable, Sendable {
    public let level: String
    public let description: String

    public init(level: String, description: String) {
        self.level = level
        self.description = description
    }
}

/// A model offered by a provider, with the reasoning levels and fast-tier support
/// discovered from the CLI (or curated where the CLI exposes no list).
public struct ProviderModel: Equatable, Sendable {
    public let slug: String
    public let displayName: String
    public let efforts: [ProviderEffort]
    public let defaultEffort: String
    public let supportsFastMode: Bool

    public init(slug: String, displayName: String, efforts: [ProviderEffort], defaultEffort: String, supportsFastMode: Bool) {
        self.slug = slug
        self.displayName = displayName
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.supportsFastMode = supportsFastMode
    }

    public var effortLevels: [String] { efforts.map(\.level) }
}

/// The models a provider can offer right now. Empty `models` is a valid, non-fatal
/// state (e.g. codex cache missing) — the UI falls back to free-text "Custom…" entry.
public struct ProviderCatalog: Equatable, Sendable {
    public let models: [ProviderModel]

    public init(models: [ProviderModel]) {
        self.models = models
    }

    public func model(slug: String) -> ProviderModel? {
        let needle = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        return models.first { $0.slug == needle }
    }
}

public protocol ProviderCataloging {
    /// Loads the current catalog. MUST NOT throw: discovery failure returns an empty
    /// catalog so the settings UI degrades to custom entry instead of erroring.
    func load() -> ProviderCatalog
}

// MARK: - Registry

/// Builds clients and catalogs from plain config values. Inputs are all `Sendable`
/// (strings/bools) so a client can be constructed inside a detached task without
/// capturing anything non-Sendable.
public enum ProviderRegistry {
    public static func makeClient(
        kind: LLMProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LLMClient {
        switch kind {
        case .claude:
            return ClaudeCLIClient(environment: environment)
        case .codex:
            return CodexCLIClient(environment: environment)
        }
    }

    public static func catalog(
        kind: LLMProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProviderCataloging {
        switch kind {
        case .claude:
            return ClaudeModelCatalog()
        case .codex:
            return CodexModelCatalog(environment: environment)
        }
    }
}
