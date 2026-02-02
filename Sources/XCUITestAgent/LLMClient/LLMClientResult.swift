import Foundation

public struct LLMClientResult {
    public let content: String
    public let usage: LLMClientUsage?

    public init(content: String, usage: LLMClientUsage?) {
        self.content = content
        self.usage = usage
    }
}
