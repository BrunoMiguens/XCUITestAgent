import Foundation
import XCTest

open class XCUITestAgent: UITestAgent {
    public init(
        app: XCUIApplication,
        client: LLMClient,
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        super.init(
            client: client,
            responseMapper: LLMClientJSONResponseMapper(
                frameMapper: XCUITestFrameMapper(),
                logger: logger
            ),
            promptProvider: XCUITestAgentPromptProvider(app: app, logger: logger),
            actionPerformer: XCUITestAgentActionPerformer(app: app, logger: logger),
            logger: logger
        )
    }
}
