import Foundation

public enum PromptBuilder {
    public static func analysisSystemPrompt(outputLanguageIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier) -> String {
        """
        macOS load advisor using /mac-optimizer methodology.
        Analyze in language/locale: \(outputLanguageIdentifier).
        For each fixable issue, identify the ACTUAL remediation command (e.g. kill/
        killall the runaway process, unload a launch job) so the user can run it from
        the app. The app NEVER auto-runs anything and you MUST NOT claim or imply a fix
        was already executed — you only analyze and recommend.
        """
    }

    public static func userPrompt(for snapshot: SystemSnapshot, optimizerReport: MacOptimizerReport? = nil) -> String {
        let cpuPercent = Int((snapshot.cpu.totalUsage * 100).rounded())
        let memoryPercent = Int(snapshot.memory.usedPercent.rounded())
        let totalRAMGB = String(format: "%.1f", Double(snapshot.memory.total) / 1_073_741_824)
        let cpuProcesses = processList(snapshot.topByCPU)
        let memoryProcesses = processList(snapshot.topByMemory)
        let flags = LoadAnalyzer.pressureFlags(cpu: snapshot.cpu, memory: snapshot.memory)
        let optimizerSection: String
        if let optimizerReport {
            optimizerSection = """

            mac-optimizer output from \(optimizerReport.scriptPath):
            \(optimizerReport.output)
            """
        } else {
            optimizerSection = "\n\nmac-optimizer output: unavailable; use the Swift snapshot above."
        }

        return """
        Use /mac-optimizer. If the slash command is unavailable, use the attached mac-optimizer output.
        Produce analysis notes only; final JSON formatting happens in a separate CLI formatter pass.

        Current macOS load snapshot:
        CPU: \(cpuPercent)%
        Memory used: \(memoryPercent)%
        Total RAM: \(totalRAMGB) GB
        Pressure flags: \(flags.isEmpty ? "none" : flags.joined(separator: ", "))

        Top processes by CPU:
        \(cpuProcesses)

        Top processes by memory:
        \(memoryProcesses)
        \(optimizerSection)
        """
    }

    private static func processList(_ processes: [ProcessSample]) -> String {
        if processes.isEmpty {
            return "- none"
        }

        return processes.map { process in
            let cpu = Int(process.cpuPercent.rounded())
            let memoryMB = Int((Double(process.memoryBytes) / 1_048_576).rounded())
            // Include the pid so a remediation command can target the exact process
            // (e.g. `kill <pid>`) instead of a broad name-based action.
            return "- \(process.name) (pid \(process.pid)): CPU \(cpu)%, MEM \(memoryMB) MB"
        }.joined(separator: "\n")
    }
}
