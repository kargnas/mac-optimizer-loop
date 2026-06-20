import AppKit
import MacOptimizingLooperCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let modelField = NSTextField()
    private let thinkingPopup = NSPopUpButton()
    private let intervalSlider = NSSlider()
    private let intervalValueLabel = NSTextField(labelWithString: "")
    private let monitorSlider = NSSlider()
    private let monitorValueLabel = NSTextField(labelWithString: "")
    private let languageField = NSTextField()

    // Discrete analysis-interval steps the slider snaps to (seconds).
    private static let intervalStepsSeconds = [600, 1_800, 3_600, 7_200, 14_400, 28_800, 57_600, 86_400, 129_600]
    // Discrete sustained-monitor durations (seconds). 0 = monitor off.
    private static let monitorStepsSeconds = [0, 10, 20, 30, 45, 60, 90, 120]
    private let terminalPopup = NSPopUpButton()
    private let detectedLanguageField = NSTextField(labelWithString: "")
    private let effectiveLanguageField = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let thinkingLabel = NSTextField(labelWithString: "")
    private let intervalLabel = NSTextField(labelWithString: "")
    private let monitorLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let terminalLabel = NSTextField(labelWithString: "")
    private let languageHelpField = NSTextField(labelWithString: "")
    private lazy var saveButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(save(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()
    private lazy var cancelButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(cancel(_:)))
        button.bezelStyle = .rounded
        return button
    }()
    private var currentConfig = AppConfig.defaults(environment: [:])
    private var terminalApplications: [TerminalApplication] = []
    private let onSave: (AppConfig) -> Void

    init(onSave: @escaping (AppConfig) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 394),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with config: AppConfig) {
        currentConfig = config
        modelField.stringValue = config.model
        thinkingPopup.selectItem(withTitle: config.thinkingLevel)
        setIntervalSlider(toNearestSeconds: config.intervalSeconds)
        updateIntervalValueLabel()
        setMonitorSlider(toNearestSeconds: config.monitorSeconds)
        updateMonitorValueLabel()
        languageField.stringValue = config.outputLanguageIdentifier ?? ""
        reloadTerminalPopup(selecting: config.terminalAppBundleIdentifier)
        applyLocalizedText()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        modelField.placeholderString = "sonnet"
        thinkingPopup.removeAllItems()
        thinkingPopup.addItems(withTitles: AppConfig.validThinkingLevels)

        // Snap-to-step slider over the 9 fixed interval values (10m … 36h).
        intervalSlider.minValue = 0
        intervalSlider.maxValue = Double(Self.intervalStepsSeconds.count - 1)
        intervalSlider.numberOfTickMarks = Self.intervalStepsSeconds.count
        intervalSlider.allowsTickMarkValuesOnly = true
        intervalSlider.isContinuous = true
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalChanged(_:))
        intervalValueLabel.textColor = .secondaryLabelColor
        intervalValueLabel.alignment = .left

        monitorSlider.minValue = 0
        monitorSlider.maxValue = Double(Self.monitorStepsSeconds.count - 1)
        monitorSlider.numberOfTickMarks = Self.monitorStepsSeconds.count
        monitorSlider.allowsTickMarkValuesOnly = true
        monitorSlider.isContinuous = true
        monitorSlider.target = self
        monitorSlider.action = #selector(monitorChanged(_:))
        monitorValueLabel.textColor = .secondaryLabelColor
        monitorValueLabel.alignment = .left
        detectedLanguageField.textColor = .secondaryLabelColor
        detectedLanguageField.lineBreakMode = .byWordWrapping
        detectedLanguageField.maximumNumberOfLines = 2
        effectiveLanguageField.textColor = .secondaryLabelColor
        effectiveLanguageField.lineBreakMode = .byWordWrapping
        effectiveLanguageField.maximumNumberOfLines = 2
        languageHelpField.textColor = .secondaryLabelColor
        languageHelpField.lineBreakMode = .byWordWrapping
        languageHelpField.maximumNumberOfLines = 2

        let modelRow = row(label: modelLabel, control: modelField)
        let thinkingRow = row(label: thinkingLabel, control: thinkingPopup)
        let intervalRow = sliderRow(label: intervalLabel, slider: intervalSlider, valueLabel: intervalValueLabel)
        let monitorRow = sliderRow(label: monitorLabel, slider: monitorSlider, valueLabel: monitorValueLabel)
        let languageRow = row(label: languageLabel, control: languageField)
        let terminalRow = row(label: terminalLabel, control: terminalPopup)
        let buttonStack = NSStackView(views: [cancelButton, saveButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.distribution = .gravityAreas

        let stack = NSStackView(views: [
            modelRow,
            thinkingRow,
            intervalRow,
            monitorRow,
            languageRow,
            terminalRow,
            effectiveLanguageField,
            detectedLanguageField,
            languageHelpField,
            buttonStack
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            modelField.widthAnchor.constraint(equalToConstant: 260),
            thinkingPopup.widthAnchor.constraint(equalToConstant: 160),
            intervalSlider.widthAnchor.constraint(equalToConstant: 200),
            intervalValueLabel.widthAnchor.constraint(equalToConstant: 64),
            monitorSlider.widthAnchor.constraint(equalToConstant: 200),
            monitorValueLabel.widthAnchor.constraint(equalToConstant: 64),
            languageField.widthAnchor.constraint(equalToConstant: 100),
            terminalPopup.widthAnchor.constraint(equalToConstant: 260),
            effectiveLanguageField.widthAnchor.constraint(equalToConstant: 452),
            detectedLanguageField.widthAnchor.constraint(equalToConstant: 452),
            languageHelpField.widthAnchor.constraint(equalToConstant: 452)
        ])
        reloadTerminalPopup(selecting: currentConfig.terminalAppBundleIdentifier)
        applyLocalizedText()
    }

    private func row(label text: NSTextField, control: NSControl) -> NSStackView {
        text.alignment = .right
        text.widthAnchor.constraint(equalToConstant: 170).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func sliderRow(label text: NSTextField, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        text.alignment = .right
        text.widthAnchor.constraint(equalToConstant: 170).isActive = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [text, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func intervalChanged(_ sender: NSSlider) {
        updateIntervalValueLabel()
    }

    private func selectedIntervalSeconds() -> Int {
        let index = Int(intervalSlider.doubleValue.rounded())
        let clamped = min(max(index, 0), Self.intervalStepsSeconds.count - 1)
        return Self.intervalStepsSeconds[clamped]
    }

    private func setIntervalSlider(toNearestSeconds seconds: Int) {
        let index = Self.intervalStepsSeconds.enumerated().min(by: {
            abs($0.element - seconds) < abs($1.element - seconds)
        })?.offset ?? 2
        intervalSlider.doubleValue = Double(index)
    }

    private func updateIntervalValueLabel() {
        let text = AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier())
        intervalValueLabel.stringValue = text.intervalLabel(seconds: selectedIntervalSeconds())
    }

    @objc private func monitorChanged(_ sender: NSSlider) {
        updateMonitorValueLabel()
    }

    private func selectedMonitorSeconds() -> Int {
        let index = Int(monitorSlider.doubleValue.rounded())
        let clamped = min(max(index, 0), Self.monitorStepsSeconds.count - 1)
        return Self.monitorStepsSeconds[clamped]
    }

    private func setMonitorSlider(toNearestSeconds seconds: Int) {
        let index = Self.monitorStepsSeconds.enumerated().min(by: {
            abs($0.element - seconds) < abs($1.element - seconds)
        })?.offset ?? 3
        monitorSlider.doubleValue = Double(index)
    }

    private func updateMonitorValueLabel() {
        let text = AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier())
        monitorValueLabel.stringValue = text.monitorDurationValue(seconds: selectedMonitorSeconds())
    }

    private func applyLocalizedText() {
        let text = AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier())
        window?.title = text.settingsWindowTitle
        modelLabel.stringValue = text.claudeModelLabel
        thinkingLabel.stringValue = text.thinkingLevelLabel
        intervalLabel.stringValue = text.analysisIntervalLabel
        updateIntervalValueLabel()
        monitorLabel.stringValue = text.monitorDurationLabel
        updateMonitorValueLabel()
        languageLabel.stringValue = text.analysisLanguageLabel
        terminalLabel.stringValue = text.terminalAppLabel
        languageField.placeholderString = text.languagePlaceholder
        if terminalApplications.isEmpty, terminalPopup.numberOfItems > 0 {
            terminalPopup.item(at: 0)?.title = text.noTerminalAppsDetected
        }
        detectedLanguageField.stringValue = text.detectedMacOSLanguages(Self.detectedLanguageSummary())
        effectiveLanguageField.stringValue = text.currentAnalysisLanguage(currentConfig.resolvedOutputLanguageIdentifier())
        languageHelpField.stringValue = text.languageHelp
        saveButton.title = text.save
        cancelButton.title = text.cancel
    }

    @objc private func save(_ sender: NSButton) {
        let interval = selectedIntervalSeconds()
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageIdentifier = AppConfig.normalizedLanguageIdentifier(languageField.stringValue)

        var newConfig = currentConfig
        newConfig.model = model.isEmpty ? AppConfig.defaults(environment: [:]).model : model
        newConfig.thinkingLevel = thinkingPopup.titleOfSelectedItem ?? currentConfig.thinkingLevel
        newConfig.monitorSeconds = selectedMonitorSeconds()
        newConfig.intervalSeconds = interval
        newConfig.outputLanguageIdentifier = languageIdentifier
        newConfig.terminalAppBundleIdentifier = selectedTerminalBundleIdentifier()
        onSave(newConfig)
        close()
    }

    @objc private func cancel(_ sender: NSButton) {
        close()
    }

    private static func detectedLanguageSummary() -> String {
        let languages = Locale.preferredLanguages
        guard !languages.isEmpty else {
            return Locale.current.identifier
        }
        return languages.joined(separator: " → ")
    }

    private func reloadTerminalPopup(selecting configuredBundleIdentifier: String?) {
        terminalApplications = TerminalAppCatalog.installedApplications()
        terminalPopup.removeAllItems()

        if terminalApplications.isEmpty {
            terminalPopup.addItem(withTitle: AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier()).noTerminalAppsDetected)
            terminalPopup.isEnabled = false
            return
        }

        terminalPopup.isEnabled = true
        for app in terminalApplications {
            terminalPopup.addItem(withTitle: app.displayName)
            terminalPopup.lastItem?.representedObject = app.bundleIdentifier
        }

        let selectedBundleIdentifier = configuredBundleIdentifier
            ?? TerminalAppCatalog.defaultBundleIdentifier
        if let index = terminalApplications.firstIndex(where: { $0.bundleIdentifier == selectedBundleIdentifier }) {
            terminalPopup.selectItem(at: index)
        } else {
            terminalPopup.selectItem(at: 0)
        }
    }

    private func selectedTerminalBundleIdentifier() -> String? {
        terminalPopup.selectedItem?.representedObject as? String
    }
}
