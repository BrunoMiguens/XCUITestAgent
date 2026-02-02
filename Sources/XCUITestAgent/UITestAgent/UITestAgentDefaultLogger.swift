import Foundation
import os

/// Default logger implementation that outputs to both `print()` (for Xcode console
/// and CI visibility) and `os_log` (for Console.app and Instruments integration).
public struct UITestAgentDefaultLogger: UITestAgentLogger {
    public let minimumLevel: UITestAgentLogLevel

    /// Categories to include. If nil, all categories are included.
    public let enabledCategories: Set<UITestAgentLogCategory>?

    private let subsystem: String

    /// Creates a default logger.
    ///
    /// - Parameters:
    ///   - minimumLevel: The minimum log level to emit. If nil, auto-detects:
    ///     CI environment -> `.info`, local -> `.debug`.
    ///   - enabledCategories: When non-nil, only messages in these categories are emitted.
    ///     When nil (default), all categories are logged.
    ///   - subsystem: The os_log subsystem identifier. Defaults to "com.xcuitestagent".
    public init(
        minimumLevel: UITestAgentLogLevel? = nil,
        enabledCategories: Set<UITestAgentLogCategory>? = nil,
        subsystem: String = "com.xcuitestagent"
    ) {
        self.minimumLevel = minimumLevel ?? Self.autoDetectLevel()
        self.enabledCategories = enabledCategories
        self.subsystem = subsystem
    }

    public func log(
        _ level: UITestAgentLogLevel,
        category: UITestAgentLogCategory,
        message: @autoclosure () -> String
    ) {
        guard level >= minimumLevel else { return }
        guard enabledCategories == nil || enabledCategories!.contains(category) else { return }

        let msg = message()

        // Primary: print for Xcode console and CI pipeline visibility.
        // Leading emoji makes XCUITestAgent lines stand out from XCTest framework output.
        let emoji = Self.lineEmoji(level: level, category: category)
        let paddedLevel = level.label.padding(toLength: 7, withPad: " ", startingAt: 0)
        let paddedCategory = category.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        print("\(emoji) \(Self.prefix) \(paddedLevel) | \(paddedCategory) | \(msg)")

        // Secondary: os_log for Console.app and Instruments
        let osLog = OSLog(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", msg)
        case .info:
            os_log(.info, log: osLog, "%{public}@", msg)
        case .warning:
            os_log(.default, log: osLog, "[WARNING] %{public}@", msg)
        case .error:
            os_log(.error, log: osLog, "%{public}@", msg)
        case .none:
            break
        }
    }

    public func logSeparator(_ style: UITestAgentLogSeparatorStyle, _ title: String? = nil) {
        switch style {
        case .heavy:
            let line = String(repeating: "=", count: Self.separatorWidth)
            print("🤖 \(Self.prefix) \(line)")
            if let title {
                print("🤖 \(Self.prefix)  \(title)")
                print("🤖 \(Self.prefix) \(line)")
            }
        case .light:
            if let title {
                let padding = max(0, Self.separatorWidth - title.count - 2)
                print("🔁 \(Self.prefix) \(title) \(String(repeating: "-", count: padding))")
            } else {
                print("🔁 \(Self.prefix) \(String(repeating: "-", count: Self.separatorWidth))")
            }
        }
    }

    // MARK: - Emoji helpers

    /// Returns a leading emoji for the print line. Warning/error levels take
    /// priority over category so they always stand out visually.
    private static func lineEmoji(level: UITestAgentLogLevel, category: UITestAgentLogCategory) -> String {
        switch level {
        case .warning: return "⚠️"
        case .error:   return "❌"
        default:       return categoryEmoji(category)
        }
    }

    private static func categoryEmoji(_ category: UITestAgentLogCategory) -> String {
        switch category {
        case .agentLoop: return "🤖"
        case .llmClient: return "🧠"
        case .mapping:   return "🔄"
        case .actions:   return "👆"
        case .prompt:    return "📝"
        }
    }

    // MARK: - Constants

    private static let prefix = "[XCUITestAgent]"
    private static let separatorWidth = 55

    /// CI auto-detection: if "CI" environment variable is set (common across
    /// GitHub Actions, Jenkins, GitLab CI, Bitrise, CircleCI), default to `.info`.
    /// Otherwise default to `.debug` for local development verbosity.
    private static func autoDetectLevel() -> UITestAgentLogLevel {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            return .info
        }
        return .debug
    }
}
