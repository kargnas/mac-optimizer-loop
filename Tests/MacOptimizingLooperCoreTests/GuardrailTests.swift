import XCTest
@testable import MacOptimizingLooperCore

final class GuardrailTests: XCTestCase {
    func testActionPolicyIsUserInitiatedWithSafeguards() {
        // Advice is still inert data; the only execution path is the explicit,
        // user-initiated, risk-checked "Run command now" action.
        XCTAssertEqual(ActionPolicy.current, .userInitiatedWithSafeguards)
    }

    func testSuggestionAndAdviceConformToAdvisoryOnly() {
        let suggestion = Fixtures.suggestion(command: "killall Example")
        let advice = Advice(
            generatedAt: Fixtures.snapshot.timestamp,
            summary: "summary",
            statusBar: StatusBarDisplay(title: "1", color: "red"),
            suggestions: [suggestion]
        )

        assertAdvisoryOnly(suggestion)
        assertAdvisoryOnly(advice)
    }

    func testSuggestedCommandIsOnlyAnOptionalStringDataField() {
        let suggestion = Fixtures.suggestion(command: "killall Example")

        XCTAssertEqual(suggestion.suggestedCommand, "killall Example")
        XCTAssertFalse(Mirror(reflecting: suggestion).children.contains { child in
            String(describing: type(of: child.value)).contains("->")
        }, "Suggestion must not carry executable closures; suggestedCommand is display/copy-only data.")
    }

    func testTerminalDisplayScriptPrintsSuggestedCommandWithoutExecutingIt() {
        let command = "touch /tmp/mac-optimizing-looper-test; echo 'ran'"

        let script = TerminalScriptBuilder.suggestedCommandDisplayScript(command: command, languageIdentifier: "en-US")

        XCTAssertTrue(script.contains("not executed"))
        XCTAssertTrue(script.contains("printf '%s\\n\\n' \(TerminalScriptBuilder.shellQuoted(command))"))
        XCTAssertFalse(script.contains("\ntouch /tmp/mac-optimizing-looper-test"))
    }

    func testClaudeReviewScriptOpensInteractiveSessionFromPromptFile() {
        let script = TerminalScriptBuilder.claudeReviewScript(
            promptFilePath: "/tmp/review prompt.txt",
            claudeExecutablePath: "/opt/homebrew/bin/claude",
            model: "sonnet"
        )

        XCTAssertTrue(script.contains("/opt/homebrew/bin/claude"))
        XCTAssertTrue(script.contains("--model 'sonnet'"))
        XCTAssertTrue(script.contains("_mac_load_advisor_prompt='/tmp/review prompt.txt'"))
        // Prompt read from the file (not embedded inline) and passed as an argument.
        XCTAssertTrue(script.contains("cat \"$_mac_load_advisor_prompt\""))
        // Interactive session — must NOT be headless print mode.
        XCTAssertFalse(script.contains(" -p "))
        XCTAssertFalse(script.contains("--print"))
        XCTAssertFalse(script.contains("--output-format"))
    }

    private func assertAdvisoryOnly<T: AdvisoryOnly>(_ value: T) {
        XCTAssertNotNil(value)
    }
}
