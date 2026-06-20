import Foundation

/// Resolves a forced locale identifier to its `.lproj` sub-bundle inside `Bundle.module`.
///
/// The app drives a *chosen* UI language (config override or system locale), which the
/// system-bound `NSLocalizedString(_:comment:)` cannot honor — that one keys off the
/// process's preferred-language list. So we locate the exact `.lproj` for the requested
/// locale and read strings from that bundle. Missing keys fall back to en because the
/// returned bundle's own `Localizable.strings` is consulted; if the whole locale is
/// absent we hand back `.module` (default localization = en).
enum LocalizationBundle {
    private static var cache: [String: Bundle] = [:]
    private static let lock = NSLock()

    static func bundle(for languageIdentifier: String) -> Bundle {
        let key = languageIdentifier.isEmpty ? "en" : languageIdentifier
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let resolved = resolve(key)
        cache[key] = resolved
        return resolved
    }

    private static func resolve(_ identifier: String) -> Bundle {
        for candidate in candidates(for: identifier) {
            // SwiftPM lowercases generated .lproj directory names (e.g. `zh-hans.lproj`,
            // `pt-br.lproj`), and path(forResource:) is case-sensitive — so match lowercased.
            if let path = Bundle.module.path(forResource: candidate.lowercased(), ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .module
    }

    /// Ordered most-specific → least-specific `.lproj` names to try, always ending at "en".
    /// Handles Chinese script collapse (zh → zh-Hans/zh-Hant) and pt → pt-BR since those
    /// are the only Chinese/Portuguese variants we ship.
    private static func candidates(for identifier: String) -> [String] {
        let locale = Locale(identifier: identifier)
        let language = locale.language.languageCode?.identifier.lowercased()
            ?? String(identifier.prefix(2)).lowercased()
        let script = locale.language.script?.identifier            // e.g. "Hans"/"Hant"
        let region = locale.region?.identifier                     // e.g. "KR"/"BR"/"TW"

        var list: [String] = [identifier]
        let dashed = identifier.replacingOccurrences(of: "_", with: "-")
        if dashed != identifier { list.append(dashed) }

        if language == "zh" {
            if let script { list.append("zh-\(script)") }
            if let region {
                list.append(["TW", "HK", "MO"].contains(region) ? "zh-Hant" : "zh-Hans")
            }
            list.append("zh-Hans")   // bare "zh" → Simplified
        }
        if language == "pt" { list.append("pt-BR") }   // only Brazilian Portuguese shipped

        if let region { list.append("\(language)-\(region)") }
        if let script { list.append("\(language)-\(script)") }
        list.append(language)
        list.append("en")
        return list
    }
}

/// User-facing UI chrome text. Construct with the *resolved* locale identifier (config
/// override or system locale); all strings come from that locale's `.lproj`, falling back
/// to English. Analysis-output language is a separate concern handled in the prompts.
public struct AppStrings {
    public let languageIdentifier: String
    private let bundle: Bundle

    public init(languageIdentifier: String) {
        self.languageIdentifier = languageIdentifier
        self.bundle = LocalizationBundle.bundle(for: languageIdentifier)
    }

    private func str(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    /// `String(format:)` over a localized template. `%@` placeholders take Swift strings
    /// (numbers are stringified at the call site so format specifiers stay locale-safe).
    private func fmt(_ key: String, _ args: CVarArg...) -> String {
        String(format: str(key), arguments: args)
    }

    public var appAccessibilityDescription: String { str("app.accessibility") }
    public var appTooltip: String { str("app.tooltip") }
    public var analysisWaiting: String { str("analysis.waiting") }
    public var configurationWarningTitle: String { str("config.warning.title") }
    public var analyzing: String { str("analyzing") }
    public var noSuggestions: String { str("suggestions.none") }
    public var analyzeNow: String { str("analyze.now") }
    public var settingsMenuItem: String { str("menu.settings") }
    public var checkForUpdatesMenuItem: String { str("menu.checkForUpdates") }
    public var quit: String { str("menu.quit") }
    public var openCommandInTerminal: String { str("action.showInTerminal") }
    public var reviewWithClaude: String { str("action.reviewWithClaude") }
    /// Provider-aware variant of the review action label (e.g. "Review with Codex CLI").
    public func reviewWith(provider: String) -> String { fmt("action.reviewWith", provider) }
    public var copyCommand: String { str("action.copyCommand") }
    public var runCommandNow: String { str("action.runNow") }
    public var runCommandDone: String { str("action.runDone") }
    public var dangerousCommandTitle: String { str("dangerous.title") }
    public var runAnyway: String { str("action.run") }
    public var checkingCommandSafety: String { str("safety.checking") }
    public var runningCommand: String { str("command.running") }
    public var resultWindowTitle: String { str("result.windowTitle") }
    public var clickToViewOutput: String { str("result.clickToView") }
    public var noOutput: String { str("result.noOutput") }
    public var exitCodeLabel: String { str("result.exitCodeLabel") }
    public var ranWithAdministrator: String { str("result.ranWithAdmin") }
    public var safetyCheckUnavailable: String { str("safety.unavailable") }

    public func dangerousCommandPrompt(reason: String, command: String) -> String {
        let reasonLine = reason.isEmpty ? "" : (fmt("dangerous.prompt.reasonPrefix", reason) + "\n\n")
        let lead = str("dangerous.prompt.lead")
        return "\(lead)\n\n\(reasonLine)\(command)"
    }

    public func commandSucceededTitle(_ command: String) -> String { "✅ \(command)" }
    public func commandFailedTitle(_ command: String) -> String { "❌ \(command)" }

    public func commandResultBody(exitCode: Int32, durationSeconds: Double) -> String {
        let duration = String(format: "%.1fs", max(0, durationSeconds))
        return "\(exitCodeLabel) \(exitCode) · \(duration) · \(clickToViewOutput)"
    }
    public var terminalOpenFailed: String { str("terminal.openFailed") }
    public func terminalAppNotFound(_ bundleIdentifier: String) -> String {
        let id = bundleIdentifier.isEmpty ? str("terminal.appNotFound.none") : bundleIdentifier
        return fmt("terminal.appNotFound", id)
    }
    public var missingClaudeCLITitle: String { str("claude.missing.title") }
    public var missingClaudeCLIMessage: String { str("claude.missing.message") }
    public var claudeReviewOpenFailed: String { str("claude.reviewOpenFailed") }
    public var settingsSavedRefreshing: String { str("settings.savedRefreshing") }
    public var settingsSaveFailed: String { str("settings.saveFailed") }
    public var ok: String { str("ok") }
    public var memoryShortLabel: String { str("mem.short") }
    public var reasonLabel: String { str("reason.label") }
    public var macOptimizerFailedPrefix: String { str("macOptimizer.failedPrefix") }
    public var settingsWindowTitle: String { str("settings.windowTitle") }
    public var providerLabel: String { str("settings.providerLabel") }
    public var modelLabel: String { str("settings.modelLabel") }
    public var thinkingLevelLabel: String { str("settings.thinkingLevelLabel") }
    public var fastModeLabel: String { str("settings.fastModeLabel") }
    public var fastModeCheckbox: String { str("settings.fastModeCheckbox") }
    public var customModelOption: String { str("settings.customModelOption") }
    public var analysisIntervalLabel: String { str("settings.analysisIntervalLabel") }

    /// Short label for a discrete analysis-interval step (e.g. "60m"/"2h"). Steps up to
    /// 60 minutes read as minutes; longer steps read as whole hours.
    public func intervalLabel(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes <= 60 {
            return fmt("interval.minutes", "\(minutes)")
        }
        let hours = minutes / 60
        return fmt("interval.hours", "\(hours)")
    }

    /// Label for the unified UI + analysis language selector.
    public var languageLabel: String { str("settings.languageLabel") }
    /// Popup entry that defers to the current macOS language.
    public var systemDefaultLanguage: String { str("settings.language.systemDefault") }
    public var monitorDurationLabel: String { str("settings.monitorDurationLabel") }

    /// Value label for the monitor-duration slider; 0 reads as "off".
    public func monitorDurationValue(seconds: Int) -> String {
        if seconds <= 0 {
            return str("monitor.off")
        }
        return fmt("monitor.seconds", "\(seconds)")
    }
    public var terminalAppLabel: String { str("settings.terminalAppLabel") }
    public var noTerminalAppsDetected: String { str("settings.noTerminalAppsDetected") }
    public var save: String { str("save") }
    public var cancel: String { str("cancel") }
    public var terminalCommandHeader: String { str("terminal.commandHeader") }
    public var terminalCommandFooter: String { str("terminal.commandFooter") }
    public var claudeReviewStarting: String { str("claude.reviewStarting") }
    public var claudeNotExecutable: String { str("claude.notExecutable") }
    public var reviewPromptMissing: String { str("claude.reviewPromptMissing") }

    public func detectedMacOSLanguages(_ summary: String) -> String {
        fmt("detectedMacOSLanguages", summary)
    }

    public func currentAnalysisLanguage(_ language: String) -> String {
        fmt("currentAnalysisLanguage", language)
    }

    public func analysisFailed(_ message: String) -> String {
        fmt("analysisFailed", message)
    }

    public func analyzingElapsed(seconds: Int) -> String {
        fmt("analyzingElapsed", formatElapsed(seconds: seconds))
    }

    /// English-language error surfaces moved off inline `isKorean` branches in AppDelegate.
    public func providerCLINotFound(provider: String) -> String {
        fmt("error.providerCLINotFound", provider)
    }
    public var invalidResponseFormat: String { str("error.invalidResponseFormat") }
    public func decodingError(_ message: String) -> String {
        fmt("error.decodingError", message)
    }

    public var lastCheckedLabel: String { str("lastChecked.label") }

    /// Coarse "X ago" phrase for the menu-bar last-check time. The exact clock time
    /// is shown separately inside the dropdown (see `AdviceFormatter.lastCheckTimeString`).
    public func relativeTimeAgo(secondsAgo: Int) -> String {
        let s = max(0, secondsAgo)
        if s < 10 { return str("time.justNow") }
        if s < 60 { return fmt("time.secondsAgo", "\(s)") }
        let minutes = s / 60
        if minutes < 60 { return fmt("time.minutesAgo", "\(minutes)") }
        let hours = minutes / 60
        if hours < 24 { return fmt("time.hoursAgo", "\(hours)") }
        let days = hours / 24
        return fmt("time.daysAgo", "\(days)")
    }

    private func formatElapsed(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        if safeSeconds < 60 {
            return fmt("elapsed.seconds", "\(safeSeconds)")
        }

        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        if minutes < 60 {
            return fmt("elapsed.minutesSeconds", "\(minutes)", "\(remainingSeconds)")
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return fmt("elapsed.hoursMinutes", "\(hours)", "\(remainingMinutes)")
    }

    public func processFailed(status: Int32, message: String) -> String {
        let suffix = message.isEmpty ? "" : ": \(message)"
        return fmt("process.failed", "\(status)", suffix)
    }
}
