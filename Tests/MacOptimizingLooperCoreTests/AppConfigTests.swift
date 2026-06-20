import XCTest
@testable import MacOptimizingLooperCore

final class AppConfigTests: XCTestCase {
    func testLoadWithEmptyEnvironmentAndNoFileReturnsDefaults() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)

        XCTAssertEqual(config.model, "sonnet")
        XCTAssertEqual(config.thinkingLevel, "max")
        XCTAssertEqual(config.monitorSeconds, 30)
        XCTAssertEqual(config.intervalSeconds, 3_600)
        XCTAssertNil(config.outputLanguageIdentifier)
        XCTAssertEqual(config.terminalAppBundleIdentifier, "com.apple.Terminal")
        XCTAssertFalse(config.resolvedOutputLanguageIdentifier().isEmpty)
        XCTAssertEqual(config.maxTokens, 8192)
        XCTAssertEqual(config.temperature, 0.2)
    }

    func testThinkingLevelLoadsAndClampsInvalidToMax() throws {
        let valid = try AppConfig.load(environment: [:], fileContents: Data(#"{ "thinkingLevel": "high" }"#.utf8))
        XCTAssertEqual(valid.thinkingLevel, "high")

        let invalid = try AppConfig.load(environment: [:], fileContents: Data(#"{ "thinkingLevel": "ultra" }"#.utf8))
        XCTAssertEqual(invalid.thinkingLevel, "max")
    }

    func testMonitorSecondsLoadsAndClampsToRange() throws {
        let valid = try AppConfig.load(environment: [:], fileContents: Data(#"{ "monitorSeconds": 45 }"#.utf8))
        XCTAssertEqual(valid.monitorSeconds, 45)

        let zero = try AppConfig.load(environment: [:], fileContents: Data(#"{ "monitorSeconds": 0 }"#.utf8))
        XCTAssertEqual(zero.monitorSeconds, 0)

        let tooBig = try AppConfig.load(environment: [:], fileContents: Data(#"{ "monitorSeconds": 9999 }"#.utf8))
        XCTAssertEqual(tooBig.monitorSeconds, 600)
    }

    func testMalformedConfigThrows() {
        XCTAssertThrowsError(try AppConfig.load(environment: [:], fileContents: Data("{ not json".utf8))) { error in
            XCTAssertEqual(error as? ConfigError, .malformedFile)
        }
    }

    func testNilFileContentsReturnsDefaults() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)

        XCTAssertEqual(config.model, "sonnet")
        XCTAssertEqual(config.intervalSeconds, 3_600)
    }

    func testFileOverridesModelAndClampsInterval() throws {
        let data = try XCTUnwrap("""
        { "model": "custom-model", "intervalSeconds": 10, "outputLanguageIdentifier": "ko-KR" }
        """.data(using: .utf8))

        let config = try AppConfig.load(environment: [:], fileContents: data)

        XCTAssertEqual(config.model, "custom-model")
        XCTAssertEqual(config.intervalSeconds, 60)
        XCTAssertEqual(config.outputLanguageIdentifier, "ko-KR")
    }

    func testFileCanPersistSettingsShape() throws {
        let data = try XCTUnwrap("""
        { "model": "opus", "intervalSeconds": 120, "terminalAppBundleIdentifier": "com.googlecode.iterm2" }
        """.data(using: .utf8))

        let config = try AppConfig.load(environment: [:], fileContents: data)

        XCTAssertEqual(config.model, "opus")
        XCTAssertEqual(config.intervalSeconds, 120)
        XCTAssertEqual(config.terminalAppBundleIdentifier, "com.googlecode.iterm2")
    }

    func testMissingFileUsesMacOSLanguageAsResolvedDefault() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)

        XCTAssertNil(config.outputLanguageIdentifier)
        XCTAssertEqual(config.resolvedOutputLanguageIdentifier(), AppConfig.defaultOutputLanguageIdentifier())
    }

    func testSystemOutputLanguageClearsUserOverride() {
        let language = AppConfig.normalizedLanguageIdentifier(
            "system"
        )

        XCTAssertNil(language)
    }
}
