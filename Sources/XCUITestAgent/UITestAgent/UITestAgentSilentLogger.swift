import Foundation

/// A no-op logger that discards all messages.
/// The @autoclosure ensures message string interpolation is never evaluated.
public struct UITestAgentSilentLogger: UITestAgentLogger {
    public init() {}

    public func log(
        _ level: UITestAgentLogLevel,
        category: UITestAgentLogCategory,
        message: @autoclosure () -> String
    ) {}
}
