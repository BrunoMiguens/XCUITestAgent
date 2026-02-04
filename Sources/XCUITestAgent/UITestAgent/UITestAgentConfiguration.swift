import Foundation

public struct UITestAgentConfiguration {
    public var retryLimit: Int
    public var maxIterations: Int
    public var maxAttemptsPerScreen: Int
    public var loopDetectionWindow: Int?

    public init(
        retryLimit: Int = 3,
        maxIterations: Int = 30,
        maxAttemptsPerScreen: Int = 5,
        loopDetectionWindow: Int? = nil
    ) {
        self.retryLimit = retryLimit
        self.maxIterations = maxIterations
        self.maxAttemptsPerScreen = maxAttemptsPerScreen
        self.loopDetectionWindow = loopDetectionWindow
    }

    public func resolvedLoopWindowSize() -> Int {
        loopDetectionWindow ?? max(6, maxAttemptsPerScreen * 2)
    }
}
