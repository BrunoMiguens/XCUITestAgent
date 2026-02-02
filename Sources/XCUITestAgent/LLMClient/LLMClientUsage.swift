import Foundation

public struct LLMClientUsage: Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let model: String

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        model: String
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.model = model
    }
}
