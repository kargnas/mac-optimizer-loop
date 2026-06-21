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

    /// With no override and no app bundle (the `swift test` case, CWD == package root),
    /// resolution MUST land on the tracked in-repo skill copy — never on a $HOME path.
    /// This is the regression guard for "the scan is bundled, not borrowed from ~/".
    func testFindScriptResolvesTrackedRepoCopyWithoutHomeLookup() throws {
        let repoCopy = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".agents/skills/mac-optimizer/mac-optimize.sh")
        try XCTSkipUnless(
            FileManager.default.isReadableFile(atPath: repoCopy.path),
            "tracked skill copy not at CWD — skip when tests run outside the repo root"
        )

        let report = MacOptimizerScript.findScript(environment: [:])

        XCTAssertEqual(report?.path, repoCopy.path)
        XCTAssertFalse(report?.path.contains("/.claude/") ?? false, "must not resolve from $HOME")
    }
}
