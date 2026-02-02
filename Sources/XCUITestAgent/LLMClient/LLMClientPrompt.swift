import Foundation

public struct LLMClientPrompt: Codable {
    /// System prompt describing intended agent behaviour and llm response format.
    public let systemPrompt: String

    /// Test prompt describing the test that is to be performed by the agent.
    public let testPrompt: String

    /// Any context in addition to the test prompt, e.g. any actions taken prioer to the current prompt.
    public let testContext: String?

    /// Screenshot of the app prior to prompting.
    public let screenshotData: Data?

    /// Debug description of view hierarchy including frames of views.
    public let debugViewHierarchy: String

    /// Behavioral knowledge context for the current screen, if available from prior runs.
    public let knowledgeContext: String?

    public init(
        systemPrompt: String,
        testPrompt: String,
        testContext: String?,
        screenshotData: Data?,
        debugViewHierarchy: String,
        knowledgeContext: String? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.testPrompt = testPrompt
        self.testContext = testContext
        self.screenshotData = screenshotData
        self.debugViewHierarchy = debugViewHierarchy
        self.knowledgeContext = knowledgeContext
    }
}
