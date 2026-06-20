import Foundation

public enum LoadAnalyzer {
    public static func rank(processes: [ProcessSample], top n: Int = 6) -> (byCPU: [ProcessSample], byMemory: [ProcessSample]) {
        let limit = max(0, n)

        let byCPU = processes.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.cpuPercent == rhs.element.cpuPercent {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.cpuPercent > rhs.element.cpuPercent
            }
            .prefix(limit)
            .map(\.element)

        let byMemory = processes.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.memoryBytes == rhs.element.memoryBytes {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.memoryBytes > rhs.element.memoryBytes
            }
            .prefix(limit)
            .map(\.element)

        return (byCPU, byMemory)
    }

    public static func pressureFlags(cpu: CPUSample, memory: MemorySample) -> [String] {
        var flags: [String] = []
        if cpu.totalUsage > 0.85 {
            flags.append("high-cpu")
        }
        if memory.usedPercent > 85 {
            flags.append("high-memory")
        }
        if memory.compressed > memory.wired {
            flags.append("memory-compression")
        }
        return flags
    }
}
