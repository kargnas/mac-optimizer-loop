import AppKit
import MacOptimizingLooperCore

enum TerminalLaunchError: Error {
    /// The configured terminal could not be resolved. We surface this instead of
    /// silently opening a different terminal than the user chose.
    case applicationNotFound(bundleIdentifier: String?)
    case launchFailed(status: Int32)
}

/// Single place that turns a shell script into an opened terminal window using the
/// user's configured terminal app. Every terminal-opening feature (show command,
/// Claude review) goes through here, so the app-resolution and per-terminal launch
/// quirks live in exactly one tested unit instead of being duplicated per call site.
struct TerminalLauncher {
    let terminalBundleIdentifier: String?

    init(terminalBundleIdentifier: String?) {
        self.terminalBundleIdentifier = terminalBundleIdentifier
    }

    func open(script: String) throws {
        guard let terminalApp = TerminalAppCatalog.application(bundleIdentifier: terminalBundleIdentifier) else {
            throw TerminalLaunchError.applicationNotFound(bundleIdentifier: terminalBundleIdentifier)
        }

        switch terminalApp.launchMode {
        case .appleTerminal:
            // Run via a command file (path-only injection). Embedding the multi-line
            // UTF-8 script directly in `do script` strands `if/elif/else/fi` at shell
            // continuation prompts and corrupts CJK text; the file avoids both.
            let scriptURL = try writeCommandFile(script: script)
            try openWithAppleScript(appleScript: appleTerminalScript(scriptPath: scriptURL.path), cleanupURL: scriptURL)
        case .iTerm:
            let scriptURL = try writeCommandFile(script: script)
            try openWithAppleScript(appleScript: iTermScript(scriptPath: scriptURL.path), cleanupURL: scriptURL)
        case .openWithArguments:
            try openWithArguments(script: script, terminalApp: terminalApp)
        case .openCommandFile:
            let scriptURL = try writeCommandFile(script: script)
            try openCommandFile(scriptURL, with: terminalApp)
        }
    }

    private func writeCommandFile(script: String) throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-terminal-\(UUID().uuidString).command")
        let wrappedScript = """
        #!/bin/zsh
        _mac_load_advisor_script="$0"
        rm -f "$_mac_load_advisor_script" >/dev/null 2>&1 || true
        \(script)
        """
        try wrappedScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func openWithAppleScript(appleScript: String, cleanupURL: URL?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
            throw TerminalLaunchError.launchFailed(status: process.terminationStatus)
        }
    }

    private func openWithArguments(script: String, terminalApp: TerminalApplication) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-na", terminalApp.url.path,
            "--args",
            "-e", "/bin/zsh", "-lc", script
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TerminalLaunchError.launchFailed(status: process.terminationStatus)
        }
    }

    private func openCommandFile(_ scriptURL: URL, with terminalApp: TerminalApplication) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", terminalApp.bundleIdentifier, scriptURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: scriptURL)
            throw TerminalLaunchError.launchFailed(status: process.terminationStatus)
        }
    }

    // Inject only the (ASCII) command-file path, never the multi-line/UTF-8 script
    // body. Terminal's `do script` turns embedded newlines into Return presses,
    // which strands a multi-line `if/elif/else/fi` at continuation prompts and can
    // corrupt multibyte (CJK) text. The script body lives in the executable file,
    // read directly by zsh as UTF-8.
    private func appleTerminalScript(scriptPath: String) -> String {
        let runCommand = TerminalScriptBuilder.shellQuoted(scriptPath)
        return """
        tell application id "com.apple.Terminal"
            activate
            do script \(TerminalScriptBuilder.appleScriptStringLiteral(runCommand))
        end tell
        """
    }

    private func iTermScript(scriptPath: String) -> String {
        let runCommand = TerminalScriptBuilder.shellQuoted(scriptPath)
        return """
        tell application id "com.googlecode.iterm2"
            activate
            if (count of windows) = 0 then
                create window with default profile command \(TerminalScriptBuilder.appleScriptStringLiteral(runCommand))
            else
                tell current window
                    create tab with default profile command \(TerminalScriptBuilder.appleScriptStringLiteral(runCommand))
                end tell
            end if
        end tell
        """
    }
}
