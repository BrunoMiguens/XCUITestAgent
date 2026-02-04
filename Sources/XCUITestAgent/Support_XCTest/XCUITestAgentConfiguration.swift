import Foundation
import CoreGraphics

public struct XCUITestAgentConfiguration {
    public struct PromptConfiguration {
        public var screenshotMaxHeight: CGFloat
        public var screenshotJPEGQuality: CGFloat

        public init(
            screenshotMaxHeight: CGFloat = 768,
            screenshotJPEGQuality: CGFloat = 0.80
        ) {
            self.screenshotMaxHeight = screenshotMaxHeight
            self.screenshotJPEGQuality = screenshotJPEGQuality
        }
    }

    public struct ActionConfiguration {
        public var textEntryStrategy: TextEntryStrategy
        public var pasteMenuTimeout: TimeInterval
        public var enterTextInitialDelay: TimeInterval
        public var typeTextInitialDelay: TimeInterval
        public var defaultSequenceDelay: TimeInterval
        public var swipePressDuration: TimeInterval
        public var swipeInsetRatio: CGFloat

        public init(
            textEntryStrategy: TextEntryStrategy = .enterTextFirst,
            pasteMenuTimeout: TimeInterval = 3,
            enterTextInitialDelay: TimeInterval = 1,
            typeTextInitialDelay: TimeInterval = 1,
            defaultSequenceDelay: TimeInterval = 1,
            swipePressDuration: TimeInterval = 0.2,
            swipeInsetRatio: CGFloat = 0.2
        ) {
            self.textEntryStrategy = textEntryStrategy
            self.pasteMenuTimeout = pasteMenuTimeout
            self.enterTextInitialDelay = enterTextInitialDelay
            self.typeTextInitialDelay = typeTextInitialDelay
            self.defaultSequenceDelay = defaultSequenceDelay
            self.swipePressDuration = swipePressDuration
            self.swipeInsetRatio = swipeInsetRatio
        }
    }

    public enum TextEntryStrategy {
        case enterTextFirst
        case enterTextOnly
        case typeTextOnly
    }

    public var core: UITestAgentConfiguration
    public var prompt: PromptConfiguration
    public var actions: ActionConfiguration

    public init(
        core: UITestAgentConfiguration = UITestAgentConfiguration(),
        prompt: PromptConfiguration = PromptConfiguration(),
        actions: ActionConfiguration = ActionConfiguration()
    ) {
        self.core = core
        self.prompt = prompt
        self.actions = actions
    }
}
