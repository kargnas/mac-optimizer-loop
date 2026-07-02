import Foundation

public struct ClaudeCLIClient: LLMClient {
    private let executableURL: URL?
    private let environment: [String: String]

    public init(
        executableURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.environment = environment
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        guard let executableURL = executableURL ?? Self.defaultExecutableURL(environment: environment) else {
            throw LLMError.missingClaudeCLI
        }

        let output = try runClaude(request, executableURL: executableURL)
        return ChatResponse(choices: [
            ChatResponseChoice(message: ChatMessage(role: "assistant", content: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        ])
    }

    private func runClaude(_ request: ChatRequest, executableURL: URL) throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-claude-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-claude-\(UUID().uuidString).err")
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-claude-\(UUID().uuidString).in")
        try request.user.data(using: .utf8)?.write(to: inputURL, options: .atomic)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
            try? FileManager.default.removeItem(at: inputURL)
        }

        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? inputHandle.close()
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments(for: request)
        process.environment = Self.processEnvironment(from: environment)
        process.standardInput = inputHandle
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in
            group.leave()
        }

        try process.run()
        // No timeout: a full analysis can take several minutes and its duration is
        // highly variable, so we wait for claude to finish instead of killing a run
        // that is still working. (Previously a 120s cap aborted long inspections.)
        group.wait()

        let output = String(data: (try? Data(contentsOf: outputURL)) ?? Data(), encoding: .utf8) ?? ""
        let errorOutput = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            // claude prints API failures ("API Error: 429 …", usage-limit notices) to
            // STDOUT and exits nonzero with an EMPTY stderr, so stderr alone loses the
            // actual cause and the UI shows a bare "process failed 1". Fall back to
            // stdout (capped: it is unbounded and lands in a one-line menu title).
            let stderrText = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderrText.isEmpty ? String(stdoutText.prefix(300)) : stderrText
            throw LLMError.processFailed(process.terminationStatus, message)
        }

        return output
    }

    private func arguments(for request: ChatRequest) -> [String] {
        let effort = request.effort.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = [
            "-p",
            "--no-session-persistence",
            // We run claude headless from a background app, so there is no TTY to answer
            // an interactive permission prompt. `plan` is read-only: claude may run
            // read-only inspections (verified: `ps`; likewise df/du/vm_stat for capacity)
            // to investigate, but writes/edits are categorically blocked by the mode —
            // independent of how any individual command would be classified. This still
            // lets claude RECOMMEND a fix command as inert text; the app (not claude) runs
            // it later on the user's click. For a kernel-enforced guarantee an OS sandbox
            // could wrap this process; codex already runs under `--sandbox read-only`.
            "--permission-mode", "plan",
            "--output-format", "text",
            "--effort", effort.isEmpty ? "low" : effort,
            "--system-prompt", request.system
        ]
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        return arguments
    }

    public static func defaultExecutableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        let candidates = executableCandidates(environment: environment)
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func executableCandidates(environment: [String: String]) -> [URL] {
        var paths: [String] = []
        if let configured = environment["CLAUDE_CLI_PATH"], !configured.isEmpty {
            paths.append(configured)
        }
        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/claude" })
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(contentsOf: [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ])

        var seen = Set<String>()
        return paths.compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            guard seen.insert(expanded).inserted else { return nil }
            return URL(fileURLWithPath: expanded)
        }
    }

    private static func processEnvironment(from environment: [String: String]) -> [String: String] {
        var result = environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbackPath = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = result["PATH"], !currentPath.isEmpty {
            result["PATH"] = "\(currentPath):\(fallbackPath)"
        } else {
            result["PATH"] = fallbackPath
        }
        return result
    }
}
