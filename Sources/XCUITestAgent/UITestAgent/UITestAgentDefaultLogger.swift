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

        // Primary: print for Xcode console and CI pipeline visibility
        print("[XCUITestAgent] [\(level.label)] [\(category.rawValue)] \(msg)")

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
