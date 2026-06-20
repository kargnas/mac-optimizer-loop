import XCTest
@testable import MacOptimizingLooperCore

final class MacOptimizerScriptTests: XCTestCase {
    func testFindScriptUsesConfiguredPathFirst() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-test-\(UUID().uuidString).sh")
        try "#!/bin/bash\necho ok\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let report = MacOptimizerScript.findScript(environment: [
            "MAC_OPTIMIZER_SCRIPT": scriptURL.path
        ])

        XCTAssertEqual(report?.path, scriptURL.path)
    }
}
