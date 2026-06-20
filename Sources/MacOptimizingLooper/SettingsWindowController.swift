import AppKit
import MacOptimizingLooperCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let providerPopup = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    // Free-text model entry, shown only when the model popup's "Custom…" is selected.
    private let modelCustomField = NSTextField()
    private let thinkingPopup = NSPopUpButton()
    private let fastModeCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let intervalSlider = NSSlider()
    private let intervalValueLabel = NSTextField(labelWithString: "")
    private let monitorSlider = NSSlider()
    private let monitorValueLabel = NSTextField(labelWithString: "")
    // Unified UI + analysis language. First item = "System default" (nil identifier).
    private let languagePopup = NSPopUpButton()
    // Sentinel representedObject for the "System default" popup entry (no override).
    private static let systemLanguageSentinel = ""

    // Discrete analysis-interval steps the slider snaps to (seconds).
    private static let intervalStepsSeconds = [600, 1_800, 3_600, 7_200, 14_400, 28_800, 57_600, 86_400, 129_600]
    // Discrete sustained-monitor durations (seconds). 0 = monitor off.
    private static let monitorStepsSeconds = [0, 10, 20, 30, 45, 60, 90, 120]
    private let terminalPopup = NSPopUpButton()
    private let detectedLanguageField = NSTextField(labelWithString: "")
    private let effectiveLanguageField = NSTextField(labelWithString: "")
    private let providerLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let modelCustomLabel = NSTextField(labelWithString: "")
    private let thinkingLabel = NSTextField(labelWithString: "")
    private let fastModeLabel = NSTextField(labelWithString: "")
    private let intervalLabel = NSTextField(labelWithString: "")
    private let monitorLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let terminalLabel = NSTextField(labelWithString: "")
    private var modelCustomRow: NSStackView?
    // Sentinel for the "Custom…" model popup entry (no catalog slug).
    private static let customModelSentinel = "__custom__"

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
    private var catalog = ProviderCatalog(models: [])
    private var terminalApplications: [TerminalApplication] = []
    private let onSave: (AppConfig) -> Void

    init(onSave: @escaping (AppConfig) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
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
        selectProvider(config.resolvedProviderKind)
        reloadCatalog()
        populateModels(selectingModel: config.model)
        populateEfforts(selecting: config.thinkingLevel)
        updateFastMode(checked: config.fastMode)
        setIntervalSlider(toNearestSeconds: config.intervalSeconds)
        updateIntervalValueLabel()
        setMonitorSlider(toNearestSeconds: config.monitorSeconds)
        updateMonitorValueLabel()
        selectLanguage(identifier: config.outputLanguageIdentifier)
        reloadTerminalPopup(selecting: config.terminalAppBundleIdentifier)
        applyLocalizedText()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        providerPopup.removeAllItems()
        for kind in LLMProviderKind.allCases {
            providerPopup.addItem(withTitle: kind.displayName)
            providerPopup.lastItem?.representedObject = kind.rawValue
        }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))

        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        modelCustomField.placeholderString = "model id"

        thinkingPopup.target = self
        thinkingPopup.action = #selector(thinkingChanged(_:))

        fastModeCheckbox.target = self
        fastModeCheckbox.action = #selector(fastModeToggled(_:))

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

        // Build the language popup once: "System default" (nil override) then every
        // shipped language by its own autonym. Localized titles are refreshed in
        // applyLocalizedText(); autonyms stay constant across UI languages.
        languagePopup.removeAllItems()
        languagePopup.addItem(withTitle: "")
        languagePopup.lastItem?.representedObject = Self.systemLanguageSentinel
        for language in AppConfig.supportedUILanguages {
            languagePopup.addItem(withTitle: language.autonym)
            languagePopup.lastItem?.representedObject = language.identifier
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        let providerRow = row(label: providerLabel, control: providerPopup)
        let modelRow = row(label: modelLabel, control: modelPopup)
        let customRow = row(label: modelCustomLabel, control: modelCustomField)
        modelCustomRow = customRow
        customRow.isHidden = true
        let thinkingRow = row(label: thinkingLabel, control: thinkingPopup)
        let fastModeRow = row(label: fastModeLabel, control: fastModeCheckbox)
        let intervalRow = sliderRow(label: intervalLabel, slider: intervalSlider, valueLabel: intervalValueLabel)
        let monitorRow = sliderRow(label: monitorLabel, slider: monitorSlider, valueLabel: monitorValueLabel)
        let languageRow = row(label: languageLabel, control: languagePopup)
        let terminalRow = row(label: terminalLabel, control: terminalPopup)
        let buttonStack = NSStackView(views: [cancelButton, saveButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.distribution = .gravityAreas

        let stack = NSStackView(views: [
            providerRow,
            modelRow,
            customRow,
            thinkingRow,
            fastModeRow,
            intervalRow,
            monitorRow,
            languageRow,
            terminalRow,
            effectiveLanguageField,
            detectedLanguageField,
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
            providerPopup.widthAnchor.constraint(equalToConstant: 160),
            modelPopup.widthAnchor.constraint(equalToConstant: 260),
            modelCustomField.widthAnchor.constraint(equalToConstant: 260),
            thinkingPopup.widthAnchor.constraint(equalToConstant: 200),
            intervalSlider.widthAnchor.constraint(equalToConstant: 200),
            intervalValueLabel.widthAnchor.constraint(equalToConstant: 64),
            monitorSlider.widthAnchor.constraint(equalToConstant: 200),
            monitorValueLabel.widthAnchor.constraint(equalToConstant: 64),
            languagePopup.widthAnchor.constraint(equalToConstant: 200),
            terminalPopup.widthAnchor.constraint(equalToConstant: 260),
            effectiveLanguageField.widthAnchor.constraint(equalToConstant: 452),
            detectedLanguageField.widthAnchor.constraint(equalToConstant: 452)
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

    // MARK: - Provider / model / effort cascading

    private var selectedProviderKind: LLMProviderKind {
        let raw = providerPopup.selectedItem?.representedObject as? String ?? LLMProviderKind.claude.rawValue
        return LLMProviderKind.resolved(raw)
    }

    private func selectProvider(_ kind: LLMProviderKind) {
        let index = LLMProviderKind.allCases.firstIndex(of: kind) ?? 0
        providerPopup.selectItem(at: index)
    }

    private func reloadCatalog() {
        catalog = ProviderRegistry.catalog(kind: selectedProviderKind).load()
    }

    /// Rebuilds the model popup from the current catalog, always ending with a
    /// "Custom…" escape. Selects `slug` if the catalog has it, otherwise Custom.
    private func populateModels(selectingModel slug: String) {
        let text = AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier())
        modelPopup.removeAllItems()
        for model in catalog.models {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.slug
        }
        modelPopup.addItem(withTitle: text.customModelOption)
        modelPopup.lastItem?.representedObject = Self.customModelSentinel

        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = catalog.models.firstIndex(where: { $0.slug == trimmed }) {
            modelPopup.selectItem(at: index)
            modelCustomField.stringValue = ""
        } else {
            modelPopup.selectItem(at: modelPopup.numberOfItems - 1)   // Custom…
            modelCustomField.stringValue = trimmed
        }
        updateCustomFieldVisibility()
    }

    private var isCustomModelSelected: Bool {
        (modelPopup.selectedItem?.representedObject as? String) == Self.customModelSentinel
    }

    private var selectedCatalogModel: ProviderModel? {
        guard let slug = modelPopup.selectedItem?.representedObject as? String,
              slug != Self.customModelSentinel else { return nil }
        return catalog.model(slug: slug)
    }

    private func updateCustomFieldVisibility() {
        modelCustomRow?.isHidden = !isCustomModelSelected
    }

    /// Fills the effort popup from the selected model's reasoning levels (or a provider
    /// fallback for a custom model), selecting `level` if present, else the model default.
    private func populateEfforts(selecting level: String) {
        let efforts: [ProviderEffort]
        let defaultLevel: String
        if let model = selectedCatalogModel {
            efforts = model.efforts
            defaultLevel = model.defaultEffort
        } else {
            efforts = fallbackEfforts()
            defaultLevel = efforts.first?.level ?? ""
        }

        thinkingPopup.removeAllItems()
        for effort in efforts {
            thinkingPopup.addItem(withTitle: effort.level)
            thinkingPopup.lastItem?.representedObject = effort.level
            if !effort.description.isEmpty {
                thinkingPopup.lastItem?.toolTip = effort.description
            }
        }
        thinkingPopup.isEnabled = !efforts.isEmpty

        let wanted = level.trimmingCharacters(in: .whitespacesAndNewlines)
        if efforts.contains(where: { $0.level == wanted }) {
            thinkingPopup.selectItem(withTitle: wanted)
        } else if !defaultLevel.isEmpty {
            thinkingPopup.selectItem(withTitle: defaultLevel)
        }
    }

    /// Effort levels offered for a custom (off-catalog) model: the union of every
    /// catalog model's levels, falling back to the claude set if the catalog is empty.
    private func fallbackEfforts() -> [ProviderEffort] {
        var seen = Set<String>()
        var union: [ProviderEffort] = []
        for model in catalog.models {
            for effort in model.efforts where seen.insert(effort.level).inserted {
                union.append(effort)
            }
        }
        if union.isEmpty {
            return AppConfig.validThinkingLevels.map { ProviderEffort(level: $0, description: "") }
        }
        return union
    }

    /// Enables Fast Mode only when the selected catalog model supports it; a custom or
    /// non-supporting model leaves it disabled and unchecked (no toggle we cannot honor).
    private func updateFastMode(checked: Bool) {
        let supports = selectedCatalogModel?.supportsFastMode ?? false
        fastModeCheckbox.isEnabled = supports
        fastModeCheckbox.state = (supports && checked) ? .on : .off
    }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        // Preserve a custom-typed model across the switch; otherwise default to the new
        // provider's first catalog model (not an empty "Custom…").
        let keepCustom = isCustomModelSelected ? modelCustomField.stringValue : nil
        reloadCatalog()
        let preferredModel = keepCustom ?? (catalog.models.first?.slug ?? "")
        populateModels(selectingModel: preferredModel)
        populateEfforts(selecting: thinkingPopup.titleOfSelectedItem ?? "")
        updateFastMode(checked: fastModeCheckbox.state == .on)
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        updateCustomFieldVisibility()
        populateEfforts(selecting: thinkingPopup.titleOfSelectedItem ?? "")
        updateFastMode(checked: fastModeCheckbox.state == .on)
    }

    @objc private func thinkingChanged(_ sender: NSPopUpButton) {}

    @objc private func fastModeToggled(_ sender: NSButton) {}

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

    // MARK: - Language selection

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        // Live-preview the resolved language without committing; UI language stays put
        // until Save, so the hint is shown in the current UI language.
        let chosen = AppConfig.normalizedLanguageIdentifier(selectedLanguageIdentifier())
        let resolved = chosen ?? AppConfig.defaultOutputLanguageIdentifier()
        let text = AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier())
        effectiveLanguageField.stringValue = text.currentAnalysisLanguage(resolved)
    }

    private func selectedLanguageIdentifier() -> String {
        (languagePopup.selectedItem?.representedObject as? String) ?? Self.systemLanguageSentinel
    }

    /// Selects the popup entry for `identifier` (nil → System default). An identifier that
    /// isn't one of the shipped languages (e.g. a hand-edited config) is preserved as a
    /// transient entry rather than silently dropped.
    private func selectLanguage(identifier: String?) {
        guard let identifier, !identifier.isEmpty else {
            languagePopup.selectItem(at: 0)
            return
        }
        if let index = languagePopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == identifier
        }) {
            languagePopup.selectItem(at: index)
            return
        }
        languagePopup.addItem(withTitle: identifier)
        languagePopup.lastItem?.representedObject = identifier
        languagePopup.selectItem(at: languagePopup.numberOfItems - 1)
    }

    private func applyLocalizedText() {
        let text = AppStrings(languageIdentifier: currentConfig.resolvedOutputLanguageIdentifier())
        window?.title = text.settingsWindowTitle
        providerLabel.stringValue = text.providerLabel
        modelLabel.stringValue = text.modelLabel
        modelCustomLabel.stringValue = text.customModelOption
        thinkingLabel.stringValue = text.thinkingLevelLabel
        fastModeLabel.stringValue = text.fastModeLabel
        fastModeCheckbox.title = text.fastModeCheckbox
        intervalLabel.stringValue = text.analysisIntervalLabel
        updateIntervalValueLabel()
        monitorLabel.stringValue = text.monitorDurationLabel
        updateMonitorValueLabel()
        languageLabel.stringValue = text.languageLabel
        // The "System default" entry (item 0) is the only popup title that localizes.
        languagePopup.item(at: 0)?.title = text.systemDefaultLanguage
        terminalLabel.stringValue = text.terminalAppLabel
        if terminalApplications.isEmpty, terminalPopup.numberOfItems > 0 {
            terminalPopup.item(at: 0)?.title = text.noTerminalAppsDetected
        }
        detectedLanguageField.stringValue = text.detectedMacOSLanguages(Self.detectedLanguageSummary())
        effectiveLanguageField.stringValue = text.currentAnalysisLanguage(currentConfig.resolvedOutputLanguageIdentifier())
        saveButton.title = text.save
        cancelButton.title = text.cancel
    }

    @objc private func save(_ sender: NSButton) {
        let interval = selectedIntervalSeconds()
        let languageIdentifier = AppConfig.normalizedLanguageIdentifier(selectedLanguageIdentifier())

        // Resolve the chosen model: a catalog slug, or the trimmed custom field.
        let chosenModel: String
        if isCustomModelSelected {
            chosenModel = modelCustomField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            chosenModel = (modelPopup.selectedItem?.representedObject as? String) ?? ""
        }

        var newConfig = currentConfig
        newConfig.provider = selectedProviderKind.rawValue
        newConfig.model = chosenModel.isEmpty ? AppConfig.defaults(environment: [:]).model : chosenModel
        newConfig.thinkingLevel = thinkingPopup.titleOfSelectedItem ?? currentConfig.thinkingLevel
        // Only persist Fast Mode when the control is actually enabled (model supports it).
        newConfig.fastMode = fastModeCheckbox.isEnabled && fastModeCheckbox.state == .on
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
