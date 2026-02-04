import Foundation
import XCTest

public struct XCUITestAgentPromptProvider: UITestAgentPromptProvider {
    private let app: XCUIApplication
    private let encoder = JSONEncoder()
    private let logger: UITestAgentLogger
    private let configuration: XCUITestAgentConfiguration.PromptConfiguration

    public init(
        app: XCUIApplication,
        configuration: XCUITestAgentConfiguration.PromptConfiguration = XCUITestAgentConfiguration.PromptConfiguration(),
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.app = app
        self.configuration = configuration
        self.logger = logger
    }

    public func captureScreenState() -> String? {
        return debugHierarchy(of: app)
    }

    public func makePrompt(_ testPrompt: String, actionHistory: [ActionSequence]) throws -> LLMClientPrompt {
        logger.debug(category: .prompt, "Building prompt with \(actionHistory.count) previous action(s)")

        let systemPrompt = XCUITestAgentSystemPrompt().make(
            responseFormat: .json,
            responseExamples: responseExamples(),
            additionalResponseDescription: XCUITestAgentAdditionalResponseDescriptionPrompt().make()
        )
        logger.debug(category: .prompt, "System prompt length: \(systemPrompt.count) chars")

        let screenshotData = makeScreenshotData(app: app)
        logger.debug(category: .prompt, "Screenshot captured: \(screenshotData?.count ?? 0) bytes")

        let hierarchy = debugHierarchy(of: app)
        logger.debug(category: .prompt, "View hierarchy length: \(hierarchy.count) chars")

        var testContext = XCUITestAgentTestContextPrompt().make(
            previousActionDescriptions: actionHistory.map { $0.description }
        )
        logger.debug(category: .prompt, "Test context: \(testContext?.count ?? 0) chars")

        return LLMClientPrompt(
            systemPrompt: systemPrompt,
            testPrompt: testPrompt,
            testContext: testContext,
            screenshotData: screenshotData,
            debugViewHierarchy: hierarchy
        )
    }
}

// MARK: - Response examples

extension XCUITestAgentPromptProvider {
    fileprivate func responseExamples() -> [XCUITestAgentSystemPrompt.ResponseExample] {
        return [
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for tapping the screen",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Tap '111' on the keyboard.",
                    actions: [
                        .init(
                            actionType: .tap,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: nil
                        ),
                        .init(
                            actionType: .tap,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: nil
                        ),
                        .init(
                            actionType: .tap,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: nil
                        )
                    ],
                    delayUntilNextSequence: 1,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for entering text into a textfield",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Enter text '7258' into the reg nr. field.",
                    actions: [
                        .init(
                            actionType: .enterText,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: "7258"
                        )
                    ],
                    delayUntilNextSequence: 1,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for entering text into two different textfields on the same screen",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Enter text '7258' into the reg nr. field. and '123412333' into the account number field.",
                    actions: [
                        .init(
                            actionType: .enterText,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: "7258"
                        ),
                        .init(
                            actionType: .enterText,
                            elementFrame: "{{250.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: "123412333"
                        )
                    ],
                    delayUntilNextSequence: 1,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for typing text character by character into a secure or custom text field where paste does not work",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Type '12345678' into the secure field.",
                    actions: [
                        .init(
                            actionType: .typeText,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: "12345678"
                        )
                    ],
                    delayUntilNextSequence: 2,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for swiping an element from left to right",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Swipe the confirm to swipe control.",
                    actions: [
                        .init(
                            actionType: .swipe,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: .right,
                            text: nil
                        )
                    ],
                    delayUntilNextSequence: 1,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for adjusting multiple picker columns and proceeding",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Swipe each picker column to the required values, then tap Continue.",
                    actions: [
                        .init(
                            actionType: .swipe,
                            elementFrame: "{{80.0, 443.3}, {103.3, 56.0}}",
                            swipeDirection: .up,
                            text: nil
                        ),
                        .init(
                            actionType: .swipe,
                            elementFrame: "{{128.0, 443.3}, {130.3, 56.0}}",
                            swipeDirection: .up,
                            text: nil
                        ),
                        .init(
                            actionType: .swipe,
                            elementFrame: "{{258.6, 443.3}, {103.3, 56.0}}",
                            swipeDirection: .up,
                            text: nil
                        ),
                        .init(
                            actionType: .tap,
                            elementFrame: "{{32.0, 792.0}, {338.0, 50.0}}",
                            swipeDirection: nil,
                            text: nil
                        )
                    ],
                    delayUntilNextSequence: 1,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for revealing a target in a scrollable view and selecting it",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Swipe the list up to reveal the target item, then tap it.",
                    actions: [
                        .init(
                            actionType: .swipe,
                            elementFrame: "{{24.0, 160.0}, {354.0, 520.0}}",
                            swipeDirection: .up,
                            text: nil
                        ),
                        .init(
                            actionType: .tap,
                            elementFrame: "{{24.0, 300.0}, {354.0, 44.0}}",
                            swipeDirection: nil,
                            text: nil
                        )
                    ],
                    delayUntilNextSequence: 1,
                    text: nil
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for succeeding the test",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Succeed the test because the screen contains a photo of a dog as required.",
                    actions: [
                        .init(
                            actionType: .success,
                            elementFrame: nil,
                            swipeDirection: nil,
                            text: nil
                        )
                    ],
                    delayUntilNextSequence: nil,
                    text: nil
                ))
            )
        ]
    }

    fileprivate func responseExample(_ encodable: Encodable) -> String {
        guard let data = try? encoder.encode(encodable),
              let jsonString = String(data: data, encoding: .utf8) else {
            return ""
        }
        return jsonString
    }
}

// MARK: - Screenshot processing

extension XCUITestAgentPromptProvider {
    fileprivate func makeScreenshotData(app: XCUIApplication) -> Data? {
        return app.screenshot().image
            .scaled(toMaxHeight: configuration.screenshotMaxHeight)?
            .jpegData(compressionQuality: configuration.screenshotJPEGQuality)
    }
}

extension UIImage {
    fileprivate func scaled(toMaxHeight maxHeight: CGFloat) -> UIImage? {
        let aspectRatio = self.size.width / self.size.height

        // If height is already within limits, return the original image
        if self.size.height <= maxHeight {
            return self
        }

        // Calculate new width while maintaining aspect ratio
        let newHeight = maxHeight
        let newWidth = newHeight * aspectRatio
        let newSize = CGSize(width: newWidth, height: newHeight)

        // Render the new image
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage
    }
}

// MARK: - Debug view hierarchy

extension XCUITestAgentPromptProvider {
    fileprivate func debugHierarchy(of app: XCUIApplication) -> String {
        var output = app.debugDescription
        output = removePattern(", 0x[0-9a-fA-F]+", from: output)
        output = removePattern(", pid: \\d+", from: output)
        output = removePattern(#"identifier: '.*?'\s?"#, from: output)
        return output
    }

    fileprivate func removePattern(_ pattern: String, from input: String) -> String {
        do {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: []
            )
            let modifiedString = regex.stringByReplacingMatches(
                in: input,
                options: [],
                range: NSRange(input.startIndex..., in: input),
                withTemplate: ""
            )
            return modifiedString
        } catch {
            return input
        }
    }
}
