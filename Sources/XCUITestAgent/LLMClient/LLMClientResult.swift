import Foundation

public struct LLMClientResult: Codable {
    public let content: String
    public let usage: LLMClientUsage?

    public init(content: String, usage: LLMClientUsage?) {
        self.content = content
        self.usage = usage
    }
}
