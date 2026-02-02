import Foundation

/// Log severity levels, ordered from most verbose to most silent.
public enum UITestAgentLogLevel: Int, Comparable, Sendable {
    case debug   = 0
    case info    = 1
    case warning = 2
    case error   = 3
    case none    = 4

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARNING"
        case .error:   return "ERROR"
        case .none:    return ""
        }
    }
}

/// Categories that correspond to architectural layers.
/// Consumers can filter by category to focus on specific areas.
public enum UITestAgentLogCategory: String, Sendable, Hashable {
    case agentLoop = "AgentLoop"
    case llmClient = "LLMClient"
    case mapping   = "Mapping"
    case actions   = "Actions"
    case prompt    = "Prompt"
}

/// Visual separator styles for distinguishing agent phases in console output.
public enum UITestAgentLogSeparatorStyle {
    /// Heavy separator for major boundaries (test start/end).
    case heavy
    /// Light separator for minor boundaries (iteration start).
    case light
}

/// Protocol-based logger following the same injection pattern as LLMClient,
/// UITestAgentPromptProvider, UITestAgentActionPerformer, and LLMClientResponseMapper.
public protocol UITestAgentLogger {
    /// Log a message. The `message` parameter uses @autoclosure to defer
    /// string interpolation cost when the message would be filtered out.
    func log(
        _ level: UITestAgentLogLevel,
        category: UITestAgentLogCategory,
        message: @autoclosure () -> String
    )

    /// Print a visual separator to help distinguish agent phases in console output.
    func logSeparator(_ style: UITestAgentLogSeparatorStyle, _ title: String?)
}

// MARK: - Convenience methods

public extension UITestAgentLogger {
    /// Default no-op separator. Override in concrete loggers for visual output.
    func logSeparator(_ style: UITestAgentLogSeparatorStyle = .light, _ title: String? = nil) {}

    func debug(category: UITestAgentLogCategory, _ message: @autoclosure () -> String) {
        log(.debug, category: category, message: message())
    }

    func info(category: UITestAgentLogCategory, _ message: @autoclosure () -> String) {
        log(.info, category: category, message: message())
    }

    func warning(category: UITestAgentLogCategory, _ message: @autoclosure () -> String) {
        log(.warning, category: category, message: message())
    }

    func error(category: UITestAgentLogCategory, _ message: @autoclosure () -> String) {
        log(.error, category: category, message: message())
    }
}
