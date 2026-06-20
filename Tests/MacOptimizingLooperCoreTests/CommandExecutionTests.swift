import XCTest
@testable import MacOptimizingLooperCore

final class CommandExecutionTests: XCTestCase {
    // MARK: - sudo detection (decides whether the GUI password prompt is used)

    func testRequiresAdministratorDetectsSudoToken() {
        XCTAssertTrue(CommandExecutor.requiresAdministrator("sudo killall Dock"))
        XCTAssertTrue(CommandExecutor.requiresAdministrator("echo hi && sudo rm -rf /tmp/x"))
        XCTAssertTrue(CommandExecutor.requiresAdministrator(" pkill x | sudo tee /etc/y"))
    }

    func testRequiresAdministratorIgnoresSudoSubstrings() {
        XCTAssertFalse(CommandExecutor.requiresAdministrator("killall Dock"))
        XCTAssertFalse(CommandExecutor.requiresAdministrator("echo sudoku"))
        XCTAssertFalse(CommandExecutor.requiresAdministrator("pseudonym=1"))
    }

    // MARK: - actual background run captures output and exit code

    func testRunCapturesStdoutAndExitCode() async {
        let result = await CommandExecutor.run(command: "printf 'hello'")
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(result.usedAdministrator)
    }

    func testRunCapturesNonZeroExit() async {
        let result = await CommandExecutor.run(command: "exit 7")
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
    }

    // MARK: - risk verdict parsing

    func testParseDangerousVerdict() {
        let verdict = CommandRiskAssessor.parse("RISK: DANGEROUS\nREASON: deletes files irreversibly")
        XCTAssertEqual(verdict.level, .dangerous)
        XCTAssertEqual(verdict.reason, "deletes files irreversibly")
        XCTAssertTrue(verdict.requiresConfirmation)
    }

    func testParseSafeVerdict() {
        let verdict = CommandRiskAssessor.parse("RISK: SAFE\nREASON: only reads process list")
        XCTAssertEqual(verdict.level, .safe)
        XCTAssertFalse(verdict.requiresConfirmation)
    }

    func testParseUnsafeIsNotMistakenForSafe() {
        let verdict = CommandRiskAssessor.parse("This looks UNSAFE to me")
        XCTAssertNotEqual(verdict.level, .safe)
        XCTAssertTrue(verdict.requiresConfirmation)
    }

    func testParseAmbiguousIsUnknownAndStillConfirms() {
        let verdict = CommandRiskAssessor.parse("I'm not sure about this command")
        XCTAssertEqual(verdict.level, .unknown)
        XCTAssertTrue(verdict.requiresConfirmation)
    }
}
