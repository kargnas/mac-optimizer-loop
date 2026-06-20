import AppKit

struct TerminalApplication: Equatable {
    enum LaunchMode {
        case appleTerminal
        case iTerm
        case openWithArguments
        case openCommandFile
    }

    let displayName: String
    let bundleIdentifier: String
    let url: URL
    let launchMode: LaunchMode
}

enum TerminalAppCatalog {
    private struct Candidate {
        let displayName: String
        let bundleIdentifiers: [String]
        let launchMode: TerminalApplication.LaunchMode
        let appNames: [String]
    }

    static let defaultBundleIdentifier = "com.apple.Terminal"

    private static let candidates: [Candidate] = [
        Candidate(
            displayName: "Terminal",
            bundleIdentifiers: ["com.apple.Terminal"],
            launchMode: .appleTerminal,
            appNames: ["Terminal"]
        ),
        Candidate(
            displayName: "iTerm2",
            bundleIdentifiers: ["com.googlecode.iterm2"],
            launchMode: .iTerm,
            appNames: ["iTerm", "iTerm2"]
        ),
        Candidate(
            displayName: "Warp",
            bundleIdentifiers: ["dev.warp.Warp-Stable", "dev.warp.Warp"],
            launchMode: .openCommandFile,
            appNames: ["Warp"]
        ),
        Candidate(
            displayName: "Ghostty",
            bundleIdentifiers: ["com.mitchellh.ghostty"],
            launchMode: .openWithArguments,
            appNames: ["Ghostty"]
        ),
        Candidate(
            displayName: "WezTerm",
            bundleIdentifiers: ["com.github.wez.wezterm"],
            launchMode: .openCommandFile,
            appNames: ["WezTerm"]
        ),
        Candidate(
            displayName: "Alacritty",
            bundleIdentifiers: ["org.alacritty"],
            launchMode: .openCommandFile,
            appNames: ["Alacritty"]
        ),
        Candidate(
            displayName: "kitty",
            bundleIdentifiers: ["net.kovidgoyal.kitty"],
            launchMode: .openCommandFile,
            appNames: ["kitty", "Kitty"]
        ),
        Candidate(
            displayName: "Hyper",
            bundleIdentifiers: ["co.zeit.hyper", "io.hyper"],
            launchMode: .openCommandFile,
            appNames: ["Hyper"]
        ),
        Candidate(
            displayName: "Tabby",
            bundleIdentifiers: ["org.tabby"],
            launchMode: .openCommandFile,
            appNames: ["Tabby"]
        )
    ]

    static func installedApplications() -> [TerminalApplication] {
        var apps: [TerminalApplication] = []
        var seen = Set<String>()

        for candidate in candidates {
            if let app = installedApplication(for: candidate), seen.insert(app.bundleIdentifier).inserted {
                apps.append(app)
            }
        }

        return apps
    }

    static func application(bundleIdentifier: String?) -> TerminalApplication? {
        // A configured terminal is honored EXACTLY. We never silently substitute a
        // different app (e.g. Apple Terminal) when the chosen one can't be matched —
        // that hid real misconfiguration and opened "the wrong terminal". Resolve the
        // chosen id directly so a terminal that installedApplications() happened to
        // miss still opens, and return nil (→ caller surfaces an error) only when it
        // is genuinely not installed.
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            if let known = candidates.first(where: { $0.bundleIdentifiers.contains(bundleIdentifier) }),
               let app = installedApplication(for: known) {
                return app
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                // Installed but not in the known list → generic .command-file launch,
                // which virtually every terminal supports.
                return TerminalApplication(
                    displayName: displayName(for: url) ?? bundleIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    url: url,
                    launchMode: .openCommandFile
                )
            }
            return nil
        }

        // No terminal configured at all → default to Apple Terminal, else first found.
        let apps = installedApplications()
        return apps.first(where: { $0.bundleIdentifier == defaultBundleIdentifier }) ?? apps.first
    }

    private static func installedApplication(for candidate: Candidate) -> TerminalApplication? {
        for bundleIdentifier in candidate.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return TerminalApplication(
                    displayName: displayName(for: url) ?? candidate.displayName,
                    bundleIdentifier: bundleIdentifier,
                    url: url,
                    launchMode: candidate.launchMode
                )
            }
        }

        for appName in candidate.appNames {
            if let url = findApplication(named: appName),
               let bundleIdentifier = Bundle(url: url)?.bundleIdentifier {
                return TerminalApplication(
                    displayName: displayName(for: url) ?? candidate.displayName,
                    bundleIdentifier: bundleIdentifier,
                    url: url,
                    launchMode: candidate.launchMode
                )
            }
        }

        return nil
    }

    private static func findApplication(named appName: String) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/Applications/\(appName).app",
            "/Applications/Utilities/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func displayName(for url: URL) -> String? {
        Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
}
