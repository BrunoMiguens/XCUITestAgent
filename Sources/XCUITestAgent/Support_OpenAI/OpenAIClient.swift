import Foundation
import OpenAI

public struct OpenAIClient: LLMClient {
    public enum OpenAIClientError: Error {
        case invalidResponseFormat
    }

    private let client: OpenAI

    public init(client: OpenAI) {
        self.client = client
    }

    public init(configuration: OpenAI.Configuration) {
        self.client = OpenAI(configuration: configuration)
    }

    public init(apiToken: String) {
        self.client = OpenAI(apiToken: apiToken)
    }

    public func prompt(_ prompt: LLMClientPrompt) async throws -> LLMClientResult {
        let messages = mapMessages(from: prompt)

        let result = try await client.chats(query: ChatQuery(
            messages: messages,
            model: .gpt4_o
        ))

        guard let responseString = result.choices.first?.message.content?
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "") else {
            throw OpenAIClientError.invalidResponseFormat
        }

        let usage: LLMClientUsage?
        if let completionUsage = result.usage {
            usage = LLMClientUsage(
                promptTokens: completionUsage.promptTokens,
                completionTokens: completionUsage.completionTokens,
                totalTokens: completionUsage.totalTokens,
                model: result.model
            )
        } else {
            usage = nil
        }

        return LLMClientResult(
            content: responseString,
            usage: usage
        )
    }

    private func mapMessages(from prompt: LLMClientPrompt) -> [ChatQuery.ChatCompletionMessageParam] {
        var messages: [ChatQuery.ChatCompletionMessageParam] = [
            .system(ChatQuery.ChatCompletionMessageParam.SystemMessageParam(
                content: .textContent(prompt.systemPrompt)
            )),
            .user(ChatQuery.ChatCompletionMessageParam.UserMessageParam(
                content: .string(prompt.testPrompt)
            )),
        ]
        if let testContext = prompt.testContext {
            messages.append(
                .system(ChatQuery.ChatCompletionMessageParam.SystemMessageParam(
                    content: .textContent(testContext)
                ))
            )
        }
        if let screenshotData = prompt.screenshotData {
            messages.append(
                .user(ChatQuery.ChatCompletionMessageParam.UserMessageParam(
                    content: .contentParts([
                        .image(.init(
                            imageUrl: .init(
                                url: imageUrl(screenshotData),
                                detail: .high
                            )
                        ))
                    ])
                ))
            )
        }
        messages.append(
            .user(.init(content: .string(prompt.debugViewHierarchy)))
        )
        return messages
    }

    private func imageUrl(_ data: Data) -> String {
        "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
