import Foundation

/// A single recorded LLM interaction within a test run.
public struct UITestAgentAuditEntry: Codable {

    /// When this LLM call was initiated.
    public let timestamp: Date

    /// The 1-based iteration index within the test's main loop.
    public let iteration: Int

    /// The 1-based index of this LLM call across the entire test run
    /// (accounts for retries within a single iteration).
    public let llmCallIndex: Int

    /// The prompt sent to the LLM.
    /// Note: `screenshotData` may be nil even when a screenshot was sent,
    /// if the audit provider is configured to exclude screenshots.
    public let prompt: LLMClientPrompt

    /// The raw LLM response on success, or nil on error.
    public let result: LLMClientResult?

    /// The error description if the LLM call or response mapping failed.
    public let errorDescription: String?

    /// Wall-clock duration of the LLM call in seconds.
    public let duration: TimeInterval

    /// The description of the mapped action sequence, if mapping succeeded.
    public let mappedActionDescription: String?

    /// The number of actions in the mapped sequence, if mapping succeeded.
    public let mappedActionCount: Int?

    /// The calculated cost for this LLM call, if usage data was available.
    public let cost: LLMClientCost?

    /// Whether this entry represents a successful LLM interaction.
    public var isSuccess: Bool { errorDescription == nil }

    public init(
        timestamp: Date,
        iteration: Int,
        llmCallIndex: Int,
        prompt: LLMClientPrompt,
        result: LLMClientResult?,
        errorDescription: String?,
        duration: TimeInterval,
        mappedActionDescription: String?,
        mappedActionCount: Int?,
        cost: LLMClientCost?
    ) {
        self.timestamp = timestamp
        self.iteration = iteration
        self.llmCallIndex = llmCallIndex
        self.prompt = prompt
        self.result = result
        self.errorDescription = errorDescription
        self.duration = duration
        self.mappedActionDescription = mappedActionDescription
        self.mappedActionCount = mappedActionCount
        self.cost = cost
    }
}
