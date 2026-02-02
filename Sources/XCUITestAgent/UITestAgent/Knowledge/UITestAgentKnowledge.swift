import Foundation

/// Per-test knowledge capturing the behavioral patterns observed across runs.
///
/// Knowledge is keyed by test identifier (derived from `#file` + `#function`)
/// and contains an ordered sequence of screen types encountered, along with
/// a flow graph describing transitions between screens.
public struct UITestAgentKnowledge: Codable {
    /// Stable identifier for the test (e.g. "MyTestFile_testLogin").
    public let testIdentifier: String

    /// Ordered sequence of screen types encountered (by first appearance).
    public var screenSequence: [ScreenKnowledge]

    /// Graph of transitions observed between screen types.
    public var flowGraph: [FlowEdge]

    /// Number of successful runs that contributed to this knowledge.
    public var successfulRunCount: Int

    /// When this knowledge was last updated.
    public var lastUpdated: Date

    public init(
        testIdentifier: String,
        screenSequence: [ScreenKnowledge] = [],
        flowGraph: [FlowEdge] = [],
        successfulRunCount: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.testIdentifier = testIdentifier
        self.screenSequence = screenSequence
        self.flowGraph = flowGraph
        self.successfulRunCount = successfulRunCount
        self.lastUpdated = lastUpdated
    }
}

/// Behavioral knowledge about a screen type, identified by its structural fingerprint.
///
/// Knowledge captures BEHAVIOR, not content/values. Two screens with the same
/// structure (e.g. "First Name" and "Last Name" text entry screens) share the
/// same fingerprint and behavioral knowledge. Values never matter — what matters
/// is the potential behaviors one might encounter.
public struct ScreenKnowledge: Codable {
    /// SHA-256 hash of the normalized structural elements (types + depth, no text content).
    public let screenFingerprint: String

    /// Human-readable descriptions seen for this screen type (e.g. ["First Name", "Last Name"]).
    public var descriptions: [String]

    /// Behaviors that led to successful progression (e.g. "Enter text in text field, tap Continue").
    public var successfulBehaviors: [String]

    /// Behaviors that were attempted but did not work (e.g. "Tap the date picker cell directly").
    public var failedBehaviors: [String]

    /// Edge cases or special notes (e.g. "paste doesn't work on secure fields, use typeText").
    public var notes: [String]

    /// How many times this screen type has been encountered across all runs.
    public var encounterCount: Int

    /// Structural elements that define this screen type (e.g. ["NavigationBar", "TextField", "Button"]).
    public let keyElements: [String]

    public init(
        screenFingerprint: String,
        descriptions: [String] = [],
        successfulBehaviors: [String] = [],
        failedBehaviors: [String] = [],
        notes: [String] = [],
        encounterCount: Int = 0,
        keyElements: [String] = []
    ) {
        self.screenFingerprint = screenFingerprint
        self.descriptions = descriptions
        self.successfulBehaviors = successfulBehaviors
        self.failedBehaviors = failedBehaviors
        self.notes = notes
        self.encounterCount = encounterCount
        self.keyElements = keyElements
    }
}

/// A directed edge in the flow graph: from one screen type, via an action behavior, to another.
public struct FlowEdge: Codable {
    /// Fingerprint of the screen where the action was performed.
    public let fromFingerprint: String

    /// Fingerprint of the screen that appeared after the action.
    public let toFingerprint: String

    /// Description of the action behavior that caused the transition.
    public let actionBehavior: String

    public init(
        fromFingerprint: String,
        toFingerprint: String,
        actionBehavior: String
    ) {
        self.fromFingerprint = fromFingerprint
        self.toFingerprint = toFingerprint
        self.actionBehavior = actionBehavior
    }
}
