import Foundation

public protocol UITestAgentPromptProvider {
    func makePrompt(_ testPrompt: String, actionHistory: [ActionSequence]) throws -> LLMClientPrompt

    /// Capture the current screen state (e.g. view hierarchy) for change detection.
    /// Returns `nil` if screen state capture is not supported.
    func captureScreenState() -> String?
}

extension UITestAgentPromptProvider {
    public func captureScreenState() -> String? { nil }
}
