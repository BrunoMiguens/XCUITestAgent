import Foundation
import OpenAI

public struct OpenAIClient: LLMClient {
    public enum OpenAIClientError: Error {
        case invalidResponseFormat
    }

    private let client: OpenAI
    private let model: LLMModel
    private let imageDetail: LLMClientImageDetail
    private let temperature: Double?
    private let topP: Double?
    private let seed: Int?
    private let logger: UITestAgentLogger

    public init(
        client: OpenAI,
        model: LLMModel = .openAI(),
        imageDetail: LLMClientImageDetail = .high,
        temperature: Double? = 0,
        topP: Double? = nil,
        seed: Int? = nil,
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.client = client
        self.model = model
        self.imageDetail = imageDetail
        self.temperature = temperature
        self.topP = topP
        self.seed = seed
        self.logger = logger
    }

    public init(
        configuration: OpenAI.Configuration,
        model: LLMModel = .openAI(),
        imageDetail: LLMClientImageDetail = .high,
        temperature: Double? = 0,
        topP: Double? = nil,
        seed: Int? = nil,
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.client = OpenAI(configuration: configuration)
        self.model = model
        self.imageDetail = imageDetail
        self.temperature = temperature
        self.topP = topP
        self.seed = seed
        self.logger = logger
    }

    public init(
        apiToken: String,
        model: LLMModel = .openAI(),
        imageDetail: LLMClientImageDetail = .high,
        temperature: Double? = 0,
        topP: Double? = nil,
        seed: Int? = nil,
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.client = OpenAI(apiToken: apiToken)
        self.model = model
        self.imageDetail = imageDetail
        self.temperature = temperature
        self.topP = topP
        self.seed = seed
        self.logger = logger
    }

    public func prompt(_ prompt: LLMClientPrompt) async throws -> LLMClientResult {
        let messages = mapMessages(from: prompt)

        logger.debug(category: .llmClient, "Sending \(messages.count) messages to OpenAI (model: \(model.modelIdentifier))")
        logger.debug(category: .llmClient, "System prompt: \(prompt.systemPrompt.count) chars, screenshot: \(prompt.screenshotData?.count ?? 0) bytes, hierarchy: \(prompt.debugViewHierarchy.count) chars")

        let result = try await client.chats(query: ChatQuery(
            messages: messages,
            model: model.modelIdentifier,
            seed: seed,
            temperature: temperature,
            topP: topP
        ))

        guard let responseString = result.choices.first?.message.content?
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "") else {
            logger.error(category: .llmClient, "Invalid response format from OpenAI — no content in first choice")
            throw OpenAIClientError.invalidResponseFormat
        }

        logger.debug(category: .llmClient, "Received response (\(responseString.count) chars): \(String(responseString.prefix(200)))...")

        let usage: LLMClientUsage?
        if let completionUsage = result.usage {
            usage = LLMClientUsage(
                promptTokens: completionUsage.promptTokens,
                completionTokens: completionUsage.completionTokens,
                totalTokens: completionUsage.totalTokens,
                model: result.model
            )
            logger.info(category: .llmClient, "Token usage — prompt: \(completionUsage.promptTokens), completion: \(completionUsage.completionTokens), total: \(completionUsage.totalTokens), model: \(result.model)")
        } else {
            usage = nil
            logger.debug(category: .llmClient, "No usage data in OpenAI response")
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
                                detail: openAIImageDetail()
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

    private func openAIImageDetail() -> ChatQuery.ChatCompletionMessageParam.ContentPartImageParam.ImageURL.Detail? {
        switch imageDetail {
        case .low: return .low
        case .high: return .high
        case .auto: return .auto
        }
    }

    private func imageUrl(_ data: Data) -> String {
        "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
