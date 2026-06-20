import AppKit
import MacOptimizingLooperCore
import Sparkle
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    // Strong ref kept for the whole app lifetime; releasing it stops update checks.
    // nil when running the bare SwiftPM binary (no .app bundle) — see startUpdaterIfBundled().
    private var updaterController: SPUStandardUpdaterController?
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var config: AppConfig
    private let configurationWarningTitle: String?
    private var advisorLoop: AdvisorLoop?
    private var settingsWindowController: SettingsWindowController?
    private var latestAdvice: Advice?
    private var latestSnapshot: SystemSnapshot?
    private var isAnalyzing = false
    private var analysisStartedAt: Date?
    private var analysisElapsedTimer: Timer?
    // Refreshes the menu-bar relative last-check time ("2분 전") between analyses,
    // which otherwise only updates when a new analysis lands.
    private var clockTimer: Timer?
    private var analysisSpinnerIndex = 0
    private var lastRenderedElapsedSeconds: Int?
    private let analysisSpinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    // Drives the menu-bar "⚠️" failure indicator (config invalid or last
    // analysis failed). updateStatusBarButton checks this BEFORE rendering
    // advice so a stale `latestAdvice` does not mask the current failure.
    private var failureActive = false

    // Direct-run feature: results indexed by notification id so a tapped notification
    // can reopen the matching output. One reusable result window.
    private var commandResults: [String: CommandExecutionResult] = [:]
    // suggestedCommands that ran successfully this analysis cycle → shown checked in
    // the menu. Cleared when a new analysis lands (pids/commands change anyway).
    private var completedCommandSignatures: Set<String> = []
    private var resultWindowController: CommandResultWindowController?
    private let riskAssessor = CommandRiskAssessor()
    // Commands currently mid-flight (check → confirm → run). Feedback only lands at
    // completion, so this stops a second click from running the same command twice.
    private var runningCommands: Set<String> = []
    private var notificationsAuthorized = false
    // UNUserNotificationCenter needs a real bundle proxy. The packaged .app has one;
    // a bare SwiftPM binary does not, so there we open the result window directly.
    private let notificationsSupported = Bundle.main.bundleIdentifier != nil

    override convenience init() {
        do {
            let config = try AppConfig.loadDefault()
            self.init(config: config)
        } catch {
            let config = AppConfig.defaults(environment: ProcessInfo.processInfo.environment)
            let text = AppStrings(languageIdentifier: config.resolvedOutputLanguageIdentifier())
            self.init(
                config: config,
                configurationWarningTitle: text.configurationWarningTitle
            )
        }
    }

    init(config: AppConfig, configurationWarningTitle: String? = nil) {
        self.config = config
        self.configurationWarningTitle = configurationWarningTitle
        super.init()
        headerItem.isEnabled = false
        headerItem.title = configurationWarningTitle ?? strings.analysisWaiting
        failureActive = (configurationWarningTitle != nil)
    }

    private var strings: AppStrings {
        AppStrings(languageIdentifier: config.resolvedOutputLanguageIdentifier())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = ""
            button.imagePosition = .imageLeading
            button.toolTip = strings.appTooltip
        }
        statusItem?.menu = menu
        if let configurationWarningTitle {
            headerItem.title = configurationWarningTitle
        }
        startUpdaterIfBundled()
        updateStatusBarButton()
        rebuildMenu()
        startClockTimer()
        setupNotifications()

        startAdvisorLoop()

        let showSettingsOnLaunch = Self.shouldShowSettingsOnLaunch()
        if configurationWarningTitle != nil {
            if showSettingsOnLaunch {
                scheduleSettingsPresentation()
            }
            return
        } else {
            advisorLoop?.fireNow()
        }

        if showSettingsOnLaunch {
            scheduleSettingsPresentation()
        }
    }

    private func startClockTimer() {
        clockTimer?.invalidate()
        // 60s cadence: relative labels are minute-grained, so this is the coarsest
        // interval that still keeps "N분 전" current without needless redraws.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            // Scheduled on RunLoop.main, so this block always fires on the main actor —
            // assert that isolation instead of hopping, keeping the synchronous access to
            // main-actor state (`isAnalyzing`, `updateStatusBarButton`) warning-free under
            // strict concurrency without changing behavior.
            MainActor.assumeIsolated {
                guard let self, !self.isAnalyzing else { return }
                self.updateStatusBarButton()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func startAdvisorLoop() {
        advisorLoop?.stop()
        advisorLoop = AdvisorLoop(intervalSeconds: config.intervalSeconds) { [weak self] in
            await self?.runAnalysis()
        }
        advisorLoop?.start()
    }

    @objc private func analyzeNow(_ sender: NSMenuItem) {
        advisorLoop?.fireNow()
    }

    private func runAnalysis() async {
        guard !isAnalyzing else { return }

        beginAnalysisStatus()

        do {
            let config = config
            let (snapshot, advice) = try await Task.detached(priority: .utility) {
                let text = AppStrings(languageIdentifier: config.resolvedOutputLanguageIdentifier())
                let collector = SystemMetricsCollector()
                let optimizerReport: MacOptimizerReport?
                do {
                    optimizerReport = try MacOptimizerScript.runIfAvailable(monitorSeconds: config.monitorSeconds, maxCharacters: 8_000)
                } catch {
                    optimizerReport = MacOptimizerReport(scriptPath: "mac-optimizer", output: "\(text.macOptimizerFailedPrefix): \(error)")
                }
                let providerKind = config.resolvedProviderKind
                let client = ProviderRegistry.makeClient(kind: providerKind)
                let provider = LLMAdviceProvider(
                    client: client,
                    config: config,
                    supportsStructuredOutput: providerKind.supportsStructuredOutput
                )
                let snapshot = try collector.collect()
                let advice = try await provider.advise(for: snapshot, optimizerReport: optimizerReport)
                return (snapshot, advice)
            }.value

            latestSnapshot = snapshot
            latestAdvice = advice
            failureActive = false
            // Fresh advice → previous "done" marks no longer apply (new pids/commands).
            completedCommandSignatures.removeAll()
            endAnalysisStatus()
            updateStatusBarButton()
            headerItem.title = AdviceFormatter.statusTitle(
                cpu: snapshot.cpu,
                memory: snapshot.memory,
                languageIdentifier: config.resolvedOutputLanguageIdentifier()
            )
            rebuildMenu()
        } catch {
            failureActive = true
            endAnalysisStatus()
            updateStatusBarButton()
            headerItem.title = strings.analysisFailed(shortDescription(error))
            rebuildMenu()
        }
    }

    private func beginAnalysisStatus() {
        isAnalyzing = true
        analysisStartedAt = Date()
        analysisSpinnerIndex = 0
        lastRenderedElapsedSeconds = nil
        updateStatusBarButton()
        updateAnalyzingStatus(rebuild: true, force: true)

        analysisElapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAnalysisSpinner()
                self?.updateAnalyzingStatus()
            }
        }
        analysisElapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func endAnalysisStatus() {
        isAnalyzing = false
        analysisStartedAt = nil
        analysisElapsedTimer?.invalidate()
        analysisElapsedTimer = nil
        analysisSpinnerIndex = 0
        lastRenderedElapsedSeconds = nil
    }

    private func updateStatusBarButton() {
        guard let button = statusItem?.button else { return }

        if isAnalyzing {
            applyAnalyzingDisplay(to: button)
            return
        }

        if failureActive {
            applyFailureDisplay(to: button)
            return
        }

        guard let latestAdvice else {
            applyDefaultIcon(to: button)
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        applyAdviceDisplay(to: button, advice: latestAdvice)
    }

    private func applyAnalyzingDisplay(to button: NSStatusBarButton) {
        button.image = nil
        let spinnerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let result = NSMutableAttributedString(
            string: " \(analysisSpinnerFrames[analysisSpinnerIndex])",
            attributes: spinnerAttributes
        )
        // First-run only: no prior advice yet, so the spinner is on its own.
        // Surface the model name (e.g. "Sonnet") to tell the user WHAT is running.
        // Re-analyses keep the previous menu state visible elsewhere; no need to repeat.
        if latestAdvice == nil {
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            result.append(NSAttributedString(
                string: " \(displayModelName())",
                attributes: labelAttributes
            ))
        }
        button.attributedTitle = result
    }

    private func displayModelName() -> String {
        let lower = config.model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("gpt") { return "GPT" }
        if lower.contains("gemini") { return "Gemini" }
        return config.model
    }

    private func applyFailureDisplay(to button: NSStatusBarButton) {
        button.image = nil
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        button.attributedTitle = NSAttributedString(string: " ⚠️", attributes: attributes)
    }

    private func applyAdviceDisplay(to button: NSStatusBarButton, advice: Advice) {
        let parts = AdviceFormatter.parseStatusBarTitle(advice.statusBar.title)
        let isCritical = AdviceFormatter.isCriticalStatusBarColor(advice.statusBar.color)
        let warningColor = statusBarColor(named: advice.statusBar.color)
        let relativeTime = AdviceFormatter.lastCheckRelativeString(
            generatedAt: advice.generatedAt,
            languageIdentifier: config.resolvedOutputLanguageIdentifier()
        )

        if parts.emoji != nil {
            button.image = nil
        } else {
            applyDefaultIcon(to: button)
        }

        button.attributedTitle = Self.buildAdviceAttributedTitle(
            emoji: parts.emoji,
            count: isCritical ? parts.count : nil,
            relativeTime: relativeTime,
            warningColor: warningColor
        )
    }

    private func applyDefaultIcon(to button: NSStatusBarButton) {
        if button.image != nil { return }
        if let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
            accessibilityDescription: strings.appAccessibilityDescription
        ) {
            image.isTemplate = true
            button.image = image
        }
    }

    private static func buildAdviceAttributedTitle(
        emoji: String?,
        count: String?,
        relativeTime: String,
        warningColor: NSColor
    ) -> NSAttributedString {
        let regularFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let monoFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let defaultColor = NSColor.labelColor

        let result = NSMutableAttributedString()
        var hasPrefix = false

        if let emoji = emoji, !emoji.isEmpty {
            result.append(NSAttributedString(
                string: " \(emoji)",
                attributes: [.font: regularFont, .foregroundColor: defaultColor]
            ))
            hasPrefix = true
        }

        if let count = count, !count.isEmpty {
            result.append(NSAttributedString(
                string: " \(count)",
                attributes: [.font: monoFont, .foregroundColor: warningColor]
            ))
            hasPrefix = true
        }

        if !relativeTime.isEmpty {
            let separator = hasPrefix ? " · " : " "
            result.append(NSAttributedString(
                string: "\(separator)\(relativeTime)",
                attributes: [.font: regularFont, .foregroundColor: defaultColor]
            ))
        }

        return result
    }

    private func advanceAnalysisSpinner() {
        guard isAnalyzing else { return }
        analysisSpinnerIndex = (analysisSpinnerIndex + 1) % analysisSpinnerFrames.count
        updateStatusBarButton()
    }

    private func statusBarColor(named name: String) -> NSColor {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hexColor = Self.hexColor(normalized) {
            return hexColor
        }
        switch normalized {
        case "red", "systemred":
            return .systemRed
        case "orange", "systemorange":
            return .systemOrange
        case "yellow", "systemyellow":
            return .systemYellow
        case "green", "systemgreen":
            return .systemGreen
        case "blue", "systemblue":
            return .systemBlue
        case "gray", "grey", "systemgray", "systemgrey":
            return .secondaryLabelColor
        default:
            return .labelColor
        }
    }

    private static func hexColor(_ value: String) -> NSColor? {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }

    private func updateAnalyzingStatus(now: Date = Date(), rebuild: Bool = false, force: Bool = false) {
        guard isAnalyzing, let analysisStartedAt else { return }
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(analysisStartedAt).rounded(.down)))
        guard force || elapsedSeconds != lastRenderedElapsedSeconds else { return }
        lastRenderedElapsedSeconds = elapsedSeconds
        headerItem.title = strings.analyzingElapsed(seconds: elapsedSeconds)
        if rebuild {
            rebuildMenu()
        } else {
            menu.update()
        }
    }

    private func rebuildMenu() {
        let text = strings
        menu.removeAllItems()
        menu.addItem(headerItem)
        if let advice = latestAdvice {
            // Exact last-check clock time lives here in the dropdown; the menu bar
            // shows it relatively ("2분 전").
            let exactTime = AdviceFormatter.lastCheckTimeString(
                generatedAt: advice.generatedAt,
                languageIdentifier: config.resolvedOutputLanguageIdentifier()
            )
            let lastCheckedItem = NSMenuItem(title: "\(text.lastCheckedLabel): \(exactTime)", action: nil, keyEquivalent: "")
            lastCheckedItem.isEnabled = false
            menu.addItem(lastCheckedItem)
        }
        menu.addItem(.separator())

        if let advice = latestAdvice, !advice.suggestions.isEmpty {
            for (line, suggestion) in zip(AdviceFormatter.menuLines(for: advice), advice.suggestions) {
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.submenu = submenu(for: suggestion)
                if let command = suggestion.suggestedCommand, completedCommandSignatures.contains(command) {
                    item.state = .on
                }
                menu.addItem(item)
            }
        } else {
            let emptyItem = NSMenuItem(title: text.noSuggestions, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: text.analyzeNow, action: #selector(analyzeNow(_:)), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: text.settingsMenuItem, action: #selector(showSettings(_:)), keyEquivalent: ","))
        // Only when running from a bundled .app — the bare dev binary has no updater.
        if updaterController != nil {
            menu.addItem(NSMenuItem(title: text.checkForUpdatesMenuItem, action: #selector(checkForUpdates(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: text.quit, action: #selector(quit(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    private func submenu(for suggestion: Suggestion) -> NSMenu {
        let text = strings
        let submenu = NSMenu()
        submenu.addItem(detailMenuItem(for: AdviceFormatter.detailLines(
            for: suggestion,
            languageIdentifier: config.resolvedOutputLanguageIdentifier()
        )))

        if let command = suggestion.suggestedCommand, !command.isEmpty {
            submenu.addItem(.separator())
            let isDone = completedCommandSignatures.contains(command)
            let runItem = NSMenuItem(title: isDone ? text.runCommandDone : text.runCommandNow, action: #selector(runCommandDirectly(_:)), keyEquivalent: "")
            runItem.target = self
            runItem.representedObject = command
            runItem.state = isDone ? .on : .off
            submenu.addItem(runItem)

            let terminalItem = NSMenuItem(title: text.openCommandInTerminal, action: #selector(openCommandInTerminal(_:)), keyEquivalent: "")
            terminalItem.target = self
            terminalItem.representedObject = command
            submenu.addItem(terminalItem)

            let reviewItem = NSMenuItem(title: text.reviewWith(provider: config.resolvedProviderKind.displayName), action: #selector(reviewSuggestionWithClaude(_:)), keyEquivalent: "")
            reviewItem.target = self
            reviewItem.representedObject = SuggestionMenuPayload(suggestion: suggestion)
            submenu.addItem(reviewItem)

            let copyItem = NSMenuItem(title: text.copyCommand, action: #selector(copyCommand(_:)), keyEquivalent: "")
            copyItem.target = self
            copyItem.representedObject = command
            submenu.addItem(copyItem)
        } else {
            submenu.addItem(.separator())
            let reviewItem = NSMenuItem(title: text.reviewWith(provider: config.resolvedProviderKind.displayName), action: #selector(reviewSuggestionWithClaude(_:)), keyEquivalent: "")
            reviewItem.target = self
            reviewItem.representedObject = SuggestionMenuPayload(suggestion: suggestion)
            submenu.addItem(reviewItem)
        }
        return submenu
    }

    private func detailMenuItem(for lines: [String]) -> NSMenuItem {
        let width: CGFloat = min(640, max(440, (NSScreen.main?.visibleFrame.width ?? 1_200) * 0.42))
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 10
        let spacing: CGFloat = 7
        let labelWidth = width - horizontalPadding * 2

        let fonts = lines.map { line in
            line.hasPrefix("$ ")
                ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                : NSFont.menuFont(ofSize: 0)
        }
        let heights = zip(lines, fonts).map { line, font in
            Self.wrappedTextHeight(for: line, font: font, width: labelWidth)
        }
        let totalHeight = verticalPadding * 2 + heights.reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: max(44, totalHeight)))

        var y = view.frame.height - verticalPadding
        for ((line, font), height) in zip(zip(lines, fonts), heights) {
            y -= height
            let label = NSTextField(wrappingLabelWithString: line)
            label.font = font
            label.textColor = .labelColor
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.frame = NSRect(x: horizontalPadding, y: y, width: labelWidth, height: height)
            view.addSubview(label)
            y -= spacing
        }

        let item = NSMenuItem()
        item.view = view
        return item
    }

    private static func wrappedTextHeight(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let rect = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        ).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 2
    }

    @objc private func openCommandInTerminal(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        do {
            try openTerminal(script: TerminalScriptBuilder.suggestedCommandDisplayScript(
                command: command,
                languageIdentifier: config.resolvedOutputLanguageIdentifier()
            ))
        } catch {
            showAlert(title: strings.terminalOpenFailed, message: shortDescription(error))
        }
    }

    @objc private func reviewSuggestionWithClaude(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SuggestionMenuPayload else { return }
        let providerKind = config.resolvedProviderKind
        // Resolve the selected provider's CLI; without it there is no review session.
        let executableURL = providerKind == .codex
            ? CodexCLIClient.defaultExecutableURL()
            : ClaudeCLIClient.defaultExecutableURL()
        guard let executableURL else {
            showAlert(title: strings.missingClaudeCLITitle, message: strings.missingClaudeCLIMessage)
            return
        }

        do {
            let prompt = TerminalScriptBuilder.claudeReviewPrompt(
                for: payload.suggestion,
                outputLanguageIdentifier: config.resolvedOutputLanguageIdentifier()
            )
            let promptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mac-optimizing-looper-review-\(UUID().uuidString).txt")
            try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
            let script: String
            switch providerKind {
            case .codex:
                script = TerminalScriptBuilder.codexReviewScript(
                    promptFilePath: promptURL.path,
                    codexExecutablePath: executableURL.path,
                    model: config.model,
                    effort: config.thinkingLevel,
                    fastMode: config.fastMode,
                    languageIdentifier: config.resolvedOutputLanguageIdentifier()
                )
            case .claude:
                script = TerminalScriptBuilder.claudeReviewScript(
                    promptFilePath: promptURL.path,
                    claudeExecutablePath: executableURL.path,
                    model: config.model,
                    languageIdentifier: config.resolvedOutputLanguageIdentifier()
                )
            }
            do {
                try openTerminal(script: script)
            } catch {
                try? FileManager.default.removeItem(at: promptURL)
                throw error
            }
        } catch {
            showAlert(title: strings.claudeReviewOpenFailed, message: shortDescription(error))
        }
    }

    @objc private func copyCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        // Copy action only writes text to the pasteboard. Direct execution is a
        // separate, explicitly user-initiated, risk-checked path (runCommandDirectly).
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    // MARK: - Direct command execution (user-initiated, gated)

    private func setupNotifications() {
        guard notificationsSupported else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.notificationsAuthorized = granted }
        }
    }

    @objc private func runCommandDirectly(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String, !command.isEmpty else { return }
        Task { await runWithSafeguards(command: command) }
    }

    /// risk-check → confirm-if-not-safe → background run → notify/show. Generating
    /// advice never reaches here; only this explicit click does.
    private func runWithSafeguards(command: String) async {
        guard !runningCommands.contains(command) else { return }
        runningCommands.insert(command)
        defer { runningCommands.remove(command) }

        let language = config.resolvedOutputLanguageIdentifier()

        // 1. LLM risk check. Any CLI failure maps to .unknown → still confirm.
        let verdict: CommandRiskVerdict
        do {
            verdict = try await riskAssessor.assess(
                command: command,
                provider: config.resolvedProviderKind,
                model: config.model,
                effort: config.thinkingLevel,
                fastMode: config.fastMode,
                languageIdentifier: language
            )
        } catch {
            verdict = CommandRiskVerdict(level: .unknown, reason: strings.safetyCheckUnavailable)
        }

        // 2. Confirm for anything not clearly safe.
        if verdict.requiresConfirmation {
            let reason = verdict.level == .unknown ? strings.safetyCheckUnavailable : verdict.reason
            guard confirmDangerousCommand(command: command, reason: reason) else { return }
        }

        // 3. Run in the background (sudo → GUI admin prompt inside the executor).
        let result = await CommandExecutor.run(command: command)

        // 4. Surface the result.
        presentResult(result)

        // 5. On success, mark this action done so the menu shows it checked.
        if result.succeeded {
            completedCommandSignatures.insert(command)
            rebuildMenu()
        }
    }

    private func confirmDangerousCommand(command: String, reason: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = strings.dangerousCommandTitle
        alert.informativeText = strings.dangerousCommandPrompt(reason: reason, command: command)
        // Cancel added first → it's the default (Return), biasing toward NOT running.
        alert.addButton(withTitle: strings.cancel)
        alert.addButton(withTitle: strings.runAnyway)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func presentResult(_ result: CommandExecutionResult) {
        if notificationsSupported && notificationsAuthorized {
            postResultNotification(result)
        } else {
            // No notifications available → open the window so output is never lost.
            openResultWindow(result)
        }
    }

    private func postResultNotification(_ result: CommandExecutionResult) {
        let id = UUID().uuidString
        commandResults[id] = result
        let content = UNMutableNotificationContent()
        content.title = result.succeeded
            ? strings.commandSucceededTitle(result.command)
            : strings.commandFailedTitle(result.command)
        content.body = strings.commandResultBody(exitCode: result.exitCode, durationSeconds: result.durationSeconds)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard error != nil else { return }
            // Posting failed → show the window so the result is never silently lost.
            Task { @MainActor in self?.openResultWindow(result) }
        }
    }

    private func openResultWindow(_ result: CommandExecutionResult) {
        let controller = resultWindowController ?? CommandResultWindowController()
        resultWindowController = controller
        controller.present(result: result, strings: strings)
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        scheduleSettingsPresentation()
    }

    private func scheduleSettingsPresentation() {
        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        let controller = settingsWindowController ?? SettingsWindowController { [weak self] newConfig in
            self?.saveAndApply(config: newConfig)
        }
        settingsWindowController = controller
        controller.configure(with: config)

        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        controller.showWindow(nil)
        if let window = controller.window {
            window.center()
            window.level = .floating
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func saveAndApply(config newConfig: AppConfig) {
        do {
            let previousLanguage = config.resolvedOutputLanguageIdentifier()
            let nextLanguage = newConfig.resolvedOutputLanguageIdentifier()
            try newConfig.saveDefault()
            config = newConfig
            if previousLanguage != nextLanguage {
                latestAdvice = nil
            }
            failureActive = false
            headerItem.title = strings.settingsSavedRefreshing
            updateStatusBarButton()
            rebuildMenu()
            startAdvisorLoop()
            advisorLoop?.fireNow()
        } catch {
            let alert = NSAlert()
            alert.messageText = strings.settingsSaveFailed
            alert.informativeText = shortDescription(error)
            alert.addButton(withTitle: strings.ok)
            alert.runModal()
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: - Software update (Sparkle)

    private func startUpdaterIfBundled() {
        // Sparkle errors out unless it runs from a real .app bundle; the dev loop
        // (`swift run`) executes the bare binary, so skip there. Manual "Check for
        // Updates…" is hidden in that case (rebuildMenu gates on updaterController).
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        // Accessory (LSUIElement) app: without activating first, Sparkle's update
        // window opens behind other apps and looks like nothing happened.
        NSApp.activate(ignoringOtherApps: true)
        updaterController?.checkForUpdates(sender)
    }

    // All terminal-opening features funnel through the shared TerminalLauncher so
    // app resolution and per-terminal launch quirks live in one place.
    private func openTerminal(script: String) throws {
        try TerminalLauncher(terminalBundleIdentifier: config.terminalAppBundleIdentifier).open(script: script)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func shortDescription(_ error: Error) -> String {
        let text = strings
        if let terminalError = error as? TerminalLaunchError {
            switch terminalError {
            case .applicationNotFound(let bundleIdentifier):
                return text.terminalAppNotFound(bundleIdentifier ?? "")
            case .launchFailed(let status):
                return text.processFailed(status: status, message: "")
            }
        }
        if let llmError = error as? LLMError {
            switch llmError {
            case .missingClaudeCLI:
                return text.missingClaudeCLITitle
            case .missingProviderCLI(let provider):
                return text.providerCLINotFound(provider: provider)
            case .processFailed(let status, let message):
                return text.processFailed(status: status, message: message)
            case .invalidResponse:
                return text.invalidResponseFormat
            case .decoding(let message):
                return text.decodingError(message)
            }
        }
        return String(describing: error)
    }

    private static func shouldShowSettingsOnLaunch() -> Bool {
        CommandLine.arguments.contains("--show-settings")
            || ProcessInfo.processInfo.environment["MAC_OPTIMIZING_LOOPER_SHOW_SETTINGS"] == "1"
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Show the banner even while the (accessory) app is active, otherwise a result
    // posted right after the click would be suppressed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Tapping the notification opens the stored full output for that run.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        Task { @MainActor in
            if let result = self.commandResults[id] {
                self.openResultWindow(result)
            }
            completionHandler()
        }
    }
}

private final class SuggestionMenuPayload: NSObject {
    let suggestion: Suggestion

    init(suggestion: Suggestion) {
        self.suggestion = suggestion
    }
}
