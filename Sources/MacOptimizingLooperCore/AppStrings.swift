import Foundation

public struct AppStrings {
    public let languageIdentifier: String

    public init(languageIdentifier: String) {
        self.languageIdentifier = languageIdentifier
    }

    public var isKorean: Bool {
        languageIdentifier.lowercased().hasPrefix("ko")
    }

    public var appAccessibilityDescription: String { isKorean ? "부하 어드바이저" : "Load Advisor" }
    public var appTooltip: String { isKorean ? "Mac 부하 어드바이저" : "Mac Optimizing Looper" }
    public var analysisWaiting: String { isKorean ? "분석 대기 중" : "Waiting for analysis" }
    public var configurationWarningTitle: String { isKorean ? "⚠️ 설정 파일 오류 — 기본값으로 실행 중" : "⚠️ Config file error — running with defaults" }
    public var analyzing: String { isKorean ? "분석 중…" : "Analyzing..." }
    public var noSuggestions: String { isKorean ? "아직 제안이 없습니다" : "No suggestions yet" }
    public var analyzeNow: String { isKorean ? "지금 분석" : "Analyze Now" }
    public var settingsMenuItem: String { isKorean ? "설정…" : "Settings..." }
    public var quit: String { isKorean ? "종료" : "Quit" }
    public var openCommandInTerminal: String { isKorean ? "터미널에 명령어 띄우기" : "Show Command in Terminal" }
    public var reviewWithClaude: String { isKorean ? "Claude로 검토" : "Review with Claude" }
    public var copyCommand: String { isKorean ? "명령어 복사" : "Copy Command" }
    public var runCommandNow: String { isKorean ? "명령 바로 실행" : "Run Command Now" }
    public var runCommandDone: String { isKorean ? "실행 완료 · 다시 실행" : "Done · Run Again" }
    public var dangerousCommandTitle: String { isKorean ? "위험할 수 있는 명령" : "Potentially Dangerous Command" }
    public var runAnyway: String { isKorean ? "실행" : "Run" }
    public var checkingCommandSafety: String { isKorean ? "명령 위험 검사 중…" : "Checking command safety…" }
    public var runningCommand: String { isKorean ? "명령 실행 중…" : "Running command…" }
    public var resultWindowTitle: String { isKorean ? "실행 결과" : "Command Result" }
    public var clickToViewOutput: String { isKorean ? "클릭하여 출력 보기" : "Click to view output" }
    public var noOutput: String { isKorean ? "(출력 없음)" : "(no output)" }
    public var exitCodeLabel: String { isKorean ? "종료 코드" : "exit code" }
    public var ranWithAdministrator: String { isKorean ? "관리자 권한으로 실행됨" : "Ran with administrator privileges" }
    public var safetyCheckUnavailable: String {
        isKorean
            ? "위험 검사를 실행할 수 없어(claude CLI 확인) 안전을 위해 확인이 필요합니다."
            : "Couldn't run the safety check (verify the claude CLI), so confirmation is required."
    }

    public func dangerousCommandPrompt(reason: String, command: String) -> String {
        let reasonLine = reason.isEmpty ? "" : (isKorean ? "사유: \(reason)\n\n" : "Reason: \(reason)\n\n")
        let lead = isKorean ? "이 명령을 실행할까요?" : "Run this command?"
        return "\(lead)\n\n\(reasonLine)\(command)"
    }

    public func commandSucceededTitle(_ command: String) -> String { "✅ \(command)" }
    public func commandFailedTitle(_ command: String) -> String { "❌ \(command)" }

    public func commandResultBody(exitCode: Int32, durationSeconds: Double) -> String {
        let duration = String(format: "%.1fs", max(0, durationSeconds))
        return "\(exitCodeLabel) \(exitCode) · \(duration) · \(clickToViewOutput)"
    }
    public var terminalOpenFailed: String { isKorean ? "터미널 열기 실패" : "Failed to Open Terminal" }
    public func terminalAppNotFound(_ bundleIdentifier: String) -> String {
        let id = bundleIdentifier.isEmpty ? (isKorean ? "(미설정)" : "(none)") : bundleIdentifier
        return isKorean
            ? "설정한 터미널 앱을 찾을 수 없습니다: \(id). 설정에서 터미널을 다시 선택하세요."
            : "Configured terminal app not found: \(id). Re-select a terminal in Settings."
    }
    public var missingClaudeCLITitle: String { isKorean ? "Claude CLI 없음" : "Claude CLI Not Found" }
    public var missingClaudeCLIMessage: String { isKorean ? "claude 실행 파일을 찾지 못했습니다." : "Could not find the claude executable." }
    public var claudeReviewOpenFailed: String { isKorean ? "Claude 검토 열기 실패" : "Failed to Open Claude Review" }
    public var settingsSavedRefreshing: String { isKorean ? "설정 저장됨 · 분석 갱신 중" : "Settings saved · refreshing analysis" }
    public var settingsSaveFailed: String { isKorean ? "설정 저장 실패" : "Failed to Save Settings" }
    public var ok: String { isKorean ? "확인" : "OK" }
    public var memoryShortLabel: String { isKorean ? "메모리" : "MEM" }
    public var reasonLabel: String { isKorean ? "이유" : "Reason" }
    public var macOptimizerFailedPrefix: String { isKorean ? "mac-optimizer 실패" : "mac-optimizer failed" }
    public var settingsWindowTitle: String { isKorean ? "Mac Optimizing Looper 설정" : "Mac Optimizing Looper Settings" }
    public var claudeModelLabel: String { isKorean ? "Claude 모델" : "Claude Model" }
    public var thinkingLevelLabel: String { isKorean ? "추론 강도" : "Thinking Level" }
    public var analysisIntervalLabel: String { isKorean ? "분석 주기" : "Analysis Interval" }

    /// Short label for a discrete analysis-interval step (e.g. "60분"/"2시간"). Steps
    /// up to 60 minutes read as minutes; longer steps read as whole hours.
    public func intervalLabel(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes <= 60 {
            return isKorean ? "\(minutes)분" : "\(minutes)m"
        }
        let hours = minutes / 60
        return isKorean ? "\(hours)시간" : "\(hours)h"
    }
    public var analysisLanguageLabel: String { isKorean ? "분석 결과 언어" : "Analysis Language" }
    public var monitorDurationLabel: String { isKorean ? "모니터 수집 시간" : "Monitor Duration" }

    /// Value label for the monitor-duration slider; 0 reads as "off".
    public func monitorDurationValue(seconds: Int) -> String {
        if seconds <= 0 {
            return isKorean ? "끄기" : "off"
        }
        return isKorean ? "\(seconds)초" : "\(seconds)s"
    }
    public var terminalAppLabel: String { isKorean ? "터미널 앱" : "Terminal App" }
    public var noTerminalAppsDetected: String { isKorean ? "감지된 터미널 없음" : "No terminal apps detected" }
    public var languagePlaceholder: String { isKorean ? "비우면 macOS 기본" : "Blank = macOS default" }
    public var languageHelp: String {
        isKorean
            ? "비워두거나 system 입력 시 macOS 첫 번째 언어를 따릅니다. 한국어 고정은 ko-KR."
            : "Leave blank or type system to follow the first macOS language. Use ko-KR to force Korean."
    }
    public var save: String { isKorean ? "저장" : "Save" }
    public var cancel: String { isKorean ? "취소" : "Cancel" }
    public var terminalCommandHeader: String { isKorean ? "Mac Optimizing Looper 제안 명령어(실행 안 함):" : "Mac Optimizing Looper suggested command (not executed):" }
    public var terminalCommandFooter: String { isKorean ? "검토 후 필요할 때만 직접 붙여넣어 실행하세요." : "Review it before running. Paste/run manually only if you choose." }
    public var claudeReviewStarting: String { isKorean ? "Claude가 Mac Optimizing Looper 제안을 검토하는 중입니다..." : "Claude is reviewing this Mac Optimizing Looper suggestion..." }
    public var claudeNotExecutable: String { isKorean ? "설정된 경로에서 Claude CLI를 실행할 수 없습니다." : "Claude CLI is not executable at the configured path." }
    public var reviewPromptMissing: String { isKorean ? "검토 프롬프트 파일을 찾을 수 없습니다." : "Review prompt file is missing." }

    public func detectedMacOSLanguages(_ summary: String) -> String {
        isKorean ? "감지된 macOS 언어: \(summary)" : "Detected macOS languages: \(summary)"
    }

    public func currentAnalysisLanguage(_ language: String) -> String {
        isKorean ? "현재 적용 분석 언어: \(language)" : "Current analysis language: \(language)"
    }

    public func analysisFailed(_ message: String) -> String {
        isKorean ? "분석 실패: \(message)" : "Analysis failed: \(message)"
    }

    public func analyzingElapsed(seconds: Int) -> String {
        isKorean ? "분석 중… \(formatElapsed(seconds: seconds))" : "Analyzing... \(formatElapsed(seconds: seconds))"
    }

    public var lastCheckedLabel: String { isKorean ? "마지막 확인" : "Last checked" }

    /// Coarse "X ago" phrase for the menu-bar last-check time. The exact clock time
    /// is shown separately inside the dropdown (see `AdviceFormatter.lastCheckTimeString`).
    public func relativeTimeAgo(secondsAgo: Int) -> String {
        let s = max(0, secondsAgo)
        if s < 10 { return isKorean ? "방금" : "just now" }
        if s < 60 { return isKorean ? "\(s)초 전" : "\(s)s ago" }
        let minutes = s / 60
        if minutes < 60 { return isKorean ? "\(minutes)분 전" : "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return isKorean ? "\(hours)시간 전" : "\(hours)h ago" }
        let days = hours / 24
        return isKorean ? "\(days)일 전" : "\(days)d ago"
    }

    private func formatElapsed(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        if safeSeconds < 60 {
            return isKorean ? "\(safeSeconds)초" : "\(safeSeconds)s"
        }

        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        if minutes < 60 {
            return isKorean ? "\(minutes)분 \(remainingSeconds)초" : "\(minutes)m \(remainingSeconds)s"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return isKorean ? "\(hours)시간 \(remainingMinutes)분" : "\(hours)h \(remainingMinutes)m"
    }

    public func processFailed(status: Int32, message: String) -> String {
        let suffix = message.isEmpty ? "" : ": \(message)"
        return isKorean ? "프로세스 실패 \(status)\(suffix)" : "Process failed \(status)\(suffix)"
    }
}
