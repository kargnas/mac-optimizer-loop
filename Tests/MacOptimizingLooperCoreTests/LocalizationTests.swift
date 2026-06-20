import XCTest
@testable import MacOptimizingLooperCore

/// Covers the forced-locale `.lproj` resolution in `AppStrings` / `LocalizationBundle`:
/// exact-locale loads, region/script collapse, Chinese & Portuguese variant mapping,
/// English fallback for unshipped locales, and placeholder formatting integrity.
final class LocalizationTests: XCTestCase {

    // MARK: Exact-locale loads

    func testEnglishLoadsSourceStrings() {
        XCTAssertEqual(AppStrings(languageIdentifier: "en").analyzeNow, "Analyze Now")
        XCTAssertEqual(AppStrings(languageIdentifier: "en").quit, "Quit")
    }

    func testKoreanLoadsTranslatedStrings() {
        XCTAssertEqual(AppStrings(languageIdentifier: "ko").analyzeNow, "지금 분석")
        XCTAssertEqual(AppStrings(languageIdentifier: "ko").quit, "종료")
    }

    /// Every shipped non-English locale must resolve to its OWN bundle, not silently
    /// fall back to English (which would defeat the whole feature).
    func testEachShippedLocaleResolvesToItsOwnTranslation() {
        let english = AppStrings(languageIdentifier: "en").quit
        for language in AppConfig.supportedUILanguages where language.identifier != "en" {
            let translated = AppStrings(languageIdentifier: language.identifier).quit
            XCTAssertFalse(translated.isEmpty, "\(language.identifier) quit is empty")
            XCTAssertNotEqual(
                translated, english,
                "\(language.identifier) fell back to English instead of loading its own .lproj"
            )
        }
    }

    func testSimplifiedAndTraditionalAreDistinct() {
        let hans = AppStrings(languageIdentifier: "zh-Hans").quit
        let hant = AppStrings(languageIdentifier: "zh-Hant").quit
        XCTAssertNotEqual(hans, hant, "zh-Hans and zh-Hant resolved to the same file")
    }

    // MARK: Region / script collapse

    func testRegionCollapsesToLanguage() {
        // ko-KR has no dedicated .lproj; it must collapse to ko.
        XCTAssertEqual(
            AppStrings(languageIdentifier: "ko-KR").analyzeNow,
            AppStrings(languageIdentifier: "ko").analyzeNow
        )
    }

    func testChineseRegionMapsToScript() {
        // zh-TW/HK → Traditional, zh-CN/SG → Simplified.
        XCTAssertEqual(
            AppStrings(languageIdentifier: "zh-TW").quit,
            AppStrings(languageIdentifier: "zh-Hant").quit
        )
        XCTAssertEqual(
            AppStrings(languageIdentifier: "zh-CN").quit,
            AppStrings(languageIdentifier: "zh-Hans").quit
        )
        // Bare "zh" defaults to Simplified.
        XCTAssertEqual(
            AppStrings(languageIdentifier: "zh").quit,
            AppStrings(languageIdentifier: "zh-Hans").quit
        )
    }

    func testPortugueseCollapsesToBrazilian() {
        // Only pt-BR is shipped; bare "pt" and "pt-PT" must reach it, not English.
        let brazilian = AppStrings(languageIdentifier: "pt-BR").analyzeNow
        XCTAssertEqual(AppStrings(languageIdentifier: "pt").analyzeNow, brazilian)
    }

    // MARK: Fallback

    func testUnshippedLocaleFallsBackToEnglish() {
        // Icelandic is not shipped → English source strings.
        XCTAssertEqual(AppStrings(languageIdentifier: "is").analyzeNow, "Analyze Now")
        XCTAssertEqual(AppStrings(languageIdentifier: "").analyzeNow, "Analyze Now")
    }

    // MARK: Placeholder integrity

    func testFormattedStringsInterpolateArgument() {
        XCTAssertTrue(AppStrings(languageIdentifier: "ko").analysisFailed("boom").contains("boom"))
        XCTAssertTrue(AppStrings(languageIdentifier: "ja").analysisFailed("boom").contains("boom"))
        XCTAssertTrue(AppStrings(languageIdentifier: "en").providerCLINotFound(provider: "Codex").contains("Codex"))
    }

    func testProcessFailedKeepsBothPlaceholders() {
        let text = AppStrings(languageIdentifier: "de").processFailed(status: 7, message: "nope")
        XCTAssertTrue(text.contains("7"))
        XCTAssertTrue(text.contains("nope"))
    }

    // MARK: Catalog

    func testSupportedLanguagesAreTenAndUnique() {
        XCTAssertEqual(AppConfig.supportedUILanguages.count, 10)
        let identifiers = AppConfig.supportedUILanguages.map(\.identifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "duplicate identifier in supportedUILanguages")
        for language in AppConfig.supportedUILanguages {
            XCTAssertFalse(language.autonym.isEmpty, "\(language.identifier) has empty autonym")
        }
    }
}
