import Foundation

public struct StatusBarTitleParts: Equatable {
    public let emoji: String?
    public let count: String?

    public init(emoji: String?, count: String?) {
        self.emoji = emoji
        self.count = count
    }
}

public enum AdviceFormatter {
    public static func statusTitle(
        cpu: CPUSample,
        memory: MemorySample,
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier
    ) -> String {
        let cpuPercent = Int((cpu.totalUsage * 100).rounded())
        let memoryPercent = Int(memory.usedPercent.rounded())
        let text = AppStrings(languageIdentifier: languageIdentifier)
        return "🖥️ CPU \(cpuPercent)% · 🧠 \(text.memoryShortLabel) \(memoryPercent)%"
    }

    /// Split LLM-produced `statusBar.title` (e.g. `🚨 2`, `⚠️ 6`, `3`, `0`) into a
    /// leading emoji prefix and a trailing numeric count. The app uses this to
    /// render the menu-bar icon position (emoji) separately from the warning
    /// number (which gets the severity color), so it can hide whichever piece
    /// the new menu-bar policy says to hide.
    public static func parseStatusBarTitle(_ title: String) -> StatusBarTitleParts {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return StatusBarTitleParts(emoji: nil, count: nil) }

        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return StatusBarTitleParts(emoji: nil, count: nil) }

        // "0" means "nothing actionable" per response-guide; treat as no count.
        func normalizedCount(_ value: String) -> String? {
            value == "0" ? nil : value
        }

        if tokens.count == 1 {
            let single = tokens[0]
            if isNumericToken(single) {
                return StatusBarTitleParts(emoji: nil, count: normalizedCount(single))
            }
            return StatusBarTitleParts(emoji: single, count: nil)
        }

        let lastToken = tokens[tokens.count - 1]
        if isNumericToken(lastToken) {
            let emojiSegment = tokens.dropLast().joined(separator: " ")
            return StatusBarTitleParts(
                emoji: emojiSegment.isEmpty ? nil : emojiSegment,
                count: normalizedCount(lastToken)
            )
        }

        // Non-numeric tail: keep the whole tail as the "count" slot so we still
        // surface the text the LLM picked instead of silently dropping it.
        let emoji = tokens.first
        let tail = tokens.dropFirst().joined(separator: " ")
        return StatusBarTitleParts(emoji: emoji, count: tail.isEmpty ? nil : tail)
    }

    /// True when the menu-bar status color qualifies as "red or higher" — the
    /// only severity level allowed to surface the warning number per the
    /// current menu-bar policy. Named colors must be `red`/`systemred`; hex
    /// colors must be dominantly red (R high, G/B both low) to qualify.
    public static func isCriticalStatusBarColor(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "red", "systemred":
            return true
        default:
            break
        }

        let hex = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return false }
        let r = (rgb >> 16) & 0xff
        let g = (rgb >> 8) & 0xff
        let b = rgb & 0xff
        // Require red dominance with low green/blue so orange/yellow hexes
        // (e.g. #FF9933) do NOT qualify as critical.
        return r >= 0xC0 && g <= 0x80 && b <= 0x80
    }

    private static func isNumericToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return token.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public static func menuLines(for advice: Advice) -> [String] {
        advice.suggestions.map { suggestion in
            "\(suggestion.severity.icon) \(suggestion.title)"
        }
    }

    public static func statusBarTitle(
        title: String,
        generatedAt: Date,
        now: Date = Date(),
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Menu bar shows the last-check time RELATIVELY ("2분 전"); the exact clock time
        // lives in the dropdown menu (see lastCheckTimeString).
        let time = lastCheckRelativeString(
            generatedAt: generatedAt,
            now: now,
            languageIdentifier: languageIdentifier
        )
        if trimmedTitle.isEmpty {
            return time
        }
        return "\(trimmedTitle) · \(time)"
    }

    public static func lastCheckRelativeString(
        generatedAt: Date,
        now: Date = Date(),
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier
    ) -> String {
        let secondsAgo = Int(now.timeIntervalSince(generatedAt).rounded(.down))
        return AppStrings(languageIdentifier: languageIdentifier).relativeTimeAgo(secondsAgo: secondsAgo)
    }

    public static func lastCheckTimeString(
        generatedAt: Date,
        now: Date = Date(),
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageIdentifier)
        formatter.timeZone = timeZone
        if calendar.isDate(generatedAt, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d HH:mm"
        }
        return formatter.string(from: generatedAt)
    }

    public static func detailLines(
        for suggestion: Suggestion,
        languageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier
    ) -> [String] {
        let text = AppStrings(languageIdentifier: languageIdentifier)
        var lines = [
            suggestion.detail,
            "\(text.reasonLabel): \(suggestion.rationale)"
        ]

        if let command = suggestion.suggestedCommand, !command.isEmpty {
            lines.append("$ \(command)")
        }

        return lines
    }
}
