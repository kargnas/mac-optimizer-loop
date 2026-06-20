import Foundation

public struct ClaudeCLIClient: LLMClient {
    private let executableURL: URL?
    private let environment: [String: String]
    private let effort: String

    public init(
        executableURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        effort: String = "low"
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.effort = effort
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
            throw LLMError.processFailed(process.terminationStatus, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func arguments(for request: ChatRequest) -> [String] {
        var arguments = [
            "-p",
            "--no-session-persistence",
            "--output-format", "text",
            "--effort", effort,
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
