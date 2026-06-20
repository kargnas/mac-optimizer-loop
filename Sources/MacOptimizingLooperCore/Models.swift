import Foundation

public struct CPUSample {
    public let totalUsage: Double
    public let perCore: [Double]

    public init(totalUsage: Double, perCore: [Double]) {
        self.totalUsage = totalUsage
        self.perCore = perCore
    }
}

public struct MemorySample {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let wired: UInt64
    public let compressed: UInt64

    public var usedPercent: Double {
        total == 0 ? 0 : Double(used) / Double(total) * 100
    }

    public init(
        total: UInt64,
        used: UInt64,
        free: UInt64,
        active: UInt64,
        inactive: UInt64,
        wired: UInt64,
        compressed: UInt64
    ) {
        self.total = total
        self.used = used
        self.free = free
        self.active = active
        self.inactive = inactive
        self.wired = wired
        self.compressed = compressed
    }
}

public struct ProcessSample: Equatable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct SystemSnapshot {
    public let timestamp: Date
    public let cpu: CPUSample
    public let memory: MemorySample
    public let topByCPU: [ProcessSample]
    public let topByMemory: [ProcessSample]

    public init(
        timestamp: Date,
        cpu: CPUSample,
        memory: MemorySample,
        topByCPU: [ProcessSample],
        topByMemory: [ProcessSample]
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.topByCPU = topByCPU
        self.topByMemory = topByMemory
    }
}

public struct Severity: Codable, Equatable {
    public let id: String
    public let label: String
    public let icon: String
    public let color: String
    public let rank: Int?

    public init(
        id: String,
        label: String,
        icon: String,
        color: String,
        rank: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.color = color
        self.rank = rank
    }

    public var displayText: String {
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedIcon.isEmpty {
            return trimmedLabel
        }
        if trimmedLabel.isEmpty {
            return trimmedIcon
        }
        return "\(trimmedIcon) \(trimmedLabel)"
    }
}

public struct StatusBarDisplay: Codable, Equatable {
    public let title: String
    public let color: String

    public init(title: String, color: String) {
        self.title = title
        self.color = color
    }
}

public protocol AdvisoryOnly {}

public enum ActionPolicy: Equatable {
    /// Advice is generated as inert data and is NEVER auto-run. The single execution
    /// path is an explicit, user-initiated "Run command now" action, gated by an LLM
    /// risk check, a confirmation prompt for risky commands, and a GUI administrator
    /// prompt for sudo. The model can never make the app run anything on its own.
    case userInitiatedWithSafeguards

    public static let current: ActionPolicy = .userInitiatedWithSafeguards
}

/// Advisory remediation data. `suggestedCommand` is an optional string the app
/// surfaces for the user to copy, review, or explicitly run via the gated
/// "Run command now" action — generating advice never executes anything by itself.
public struct Suggestion: Identifiable, Equatable, AdvisoryOnly {
    public let id: UUID
    public let title: String
    public let detail: String
    public let rationale: String
    public let severity: Severity
    public let suggestedCommand: String?
    public let targetProcessName: String?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        rationale: String,
        severity: Severity,
        suggestedCommand: String?,
        targetProcessName: String?
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.rationale = rationale
        self.severity = severity
        self.suggestedCommand = suggestedCommand
        self.targetProcessName = targetProcessName
    }
}

public struct Advice: AdvisoryOnly {
    public let generatedAt: Date
    public let summary: String
    public let statusBar: StatusBarDisplay
    public let suggestions: [Suggestion]

    public init(generatedAt: Date, summary: String, statusBar: StatusBarDisplay, suggestions: [Suggestion]) {
        self.generatedAt = generatedAt
        self.summary = summary
        self.statusBar = statusBar
        self.suggestions = suggestions
    }
}
