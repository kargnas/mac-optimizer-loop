import XCTest
@testable import MacOptimizingLooperCore

final class AppStringsTests: XCTestCase {
    func testAnalyzingElapsedFormatsKoreanDurations() {
        let strings = AppStrings(languageIdentifier: "ko-KR")

        XCTAssertEqual(strings.analyzingElapsed(seconds: 0), "분석 중… 0초")
        XCTAssertEqual(strings.analyzingElapsed(seconds: 75), "분석 중… 1분 15초")
        XCTAssertEqual(strings.analyzingElapsed(seconds: 3_900), "분석 중… 1시간 5분")
    }

    func testAnalyzingElapsedFormatsEnglishDurations() {
        let strings = AppStrings(languageIdentifier: "en-US")

        XCTAssertEqual(strings.analyzingElapsed(seconds: 7), "Analyzing... 7s")
        XCTAssertEqual(strings.analyzingElapsed(seconds: 125), "Analyzing... 2m 5s")
        XCTAssertEqual(strings.analyzingElapsed(seconds: 7_260), "Analyzing... 2h 1m")
    }
}
