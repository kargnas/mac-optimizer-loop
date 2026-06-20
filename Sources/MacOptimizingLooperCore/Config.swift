import Foundation

public enum ConfigError: Error, Equatable {
    case malformedFile
    case unreadableFile
}

public struct AppConfig: Equatable {
    public var model: String
    /// Claude `--effort` level for the analysis pass: low/medium/high/xhigh/max.
    public var thinkingLevel: String
    /// Seconds the mac-optimizer sustained monitor samples before evaluating. 0 disables it.
    public var monitorSeconds: Int
    public var intervalSeconds: Int
    /// Optional user override. `nil` means follow the current primary macOS language.
    public var outputLanguageIdentifier: String?
    public var terminalAppBundleIdentifier: String?
    public var maxTokens: Int
    public var temperature: Double

    public static let validThinkingLevels = ["low", "medium", "high", "xhigh", "max"]

    public init(
        model: String,
        thinkingLevel: String = "max",
        monitorSeconds: Int = 30,
        intervalSeconds: Int,
        outputLanguageIdentifier: String? = nil,
        terminalAppBundleIdentifier: String? = nil,
        maxTokens: Int,
        temperature: Double
    ) {
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.monitorSeconds = monitorSeconds
        self.intervalSeconds = intervalSeconds
        self.outputLanguageIdentifier = outputLanguageIdentifier
        self.terminalAppBundleIdentifier = terminalAppBundleIdentifier
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    public static func defaults(environment: [String: String]) -> AppConfig {
        var config = AppConfig(
            model: "sonnet",
            thinkingLevel: "max",
            monitorSeconds: 30,
            intervalSeconds: 3_600,
            outputLanguageIdentifier: nil,
            terminalAppBundleIdentifier: "com.apple.Terminal",
            maxTokens: 8192,
            temperature: 0.2
        )

        config.intervalSeconds = max(60, config.intervalSeconds)
        return config
    }

    public static func load(environment: [String: String], fileContents: Data?) throws -> AppConfig {
        guard let fileContents else {
            return defaults(environment: environment)
        }

        var config = defaults(environment: environment)

        let fileConfig: FileConfig
        do {
            fileConfig = try JSONDecoder().decode(FileConfig.self, from: fileContents)
        } catch {
            throw ConfigError.malformedFile
        }

        if let model = fileConfig.model {
            config.model = model
        }
        if let thinkingLevel = fileConfig.thinkingLevel {
            config.thinkingLevel = normalizedThinkingLevel(thinkingLevel)
        }
        if let monitorSeconds = fileConfig.monitorSeconds {
            config.monitorSeconds = normalizedMonitorSeconds(monitorSeconds)
        }
        if let intervalSeconds = fileConfig.intervalSeconds {
            config.intervalSeconds = intervalSeconds
        }
        if let outputLanguageIdentifier = fileConfig.outputLanguageIdentifier {
            config.outputLanguageIdentifier = normalizedLanguageIdentifier(outputLanguageIdentifier)
        }
        if let terminalAppBundleIdentifier = fileConfig.terminalAppBundleIdentifier {
            config.terminalAppBundleIdentifier = normalizedTerminalAppBundleIdentifier(terminalAppBundleIdentifier)
        }
        if let maxTokens = fileConfig.maxTokens {
            config.maxTokens = maxTokens
        }
        if let temperature = fileConfig.temperature {
            config.temperature = temperature
        }

        config.intervalSeconds = max(60, config.intervalSeconds)
        return config
    }

    public static func loadDefault() throws -> AppConfig {
        let configURL = defaultConfigURL
        let environment = ProcessInfo.processInfo.environment

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return try load(environment: environment, fileContents: nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw ConfigError.unreadableFile
        }

        return try load(environment: environment, fileContents: data)
    }

    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-optimizing-looper/config.json")
    }

    public func saveDefault() throws {
        let configURL = Self.defaultConfigURL
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettySorted.encode(FileConfig(
            model: model,
            thinkingLevel: thinkingLevel,
            monitorSeconds: monitorSeconds,
            intervalSeconds: intervalSeconds,
            outputLanguageIdentifier: outputLanguageIdentifier,
            terminalAppBundleIdentifier: terminalAppBundleIdentifier,
            maxTokens: maxTokens,
            temperature: temperature
        ))
        try data.write(to: configURL, options: .atomic)
    }

    public static func defaultOutputLanguageIdentifier(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        return Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    public static func normalizedLanguageIdentifier(
        _ identifier: String
    ) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "system" {
            return nil
        }
        return trimmed
    }

    public static func normalizedTerminalAppBundleIdentifier(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Clamps a thinking level to a known Claude `--effort` value, defaulting to
    /// "max" for empty/unknown input so a typo never silently weakens reasoning.
    public static func normalizedThinkingLevel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return validThinkingLevels.contains(trimmed) ? trimmed : "max"
    }

    /// Clamps the sustained-monitor duration to a sane range (0–600s; 0 disables it).
    public static func normalizedMonitorSeconds(_ value: Int) -> Int {
        max(0, min(600, value))
    }

    public func resolvedOutputLanguageIdentifier(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        outputLanguageIdentifier ?? Self.defaultOutputLanguageIdentifier(environment: environment)
    }
}

private struct FileConfig: Codable {
    let model: String?
    let thinkingLevel: String?
    let monitorSeconds: Int?
    let intervalSeconds: Int?
    let outputLanguageIdentifier: String?
    let terminalAppBundleIdentifier: String?
    let maxTokens: Int?
    let temperature: Double?
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
