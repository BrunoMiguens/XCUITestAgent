import Foundation
import XCTest

public struct XCUITestAgentPromptProvider: UITestAgentPromptProvider {
    private let app: XCUIApplication
    private let encoder = JSONEncoder()
    private let logger: UITestAgentLogger

    public init(app: XCUIApplication, logger: UITestAgentLogger = UITestAgentDefaultLogger()) {
        self.app = app
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
        if let nonPasteHint = nonPasteTextEntryHint(from: hierarchy) {
            if let existing = testContext, !existing.isEmpty {
                testContext = "\(existing)\n\n\(nonPasteHint)"
            } else {
                testContext = nonPasteHint
            }
        }
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
    fileprivate func nonPasteTextEntryHint(from hierarchy: String) -> String? {
        let upper = hierarchy.uppercased()
        let hasKeyboard = upper.contains("KEYBOARD")
        let hasTextField = upper.contains("TEXTFIELD") || upper.contains("SECURETEXTFIELD")
        let hasSecureToggle = upper.contains("TOGGLE PASSCODE VISIBLE") || upper.contains("PASSCODE")
        guard hasKeyboard, (!hasTextField || hasSecureToggle) else {
            return nil
        }
        return """
            SCREEN HINT: This screen uses a custom/hidden text entry field. Do NOT use enterText/paste. Tap the entry area above the keyboard, then use a SINGLE typeText action with the full value. Do NOT tap individual keyboard keys.
            """
    }

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
                    delayUntilNextSequence: 1
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
                    delayUntilNextSequence: 1
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
                    delayUntilNextSequence: 1
                ))
            ),
            XCUITestAgentSystemPrompt.ResponseExample(
                description: "Example response for typing text character by character into a secure or custom text field where paste does not work",
                response: responseExample(LLMClientActionSequenceReponse(
                    description: "Type '12345678' into the SSN field.",
                    actions: [
                        .init(
                            actionType: .typeText,
                            elementFrame: "{{100.0, 200.0}, {120.0, 60.0}}",
                            swipeDirection: nil,
                            text: "12345678"
                        )
                    ],
                    delayUntilNextSequence: 2
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
                    delayUntilNextSequence: 1
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
                    delayUntilNextSequence: nil
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
            .scaled(toMaxHeight: 768)?
            .jpegData(compressionQuality: 0.80)
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
