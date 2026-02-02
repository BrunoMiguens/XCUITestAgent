import Foundation

/// Protocol for loading and saving behavioral knowledge between test runs.
///
/// Follows the same injection pattern as other XCUITestAgent protocols
/// (`LLMClient`, `UITestAgentAuditProvider`, etc.).
///
/// Knowledge is keyed by a test identifier derived from `#file` + `#function`.
public protocol UITestAgentKnowledgeProvider {

    /// Load previously saved knowledge for a test.
    /// - Parameter testIdentifier: Stable key derived from the test's file + function name.
    /// - Returns: The saved knowledge, or `nil` if no prior knowledge exists.
    func loadKnowledge(for testIdentifier: String) -> UITestAgentKnowledge?

    /// Save knowledge after a test run completes.
    /// - Parameters:
    ///   - knowledge: The knowledge to persist.
    ///   - testIdentifier: Stable key derived from the test's file + function name.
    func saveKnowledge(_ knowledge: UITestAgentKnowledge, for testIdentifier: String)
}
