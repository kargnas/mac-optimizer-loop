import Foundation

public enum TerminalScriptBuilder {
    public static func suggestedCommandDisplayScript(
        command: String,
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier
    ) -> String {
        let text = AppStrings(languageIdentifier: languageIdentifier)
        return """
        clear
        printf '%s\\n\\n' \(shellQuoted(text.terminalCommandHeader))
        printf '%s\\n\\n' \(shellQuoted(command))
        printf '%s\\n' \(shellQuoted(text.terminalCommandFooter))
        exec "${SHELL:-/bin/zsh}" -l
        """
    }

    public static func claudeReviewPrompt(
        for suggestion: Suggestion,
        outputLanguageIdentifier: String
    ) -> String {
        let command = suggestion.suggestedCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        You are a hands-on macOS performance assistant in an interactive terminal session,
        opened from the "Mac Optimizing Looper" app about the suggestion below.

        Output language: \(outputLanguageIdentifier). Write everything in this language.

        First, briefly assess the suggested command:
        - Risk level and why
        - Expected effect and any side effects
        - A safer, least-destructive alternative if one exists

        Then PROACTIVELY offer to go further — ask the user something like "시스템을 더 점검하고
        정리해 드릴까요?" (adapt the wording to the output language). If they agree, inspect the
        system yourself with read-only commands (top CPU/memory processes, memory pressure,
        runaway daemons, login/launch items, large caches and disk hogs), explain what you
        find, and help them clean it up step by step. Ask for explicit confirmation before
        running anything destructive. Never claim the Mac Optimizing Looper app already ran anything.

        --- Suggestion from Mac Optimizing Looper ---
        Severity: \(suggestion.severity.displayText) (\(suggestion.severity.id))
        Title: \(suggestion.title)
        Detail: \(suggestion.detail)
        Rationale: \(suggestion.rationale)
        Target process: \(suggestion.targetProcessName ?? "none")
        Suggested command: \(command?.isEmpty == false ? command! : "none")
        """
    }

    public static func claudeReviewScript(
        promptFilePath: String,
        claudeExecutablePath: String,
        model: String,
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier
    ) -> String {
        let text = AppStrings(languageIdentifier: languageIdentifier)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelArguments = model.isEmpty ? "" : " --model \(shellQuoted(model))"
        let promptPath = shellQuoted(promptFilePath)
        let claudePath = shellQuoted(claudeExecutablePath)
        let systemPrompt = shellQuoted("You are reviewing a macOS performance remediation suggestion. Be concise, practical, and safety-first.")

        return """
        clear
        _mac_load_advisor_prompt=\(promptPath)
        cleanup_prompt() { rm -f "$_mac_load_advisor_prompt" >/dev/null 2>&1 || true; }
        trap cleanup_prompt EXIT INT TERM
        printf '%s\\n\\n' \(shellQuoted(text.claudeReviewStarting))
        if [ ! -x \(claudePath) ]; then
          printf '%s\\n' \(shellQuoted(text.claudeNotExecutable))
        elif [ ! -f "$_mac_load_advisor_prompt" ]; then
          printf '%s\\n' \(shellQuoted(text.reviewPromptMissing))
        else
          # Interactive session (NOT -p): seed Claude with the review prompt so the
          # user can read the assessment and keep chatting. The prompt is read from
          # the file via "$(cat ...)" to avoid embedding multi-line/CJK text inline.
          \(claudePath) --append-system-prompt \(systemPrompt)\(modelArguments) "$(cat "$_mac_load_advisor_prompt")"
        fi
        cleanup_prompt
        trap - EXIT INT TERM
        printf '\\n'
        exec "${SHELL:-/bin/zsh}" -l
        """
    }

    /// codex counterpart of `claudeReviewScript`: opens an INTERACTIVE codex session
    /// (not `exec`) seeded with the review prompt, so the user can read the assessment
    /// and keep chatting. codex has no system-prompt flag, so the prompt carries all
    /// instructions (see `claudeReviewPrompt`, which is provider-neutral).
    public static func codexReviewScript(
        promptFilePath: String,
        codexExecutablePath: String,
        model: String,
        effort: String,
        fastMode: Bool,
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier
    ) -> String {
        let text = AppStrings(languageIdentifier: languageIdentifier)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let effort = effort.trimmingCharacters(in: .whitespacesAndNewlines)
        var optionArgs = ""
        if !model.isEmpty { optionArgs += " -m \(shellQuoted(model))" }
        if !effort.isEmpty { optionArgs += " -c \(shellQuoted("model_reasoning_effort=\"\(effort)\""))" }
        if fastMode { optionArgs += " -c \(shellQuoted("service_tier=\"priority\""))" }
        let promptPath = shellQuoted(promptFilePath)
        let codexPath = shellQuoted(codexExecutablePath)

        return """
        clear
        _mac_load_advisor_prompt=\(promptPath)
        cleanup_prompt() { rm -f "$_mac_load_advisor_prompt" >/dev/null 2>&1 || true; }
        trap cleanup_prompt EXIT INT TERM
        printf '%s\\n\\n' \(shellQuoted(text.claudeReviewStarting))
        if [ ! -x \(codexPath) ]; then
          printf '%s\\n' \(shellQuoted(text.claudeNotExecutable))
        elif [ ! -f "$_mac_load_advisor_prompt" ]; then
          printf '%s\\n' \(shellQuoted(text.reviewPromptMissing))
        else
          \(codexPath)\(optionArgs) "$(cat "$_mac_load_advisor_prompt")"
        fi
        cleanup_prompt
        trap - EXIT INT TERM
        printf '\\n'
        exec "${SHELL:-/bin/zsh}" -l
        """
    }

    public static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func appleScriptStringLiteral(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
