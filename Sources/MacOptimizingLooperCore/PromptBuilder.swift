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

    /// Formatting rules for a provider that emits the final JSON itself (structured
    /// output). Mirrors `script/mac-optimizing-looper-response-guide.sh`, which plays the
    /// same role for the claude two-pass path — keep the two in sync. The JSON SHAPE is
    /// enforced separately by `adviceJSONSchema`; this conveys the SEMANTICS the schema
    /// cannot (exact menu-bar text, severity icons/colors, least-destructive commands).
    public static func responseFormatGuide(outputLanguageIdentifier: String) -> String {
        """
        Return the analysis as the structured object required by the schema.
        Language for user-facing string values: \(outputLanguageIdentifier). If it starts with ko, write Korean.
        Keep process names and shell commands unchanged.

        statusBar.title is the EXACT menu-bar text the app shows (the app does not compute it):
        - mac-optimizer SYSTEM STATE = CRITICAL or MUST-RUN NOW -> urgent emoji + issue count, e.g. "🚨 2".
        - non-critical findings -> usually just the issue count, e.g. "3".
        - nothing actionable -> "0" and suggestions = [].
        statusBar.color is the exact menu-bar text color: red|orange|yellow|green|blue|gray or #RRGGBB.

        Each severity is an object: non-empty id (e.g. critical/high/medium/low/info or MUST-RUN-NOW),
        a short user-facing label, one emoji icon (🚨/🔴/🟡/🟢/ℹ️), a color (red|orange|yellow|green|blue|gray or #RRGGBB),
        and a numeric rank (higher = more severe). A CRITICAL/MUST-RUN-NOW item -> id critical, icon 🚨, color red, rank 100.

        suggestedCommand MUST be the actual least-destructive fix command when one exists
        (graceful "kill <pid>" of the specific runaway process over "kill -9"/broad "killall";
        use the pid from the analysis). Never use inspection-only commands (pgrep/ps/top/lsof)
        as suggestedCommand when a real fix exists. Use null only when there is genuinely no
        command-line action. NEVER imply the app already executed anything.
        """
    }

    /// JSON Schema (strict) for `LLMAdviceResponse`, fed to codex `--output-schema`.
    /// Optional fields are expressed as nullable so the model can omit them while every
    /// property stays `required` (strict structured-output rule).
    public static let adviceJSONSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["summary", "statusBar", "suggestions"],
      "properties": {
        "summary": { "type": "string" },
        "statusBar": {
          "type": "object",
          "additionalProperties": false,
          "required": ["title", "color"],
          "properties": {
            "title": { "type": "string" },
            "color": { "type": "string" }
          }
        },
        "suggestions": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "detail", "rationale", "severity", "suggestedCommand", "targetProcessName"],
            "properties": {
              "title": { "type": "string" },
              "detail": { "type": "string" },
              "rationale": { "type": "string" },
              "severity": {
                "type": "object",
                "additionalProperties": false,
                "required": ["id", "label", "icon", "color", "rank"],
                "properties": {
                  "id": { "type": "string" },
                  "label": { "type": "string" },
                  "icon": { "type": "string" },
                  "color": { "type": "string" },
                  "rank": { "type": ["number", "null"] }
                }
              },
              "suggestedCommand": { "type": ["string", "null"] },
              "targetProcessName": { "type": ["string", "null"] }
            }
          }
        }
      }
    }
    """

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
