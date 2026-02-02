import Foundation

public extension LLMClient {
    func prompt(_ prompt: LLMClientPrompt, mapper: LLMClientResponseMapper) async throws -> ActionSequence {
        let result = try await self.prompt(prompt)
        return try mapper.map(response: result.content)
    }
}
