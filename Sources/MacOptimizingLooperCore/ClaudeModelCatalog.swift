import Foundation

/// The `claude` CLI exposes no "list models" command, so this is a curated alias set.
/// Aliases (not dated ids) are used so each always resolves to the latest of its tier.
/// `supportsFastMode` is false everywhere: the CLI has no service-tier/fast flag, so we
/// do not advertise a toggle we cannot honor.
public struct ClaudeModelCatalog: ProviderCataloging {
    public init() {}

    public func load() -> ProviderCatalog {
        let efforts = AppConfig.validThinkingLevels.map { level in
            ProviderEffort(level: level, description: Self.effortDescription(level))
        }
        let aliases: [(slug: String, name: String)] = [
            ("opus", "Opus"),
            ("sonnet", "Sonnet"),
            ("haiku", "Haiku"),
            ("fable", "Fable")
        ]
        let models = aliases.map { alias in
            ProviderModel(
                slug: alias.slug,
                displayName: alias.name,
                efforts: efforts,
                defaultEffort: "max",
                supportsFastMode: false
            )
        }
        return ProviderCatalog(models: models)
    }

    private static func effortDescription(_ level: String) -> String {
        switch level {
        case "low": return "Fastest, lightest reasoning"
        case "medium": return "Balanced speed and depth"
        case "high": return "Deeper reasoning"
        case "xhigh": return "Extra-deep reasoning"
        case "max": return "Maximum reasoning depth"
        default: return level
        }
    }
}
