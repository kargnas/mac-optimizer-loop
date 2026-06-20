import Foundation

/// Result of an explicit, user-initiated command run. Pure value type so it can
/// cross from the background execution task back to the main actor (`Sendable`).
public struct CommandExecutionResult: Sendable, Equatable {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let durationSeconds: Double
    public let usedAdministrator: Bool

    public init(
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int32,
        durationSeconds: Double,
        usedAdministrator: Bool
    ) {
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.usedAdministrator = usedAdministrator
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// Runs a single user-approved command off the main thread and captures its full
/// console output. This is the ONLY execution path in the app — advice generation
/// never reaches here (see `ActionPolicy.userInitiatedWithSafeguards`).
public enum CommandExecutor {
    /// Runs `command` in the background and returns its captured result. Commands
    /// that need root are routed through a GUI administrator-password prompt
    /// (`osascript ... with administrator privileges`) because a background process
    /// has no TTY and plain `sudo` would just hang/fail.
    public static func run(command: String) async -> CommandExecutionResult {
        let needsAdmin = requiresAdministrator(command)
        return await Task.detached(priority: .userInitiated) {
            needsAdmin ? runWithAdministrator(command) : runPlain(command)
        }.value
    }

    /// True when the command invokes `sudo` as a command token (not as a substring
    /// of an unrelated word like `sudoku`). Used to decide whether the GUI password
    /// prompt is needed. Exposed for testing.
    public static func requiresAdministrator(_ command: String) -> Bool {
        // `sudo` must sit on a command boundary: start of string or after any
        // non-identifier byte (space, ;, |, &, (, etc.), and be followed by a
        // non-identifier byte or end of string. Case-sensitive because the real
        // binary is lowercase `sudo`.
        let pattern = "(^|[^A-Za-z0-9_])sudo([^A-Za-z0-9_]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }

    // MARK: - Plain (non-privileged) execution

    private static func runPlain(_ command: String) -> CommandExecutionResult {
        let start = Date()
        let process = Process()
        // -l so the command sees the user's normal login environment (PATH, etc.),
        // matching what they'd get typing it in a terminal themselves.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandExecutionResult(
                command: command,
                stdout: "",
                stderr: String(describing: error),
                exitCode: -1,
                durationSeconds: Date().timeIntervalSince(start),
                usedAdministrator: false
            )
        }

        // Drain stderr on a separate queue so a process that fills the stderr pipe
        // buffer can still make progress while we block draining stdout — reading
        // both serially could otherwise deadlock on large output.
        let errQueue = DispatchQueue(label: "as.kargn.MacOptimizingLooper.stderr")
        var errData = Data()
        errQueue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errQueue.sync {}

        return CommandExecutionResult(
            command: command,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus,
            durationSeconds: Date().timeIntervalSince(start),
            usedAdministrator: false
        )
    }

    // MARK: - Privileged execution (GUI password prompt)

    private static func runWithAdministrator(_ command: String) -> CommandExecutionResult {
        let start = Date()
        let tmp = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        let outURL = tmp.appendingPathComponent("mac-optimizing-looper-run-\(token).out")
        let errURL = tmp.appendingPathComponent("mac-optimizing-looper-run-\(token).err")
        let codeURL = tmp.appendingPathComponent("mac-optimizing-looper-run-\(token).code")
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
            try? FileManager.default.removeItem(at: codeURL)
        }

        // The whole command runs inside one privileged shell. `do shell script`
        // already elevates to root, so any embedded `sudo` succeeds without a second
        // password. Redirect stdout/stderr and the real exit code to files so we
        // recover them all even when the command exits non-zero (the wrapper itself
        // still exits 0, so `do shell script` won't swallow the output as an error).
        let snippet = "{ \(command) ; } > \(TerminalScriptBuilder.shellQuoted(outURL.path))"
            + " 2> \(TerminalScriptBuilder.shellQuoted(errURL.path));"
            + " printf '%s' \"$?\" > \(TerminalScriptBuilder.shellQuoted(codeURL.path))"
        let appleScript = "do shell script \(TerminalScriptBuilder.appleScriptStringLiteral(snippet)) with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let osErrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = osErrPipe

        do {
            try process.run()
        } catch {
            return CommandExecutionResult(
                command: command,
                stdout: "",
                stderr: String(describing: error),
                exitCode: -1,
                durationSeconds: Date().timeIntervalSince(start),
                usedAdministrator: true
            )
        }

        let osErrData = osErrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let duration = Date().timeIntervalSince(start)

        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let fileStderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        let codeString = ((try? String(contentsOf: codeURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let exitCode = Int32(codeString) {
            // Command actually ran; report its own exit code and stderr.
            return CommandExecutionResult(
                command: command,
                stdout: stdout,
                stderr: fileStderr,
                exitCode: exitCode,
                durationSeconds: duration,
                usedAdministrator: true
            )
        }

        // No exit code captured → the command never ran. Most common cause is the
        // user cancelling the password prompt (osascript exits non-zero with a
        // "User canceled." style message on stderr). Surface that honestly.
        let osStderr = String(data: osErrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CommandExecutionResult(
            command: command,
            stdout: stdout,
            stderr: osStderr.isEmpty ? fileStderr : osStderr,
            exitCode: process.terminationStatus == 0 ? -1 : process.terminationStatus,
            durationSeconds: duration,
            usedAdministrator: true
        )
    }
}
