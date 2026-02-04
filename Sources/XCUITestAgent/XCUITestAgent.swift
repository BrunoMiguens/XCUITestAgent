import Foundation
import XCTest

open class XCUITestAgent: UITestAgent {

    /// Creates an agent using the `LLMModel` enum.
    /// Defaults to `gpt-4.1-mini` with high image detail.
    public init(
        app: XCUIApplication,
        model: LLMModel = .openAI(),
        apiToken: String,
        logger: UITestAgentLogger = UITestAgentDefaultLogger(),
        auditProvider: UITestAgentAuditProvider? = nil,
        configuration: XCUITestAgentConfiguration = XCUITestAgentConfiguration()
    ) {
        let client: LLMClient
        switch model {
        case .openAI(_, let imageDetail):
            client = OpenAIClient(
                apiToken: apiToken,
                model: model,
                imageDetail: imageDetail,
                logger: logger
            )
        }
        super.init(
            client: client,
            responseMapper: LLMClientJSONResponseMapper(
                frameMapper: XCUITestFrameMapper(),
                logger: logger
            ),
            promptProvider: XCUITestAgentPromptProvider(
                app: app,
                configuration: configuration.prompt,
                logger: logger
            ),
            actionPerformer: XCUITestAgentActionPerformer(
                app: app,
                configuration: configuration.actions,
                logger: logger
            ),
            logger: logger,
            auditProvider: auditProvider,
            configuration: configuration.core
        )
    }

    /// Creates an agent with a custom `LLMClient` implementation.
    public init(
        app: XCUIApplication,
        client: LLMClient,
        logger: UITestAgentLogger = UITestAgentDefaultLogger(),
        auditProvider: UITestAgentAuditProvider? = nil,
        configuration: XCUITestAgentConfiguration = XCUITestAgentConfiguration()
    ) {
        super.init(
            client: client,
            responseMapper: LLMClientJSONResponseMapper(
                frameMapper: XCUITestFrameMapper(),
                logger: logger
            ),
            promptProvider: XCUITestAgentPromptProvider(
                app: app,
                configuration: configuration.prompt,
                logger: logger
            ),
            actionPerformer: XCUITestAgentActionPerformer(
                app: app,
                configuration: configuration.actions,
                logger: logger
            ),
            logger: logger,
            auditProvider: auditProvider,
            configuration: configuration.core
        )
    }
}
