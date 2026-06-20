import XCTest
@testable import MacOptimizingLooperCore

final class LoadAnalyzerTests: XCTestCase {
    func testRankReturnsStableTopProcessesByCPUAndMemory() {
        let processes = [
            ProcessSample(pid: 1, name: "Finder", cpuPercent: 4, memoryBytes: 200),
            ProcessSample(pid: 2, name: "Chrome", cpuPercent: 80, memoryBytes: 900),
            ProcessSample(pid: 3, name: "Xcode", cpuPercent: 35, memoryBytes: 1_400),
            ProcessSample(pid: 4, name: "Slack", cpuPercent: 35, memoryBytes: 800)
        ]

        let ranked = LoadAnalyzer.rank(processes: processes, top: 3)

        XCTAssertEqual(ranked.byCPU.map(\.name), ["Chrome", "Xcode", "Slack"])
        XCTAssertEqual(ranked.byMemory.map(\.name), ["Xcode", "Chrome", "Slack"])
    }

    func testPressureFlagsReportsHighCPUHighMemoryAndCompression() {
        let cpu = CPUSample(totalUsage: 0.91, perCore: [])
        let memory = MemorySample(
            total: 100,
            used: 90,
            free: 10,
            active: 30,
            inactive: 20,
            wired: 10,
            compressed: 20
        )

        XCTAssertEqual(
            LoadAnalyzer.pressureFlags(cpu: cpu, memory: memory),
            ["high-cpu", "high-memory", "memory-compression"]
        )
    }

    func testPressureFlagsReturnsEmptyForLowPressure() {
        let cpu = CPUSample(totalUsage: 0.2, perCore: [])
        let memory = MemorySample(
            total: 100,
            used: 40,
            free: 60,
            active: 20,
            inactive: 10,
            wired: 20,
            compressed: 1
        )

        XCTAssertEqual(LoadAnalyzer.pressureFlags(cpu: cpu, memory: memory), [])
    }
}
