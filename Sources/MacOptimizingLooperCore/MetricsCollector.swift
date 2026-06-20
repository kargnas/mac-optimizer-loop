import Darwin
import Foundation

public protocol MetricsCollecting {
    func collect() throws -> SystemSnapshot
}

public enum MetricsError: Error {
    case mach(String)
    case sysctl(String)
    case process(String)
    case decoding(String)
}

public final class SystemMetricsCollector: MetricsCollecting {
    private var previousCPUInfo: host_cpu_load_info_data_t?

    public init() {}

    public func collect() throws -> SystemSnapshot {
        let cpu = try collectCPU()
        let memory = try collectMemory()
        let processes = try collectProcesses()
        let ranked = LoadAnalyzer.rank(processes: processes, top: 6)

        return SystemSnapshot(
            timestamp: Date(),
            cpu: cpu,
            memory: memory,
            topByCPU: ranked.byCPU,
            topByMemory: ranked.byMemory
        )
    }

    private func collectMemory() throws -> MemorySample {
        var totalMemory: UInt64 = 0
        var totalMemorySize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &totalMemory, &totalMemorySize, nil, 0) == 0 else {
            throw MetricsError.sysctl("hw.memsize")
        }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricsError.mach("host_statistics64(HOST_VM_INFO64)")
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        // Match Activity Monitor's "Memory Used" = App + Wired + Compressed, which
        // EXCLUDES reclaimable file cache (inactive + purgeable external pages).
        //   App Memory = anonymous pages that are NOT purgeable
        //              = internal_page_count - purgeable_count
        // The original `active + inactive + wired + compressed` folded ~55GB of
        // reclaimable cache into "used" and pinned a healthy 128GB Mac at ~96-98%.
        // Using internal-purgeable (rather than `active`) also captures inactive
        // *anonymous* app pages that `active` alone misses, so it both stops the
        // over-report AND avoids under-reporting — landing on Activity Monitor's number.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appMemory = (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize
        let used = appMemory + wired + compressed

        return MemorySample(
            total: totalMemory,
            used: used,
            free: free,
            active: active,
            inactive: inactive,
            wired: wired,
            compressed: compressed
        )
    }

    private func collectCPU() throws -> CPUSample {
        // A fresh collector is created per analysis (see AppDelegate), so previousCPUInfo
        // is normally nil and this is the only sampling window. host_statistics(HOST_CPU_
        // LOAD_INFO) tick counters advance coarsely, so ANY fixed short window can capture
        // ZERO elapsed ticks and report 0% — the "측정 실패 (measurement failure)" the user
        // saw. Instead of trusting a single fixed sleep, sample until the ticks actually
        // advance, capped at ~1s so we never block the analysis for long.
        let first = try previousCPUInfo ?? readCPUInfo()
        var second = try readCPUInfo()
        var deltas = tickDeltas(from: first, to: second)
        var waited = 0.0
        let step = 0.1
        let maxWait = 1.0
        while deltas.reduce(0, +) == 0 && waited < maxWait {
            Thread.sleep(forTimeInterval: step)
            waited += step
            second = try readCPUInfo()
            deltas = tickDeltas(from: first, to: second)
        }
        previousCPUInfo = second

        let total = deltas.reduce(0, +)
        guard total > 0 else {
            return CPUSample(totalUsage: 0, perCore: [])
        }
        // cpu_ticks order: 0=USER 1=SYSTEM 2=IDLE 3=NICE — busy is everything but idle.
        let busy = deltas[0] + deltas[1] + deltas[3]
        return CPUSample(totalUsage: Double(busy) / Double(total), perCore: [])
    }

    private func tickDeltas(from first: host_cpu_load_info_data_t, to second: host_cpu_load_info_data_t) -> [UInt64] {
        zip(cpuTicks(first), cpuTicks(second)).map { before, after in
            after >= before ? after - before : 0
        }
    }

    private func readCPUInfo() throws -> host_cpu_load_info_data_t {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricsError.mach("host_statistics(HOST_CPU_LOAD_INFO)")
        }
        return info
    }

    private func cpuTicks(_ info: host_cpu_load_info_data_t) -> [UInt64] {
        [
            UInt64(info.cpu_ticks.0),
            UInt64(info.cpu_ticks.1),
            UInt64(info.cpu_ticks.2),
            UInt64(info.cpu_ticks.3)
        ]
    }

    private func collectProcesses() throws -> [ProcessSample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // READ-ONLY: samples process table; never sends signals / never modifies the system.
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm=", "-r"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw MetricsError.process("ps exited with status \(process.terminationStatus): \(errorOutput)")
        }

        guard let output = String(data: data, encoding: .utf8) else {
            throw MetricsError.decoding("ps output was not UTF-8")
        }

        return output.split(separator: "\n").compactMap(Self.parseProcessLine)
    }

    private static func parseProcessLine(_ line: Substring) -> ProcessSample? {
        let parts = line.split(maxSplits: 3, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
        guard parts.count == 4,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[1]),
              let rssKB = UInt64(parts[2]) else {
            return nil
        }

        return ProcessSample(
            pid: pid,
            name: String(parts[3]),
            cpuPercent: cpu,
            memoryBytes: rssKB * 1_024
        )
    }
}
