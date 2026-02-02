import Foundation

/// Protocol for recording LLM interactions during test execution.
///
/// Follows the same injection pattern as `UITestAgentLogger`,
/// `UITestAgentPromptProvider`, and `UITestAgentActionPerformer`.
///
/// Implementations must be safe to call from a synchronous context.
/// Methods are called sequentially from the agent's main test loop.
public protocol UITestAgentAuditProvider {

    /// Called when a test begins execution.
    /// - Parameter testPrompt: The natural language test description.
    func testDidStart(testPrompt: String)

    /// Called after each LLM interaction (success or failure).
    /// - Parameter entry: The recorded interaction data.
    func record(_ entry: UITestAgentAuditEntry)

    /// Called when a test finishes execution.
    /// - Parameters:
    ///   - testPrompt: The natural language test description.
    ///   - iterations: The total number of loop iterations completed.
    ///   - outcome: Whether the test succeeded, failed, or errored.
    func testDidEnd(
        testPrompt: String,
        iterations: Int,
        outcome: UITestAgentAuditOutcome
    )
}
