import Foundation

/// Drives `codex exec` as an alternative to `claude -p`. codex has no `--system` flag,
/// so the system and user prompts are concatenated into the single prompt argument.
/// When the request carries an `outputSchema`, codex's native `--output-schema` returns
/// the final JSON directly (no second formatting pass).
public struct CodexCLIClient: LLMClient {
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
            throw LLMError.missingProviderCLI(LLMProviderKind.codex.displayName)
        }

        let output = try runCodex(request, executableURL: executableURL)
        return ChatResponse(choices: [
            ChatResponseChoice(message: ChatMessage(role: "assistant", content: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        ])
    }

    private func runCodex(_ request: ChatRequest, executableURL: URL) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        // `-o` writes ONLY the final assistant message, so we read clean output instead
        // of scraping it from codex's event-laden stdout.
        let lastMessageURL = tmp.appendingPathComponent("mac-optimizing-looper-codex-\(token).out")
        let schemaURL = tmp.appendingPathComponent("mac-optimizing-looper-codex-\(token).schema.json")
        let errorURL = tmp.appendingPathComponent("mac-optimizing-looper-codex-\(token).err")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: lastMessageURL)
            try? FileManager.default.removeItem(at: schemaURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        if let schema = request.outputSchema {
            try schema.data(using: .utf8)?.write(to: schemaURL, options: .atomic)
        }

        // codex blocks waiting on stdin unless it is closed; route it from /dev/null.
        let nullHandle = FileHandle(forReadingAtPath: "/dev/null")
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? nullHandle?.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments(for: request, lastMessageURL: lastMessageURL, schemaURL: schemaURL)
        process.environment = Self.processEnvironment(from: environment)
        process.standardInput = nullHandle
        process.standardOutput = errorHandle   // discard codex's event stream; final answer is in -o
        process.standardError = errorHandle

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        try process.run()
        // No timeout: a full analysis can take minutes; we wait rather than kill it.
        group.wait()

        let errorOutput = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw LLMError.processFailed(process.terminationStatus, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = String(data: (try? Data(contentsOf: lastMessageURL)) ?? Data(), encoding: .utf8) ?? ""
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.processFailed(0, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    func arguments(for request: ChatRequest, lastMessageURL: URL, schemaURL: URL) -> [String] {
        var arguments = ["exec", "--skip-git-repo-check", "--sandbox", "read-only"]

        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments.append(contentsOf: ["-m", model])
        }

        let effort = request.effort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effort.isEmpty {
            arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(effort)\""])
        }

        if request.fastMode {
            // Request codex's priority ("Fast") service tier. `service_tier` is the
            // codex config key (verified via `--strict-config`); only set when the
            // caller already confirmed the model supports it (see config validation).
            arguments.append(contentsOf: ["-c", "service_tier=\"priority\""])
        }

        if request.outputSchema != nil {
            arguments.append(contentsOf: ["--output-schema", schemaURL.path])
        }
        arguments.append(contentsOf: ["-o", lastMessageURL.path])

        // codex has no system-prompt flag; fold system into the single prompt argument.
        arguments.append(Self.combinedPrompt(system: request.system, user: request.user))
        return arguments
    }

    static func combinedPrompt(system: String, user: String) -> String {
        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSystem.isEmpty else { return user }
        return "\(trimmedSystem)\n\n\(user)"
    }

    public static func defaultExecutableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        return executableCandidates(environment: environment).first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func executableCandidates(environment: [String: String]) -> [URL] {
        var paths: [String] = []
        if let configured = environment["CODEX_CLI_PATH"], !configured.isEmpty {
            paths.append(configured)
        }
        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(contentsOf: [
            "\(home)/.bun/bin/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
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
        let fallbackPath = "\(home)/.bun/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = result["PATH"], !currentPath.isEmpty {
            result["PATH"] = "\(currentPath):\(fallbackPath)"
        } else {
            result["PATH"] = fallbackPath
        }
        return result
    }
}
