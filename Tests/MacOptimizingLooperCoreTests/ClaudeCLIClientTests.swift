import XCTest
@testable import MacOptimizingLooperCore

final class ClaudeCLIClientTests: XCTestCase {
    private func makeFakeCLI(script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-fake-claude-\(UUID().uuidString).sh")
        try "#!/bin/bash\n\(script)".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func request() -> ChatRequest {
        ChatRequest(model: "fable", system: "sys", user: "user", maxTokens: 100, temperature: 0, effort: "low")
    }

    /// claude prints API failures (e.g. "API Error: 429 …") to STDOUT and exits 1 with an
    /// empty stderr. The error surfaced to the UI must carry that stdout text, otherwise
    /// the menu shows a bare "process failed 1" with no cause.
    func testFailureWithEmptyStderrFallsBackToStdout() async throws {
        let cli = try makeFakeCLI(script: "cat >/dev/null\necho 'API Error: 429 usage limit reached'\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(executableURL: cli, environment: [:])
        do {
            _ = try await client.complete(request())
            XCTFail("expected processFailed")
        } catch let LLMError.processFailed(status, message) {
            XCTAssertEqual(status, 1)
            XCTAssertEqual(message, "API Error: 429 usage limit reached")
        }
    }

    /// When stderr does have content it stays the primary error source (existing behavior).
    func testFailureWithStderrKeepsStderrMessage() async throws {
        let cli = try makeFakeCLI(script: "cat >/dev/null\necho 'partial stdout'\necho 'real error' >&2\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(executableURL: cli, environment: [:])
        do {
            _ = try await client.complete(request())
            XCTFail("expected processFailed")
        } catch let LLMError.processFailed(status, message) {
            XCTAssertEqual(status, 1)
            XCTAssertEqual(message, "real error")
        }
    }

    /// Successful runs must be unaffected by the stdout-fallback change.
    func testSuccessReturnsStdout() async throws {
        let cli = try makeFakeCLI(script: "cat >/dev/null\necho 'analysis notes'\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(executableURL: cli, environment: [:])
        let response = try await client.complete(request())
        XCTAssertEqual(response.choices.first?.message.content, "analysis notes")
    }
}
