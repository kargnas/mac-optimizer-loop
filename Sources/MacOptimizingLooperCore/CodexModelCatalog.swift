import Foundation

/// Reads the model list codex caches at `$CODEX_HOME/models_cache.json` (default
/// `~/.codex/models_cache.json`). This is codex's own registry, so the app never
/// hardcodes codex model names. A missing/unreadable/garbled cache yields an empty
/// catalog (non-fatal) — the UI then offers free-text "Custom…" entry.
public struct CodexModelCatalog: ProviderCataloging {
    private let environment: [String: String]
    private let explicitCacheURL: URL?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheURL: URL? = nil
    ) {
        self.environment = environment
        self.explicitCacheURL = cacheURL
    }

    public func load() -> ProviderCatalog {
        let url = explicitCacheURL ?? Self.defaultCacheURL(environment: environment)
        guard let data = try? Data(contentsOf: url) else {
            return ProviderCatalog(models: [])
        }
        return Self.parse(data)
    }

    public static func defaultCacheURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
                .appendingPathComponent("models_cache.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
    }

    /// Parses the cache payload into a catalog. Exposed for tests with fixtures.
    public static func parse(_ data: Data) -> ProviderCatalog {
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return ProviderCatalog(models: [])
        }
        let models: [ProviderModel] = cache.models.compactMap { model in
            // Only models codex itself marks listable; skip hidden/internal entries.
            // Treat a missing visibility as listable so a schema tweak never hides everything.
            if let visibility = model.visibility, visibility != "list" {
                return nil
            }
            let efforts = (model.supported_reasoning_levels ?? []).map {
                ProviderEffort(level: $0.effort, description: $0.description ?? "")
            }
            guard !efforts.isEmpty else { return nil }
            let supportsFast = (model.service_tiers ?? []).contains { $0.id == "priority" }
                || (model.additional_speed_tiers ?? []).contains("fast")
            let defaultEffort = model.default_reasoning_level
                ?? efforts.first?.level
                ?? ""
            return ProviderModel(
                slug: model.slug,
                displayName: model.display_name ?? model.slug,
                efforts: efforts,
                defaultEffort: defaultEffort,
                supportsFastMode: supportsFast
            )
        }
        return ProviderCatalog(models: models)
    }

    // MARK: - Decodable mirror of the codex cache (only the fields we consume)

    private struct Cache: Decodable {
        let models: [Model]
    }

    private struct Model: Decodable {
        let slug: String
        let display_name: String?
        let default_reasoning_level: String?
        let supported_reasoning_levels: [ReasoningLevel]?
        let visibility: String?
        let additional_speed_tiers: [String]?
        let service_tiers: [ServiceTier]?
    }

    private struct ReasoningLevel: Decodable {
        let effort: String
        let description: String?
    }

    private struct ServiceTier: Decodable {
        let id: String
    }
}
