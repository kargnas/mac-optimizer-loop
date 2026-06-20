import XCTest
@testable import MacOptimizingLooperCore

final class AdviceFormatterTests: XCTestCase {
    func testStatusTitleFormatsRoundedCPUAndMemory() {
        let cpu = CPUSample(totalUsage: 0.42, perCore: [])
        let memory = MemorySample(
            total: 100,
            used: 71,
            free: 29,
            active: 0,
            inactive: 0,
            wired: 0,
            compressed: 0
        )

        XCTAssertEqual(
            AdviceFormatter.statusTitle(cpu: cpu, memory: memory, languageIdentifier: "en-US"),
            "🖥️ CPU 42% · 🧠 MEM 71%"
        )
        XCTAssertEqual(
            AdviceFormatter.statusTitle(cpu: cpu, memory: memory, languageIdentifier: "ko-KR"),
            "🖥️ CPU 42% · 🧠 메모리 71%"
        )
    }

    func testMenuLinesUseModelProvidedSeverityIcon() {
        let advice = Advice(
            generatedAt: Fixtures.snapshot.timestamp,
            summary: "summary",
            statusBar: StatusBarDisplay(title: "🚨 1", color: "red"),
            suggestions: [
                Fixtures.suggestion(severity: Severity(id: "critical", label: "Critical", icon: "🚨", color: "red", rank: 100))
            ]
        )

        XCTAssertEqual(AdviceFormatter.menuLines(for: advice), ["🚨 Close unused Chrome tabs"])
    }

    func testStatusBarTitleAppendsLastCheckTimeForSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let generatedAt = isoDate("2026-03-04T05:25:00Z")
        let now = isoDate("2026-03-04T15:26:40Z")

        XCTAssertEqual(
            AdviceFormatter.statusBarTitle(
                title: "🚨 2",
                generatedAt: generatedAt,
                now: now,
                languageIdentifier: "ko-KR",
                calendar: calendar,
                timeZone: calendar.timeZone
            ),
            "🚨 2 · 10시간 전"
        )
    }

    func testStatusBarTitleIncludesDateForOlderCheck() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let generatedAt = isoDate("2026-03-04T05:25:00Z")
        let now = isoDate("2026-03-05T05:20:00Z")

        XCTAssertEqual(
            AdviceFormatter.statusBarTitle(
                title: "",
                generatedAt: generatedAt,
                now: now,
                languageIdentifier: "en-US",
                calendar: calendar,
                timeZone: calendar.timeZone
            ),
            "23h ago"
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testDetailLinesIncludeCommandOnlyWhenPresent() {
        let withCommand = AdviceFormatter.detailLines(
            for: Fixtures.suggestion(command: "open -a 'Activity Monitor'"),
            languageIdentifier: "en-US"
        )
        let withoutCommand = AdviceFormatter.detailLines(
            for: Fixtures.suggestion(command: nil),
            languageIdentifier: "en-US"
        )

        XCTAssertTrue(withCommand.contains("Reason: Reducing active tabs can reduce renderer pressure."))
        XCTAssertTrue(withCommand.contains("$ open -a 'Activity Monitor'"))
        XCTAssertFalse(withoutCommand.contains { $0.hasPrefix("$ ") })
    }

    func testParseStatusBarTitleEmojiPlusCount() {
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle("🚨 2"),
            StatusBarTitleParts(emoji: "🚨", count: "2")
        )
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle("⚠️ 6"),
            StatusBarTitleParts(emoji: "⚠️", count: "6")
        )
    }

    func testParseStatusBarTitleCountOnly() {
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle("3"),
            StatusBarTitleParts(emoji: nil, count: "3")
        )
    }

    func testParseStatusBarTitleZeroBecomesNil() {
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle("0"),
            StatusBarTitleParts(emoji: nil, count: nil)
        )
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle("🚨 0"),
            StatusBarTitleParts(emoji: "🚨", count: nil)
        )
    }

    func testParseStatusBarTitleEmptyAndWhitespace() {
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle(""),
            StatusBarTitleParts(emoji: nil, count: nil)
        )
        XCTAssertEqual(
            AdviceFormatter.parseStatusBarTitle("   "),
            StatusBarTitleParts(emoji: nil, count: nil)
        )
    }

    func testIsCriticalStatusBarColorNamedRed() {
        XCTAssertTrue(AdviceFormatter.isCriticalStatusBarColor("red"))
        XCTAssertTrue(AdviceFormatter.isCriticalStatusBarColor("systemRed"))
        XCTAssertTrue(AdviceFormatter.isCriticalStatusBarColor(" RED "))
    }

    func testIsCriticalStatusBarColorRejectsNonRedNamed() {
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("orange"))
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("yellow"))
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("green"))
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("blue"))
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("gray"))
    }

    func testIsCriticalStatusBarColorHexRedDominant() {
        XCTAssertTrue(AdviceFormatter.isCriticalStatusBarColor("#FF0000"))
        XCTAssertTrue(AdviceFormatter.isCriticalStatusBarColor("#CC2222"))
        XCTAssertTrue(AdviceFormatter.isCriticalStatusBarColor("D00000"))
    }

    func testIsCriticalStatusBarColorHexRejectsOrange() {
        // #FF9933 is orange-ish (g=0x99 > 0x80), so MUST NOT qualify.
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("#FF9933"))
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("#FFA500"))
        XCTAssertFalse(AdviceFormatter.isCriticalStatusBarColor("#999999"))
    }
}
