import Foundation
import XCTest
@testable import MacOptimizingLooperCore

enum Fixtures {
    static let snapshot = SystemSnapshot(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        cpu: CPUSample(totalUsage: 0.42, perCore: [0.4, 0.44]),
        memory: MemorySample(
            total: 16 * 1_024 * 1_024 * 1_024,
            used: UInt64(Double(16 * 1_024 * 1_024 * 1_024) * 0.71),
            free: UInt64(Double(16 * 1_024 * 1_024 * 1_024) * 0.29),
            active: 4_000,
            inactive: 3_000,
            wired: 2_000,
            compressed: 1_000
        ),
        topByCPU: [
            ProcessSample(pid: 100, name: "Chrome", cpuPercent: 42.2, memoryBytes: 800 * 1_024 * 1_024),
            ProcessSample(pid: 200, name: "Xcode", cpuPercent: 20.0, memoryBytes: 1_500 * 1_024 * 1_024)
        ],
        topByMemory: [
            ProcessSample(pid: 200, name: "Xcode", cpuPercent: 20.0, memoryBytes: 1_500 * 1_024 * 1_024),
            ProcessSample(pid: 100, name: "Chrome", cpuPercent: 42.2, memoryBytes: 800 * 1_024 * 1_024)
        ]
    )

    static func suggestion(
        severity: Severity = Severity(id: "high", label: "High", icon: "🔴", color: "red", rank: 80),
        command: String? = nil
    ) -> Suggestion {
        Suggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Close unused Chrome tabs",
            detail: "Chrome is using significant CPU.",
            rationale: "Reducing active tabs can reduce renderer pressure.",
            severity: severity,
            suggestedCommand: command,
            targetProcessName: "Chrome"
        )
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
