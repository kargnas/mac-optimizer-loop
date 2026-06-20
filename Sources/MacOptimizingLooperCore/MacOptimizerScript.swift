import Foundation

public struct MacOptimizerReport: Equatable {
    public let scriptPath: String
    public let output: String

    public init(scriptPath: String, output: String) {
        self.scriptPath = scriptPath
        self.output = output
    }
}

public enum MacOptimizerScript {
    public static func runIfAvailable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        monitorSeconds: Int = 30,
        snapshotTimeoutSeconds: TimeInterval = 20,
        maxCharacters: Int = 80_000
    ) throws -> MacOptimizerReport? {
        guard let scriptURL = findScript(environment: environment) else {
            return nil
        }

        // Snapshot pass (fast, one-shot): rich derived metrics + process tables.
        let snapshot = try runScript(
            scriptURL: scriptURL,
            arguments: [scriptURL.path],
            environment: environment,
            timeoutSeconds: snapshotTimeoutSeconds
        )
        var combined = compacted(snapshot)

        // Sustained monitor pass: samples a real window for N seconds to separate a
        // genuine culprit from a one-off spike. User-configurable; 0 disables it.
        // `--monitor` is a distinct script mode that prints only the monitor report,
        // so it runs as a second invocation appended after the snapshot.
        if monitorSeconds > 0 {
            let monitor = try runScript(
                scriptURL: scriptURL,
                arguments: [scriptURL.path, "--monitor", "\(monitorSeconds)"],
                environment: environment,
                // Bounded by N; add buffer so the sampling window isn't cut short.
                timeoutSeconds: TimeInterval(monitorSeconds) + 15
            )
            combined += "\n\n" + monitor
        }

        return MacOptimizerReport(scriptPath: scriptURL.path, output: truncated(combined, maxCharacters: maxCharacters))
    }

    private static func runScript(
        scriptURL: URL,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-mac-optimizer-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-mac-optimizer-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in
            group.leave()
        }

        try process.run()
        if group.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            throw LLMError.processFailed(-1, "mac-optimizer timed out")
        }

        let output = String(data: (try? Data(contentsOf: outputURL)) ?? Data(), encoding: .utf8) ?? ""
        let errorOutput = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw LLMError.processFailed(process.terminationStatus, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    public static func findScript(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        return scriptCandidates(environment: environment).first { fileManager.isReadableFile(atPath: $0.path) }
    }

    private static func scriptCandidates(environment: [String: String]) -> [URL] {
        var paths: [String] = []
        if let configured = environment["MAC_OPTIMIZER_SCRIPT"], !configured.isEmpty {
            paths.append(configured)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(contentsOf: [
            "\(home)/.claude/skills/mac-optimizer/mac-optimize.sh",
            "\(home)/.agents/skills/mac-optimizer/mac-optimize.sh",
            "\(home)/.codex/skills/mac-optimizer/mac-optimize.sh"
        ])

        var seen = Set<String>()
        return paths.compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            guard seen.insert(expanded).inserted else { return nil }
            return URL(fileURLWithPath: expanded)
        }
    }

    private static func truncated(_ output: String, maxCharacters: Int) -> String {
        guard output.count > maxCharacters else {
            return output
        }
        let prefix = output.prefix(maxCharacters)
        return "\(prefix)\n\n[mac-optimizer output truncated to \(maxCharacters) characters]"
    }

    private static func compacted(_ output: String) -> String {
        let limits = [
            "=== SYSTEM INFO ===": 10,
            "=== MEMORY ===": 26,
            "=== TOP PROCESSES BY CPU ===": 11,
            "=== TOP PROCESSES BY MEMORY ===": 11,
            "=== PROCESS SUMMARY ===": 4,
            "=== BROWSER PROCESSES ===": 6,
            "=== CLAUDE CODE SESSIONS ===": 8,
            "=== DISK USAGE ===": 5,
            "=== POWER & THERMAL ===": 8,
            "=== DOCKER / VM ===": 5
        ]
        var selected: [String] = []
        var remaining = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let limit = limits[line] {
                if !selected.isEmpty, selected.last != "" {
                    selected.append("")
                }
                selected.append(line)
                remaining = limit
                continue
            }

            guard remaining > 0 else { continue }
            selected.append(line)
            remaining -= 1
        }

        return selected.isEmpty ? output : selected.joined(separator: "\n")
    }
}
