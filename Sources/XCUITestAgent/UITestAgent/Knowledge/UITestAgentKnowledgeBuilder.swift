import Foundation

/// Builds or updates `UITestAgentKnowledge` from data collected during a test run.
///
/// After a test completes, the builder merges run observations (screen fingerprints,
/// action descriptions, screen change summaries) into existing knowledge (if any)
/// or creates new knowledge from scratch.
///
/// **Merge rules:**
/// - Successful run: updates `successfulBehaviors`, increments counts, updates flow graph
/// - Failed run: appends `failedBehaviors` only, preserves previous successful data
/// - Screen types: merged by fingerprint (descriptions are additive)
public struct UITestAgentKnowledgeBuilder {

    /// Data collected for one iteration during a test run.
    public struct IterationRecord {
        /// Screen hierarchy captured before the action.
        public let screenHierarchy: String
        /// The fingerprint of the screen.
        public let screenFingerprint: String
        /// Human-readable screen description.
        public let screenDescription: String
        /// Key structural elements.
        public let keyElements: [String]
        /// The LLM-generated action description (what the agent decided to do).
        public let actionDescription: String
        /// Screen change summary after the action.
        public let screenChangeSummary: ScreenChangeDetector.ScreenChangeSummary?

        public init(
            screenHierarchy: String,
            screenFingerprint: String,
            screenDescription: String,
            keyElements: [String],
            actionDescription: String,
            screenChangeSummary: ScreenChangeDetector.ScreenChangeSummary?
        ) {
            self.screenHierarchy = screenHierarchy
            self.screenFingerprint = screenFingerprint
            self.screenDescription = screenDescription
            self.keyElements = keyElements
            self.actionDescription = actionDescription
            self.screenChangeSummary = screenChangeSummary
        }
    }

    public init() {}

    /// Build or update knowledge from a completed test run.
    /// - Parameters:
    ///   - existing: Previously loaded knowledge (may be `nil` for first run).
    ///   - testIdentifier: Stable test identifier.
    ///   - records: Iteration records from this run.
    ///   - testSucceeded: Whether the test passed.
    /// - Returns: Updated knowledge ready to be saved.
    public func build(
        existing: UITestAgentKnowledge?,
        testIdentifier: String,
        records: [IterationRecord],
        testSucceeded: Bool
    ) -> UITestAgentKnowledge {
        var knowledge = existing ?? UITestAgentKnowledge(testIdentifier: testIdentifier)

        if testSucceeded {
            knowledge.successfulRunCount += 1
        }
        knowledge.lastUpdated = Date()

        // Process each iteration record
        for (index, record) in records.enumerated() {
            mergeScreenKnowledge(
                into: &knowledge,
                record: record,
                testSucceeded: testSucceeded
            )

            // Build flow edges from consecutive iterations
            if index > 0 {
                let previousRecord = records[index - 1]
                if previousRecord.screenFingerprint != record.screenFingerprint {
                    mergeFlowEdge(
                        into: &knowledge,
                        fromFingerprint: previousRecord.screenFingerprint,
                        toFingerprint: record.screenFingerprint,
                        actionBehavior: previousRecord.actionDescription
                    )
                }
            }
        }

        return knowledge
    }

    // MARK: - Private

    private func mergeScreenKnowledge(
        into knowledge: inout UITestAgentKnowledge,
        record: IterationRecord,
        testSucceeded: Bool
    ) {
        if let existingIndex = knowledge.screenSequence.firstIndex(
            where: { $0.screenFingerprint == record.screenFingerprint }
        ) {
            // Update existing screen knowledge
            var screen = knowledge.screenSequence[existingIndex]
            screen.encounterCount += 1

            // Add description if not already known
            if !screen.descriptions.contains(record.screenDescription) {
                screen.descriptions.append(record.screenDescription)
            }

            // Categorize behavior based on screen change result
            let behavior = stripValues(from: record.actionDescription)
            if let changeSummary = record.screenChangeSummary {
                switch changeSummary.changeType {
                case .screenChanged:
                    if testSucceeded && !screen.successfulBehaviors.contains(behavior) {
                        screen.successfulBehaviors.append(behavior)
                    }
                case .noChange:
                    if !screen.failedBehaviors.contains(behavior) {
                        screen.failedBehaviors.append(behavior)
                    }
                case .keyboardChange:
                    // Keyboard changes are neutral — may be expected (text entry) or noise
                    if testSucceeded && !screen.successfulBehaviors.contains(behavior) {
                        screen.successfulBehaviors.append(behavior)
                    }
                }
            } else if testSucceeded {
                // No screen change data available — trust success
                if !screen.successfulBehaviors.contains(behavior) {
                    screen.successfulBehaviors.append(behavior)
                }
            }

            knowledge.screenSequence[existingIndex] = screen
        } else {
            // New screen type
            let behavior = stripValues(from: record.actionDescription)
            var newScreen = ScreenKnowledge(
                screenFingerprint: record.screenFingerprint,
                descriptions: [record.screenDescription],
                encounterCount: 1,
                keyElements: record.keyElements
            )

            if let changeSummary = record.screenChangeSummary {
                switch changeSummary.changeType {
                case .screenChanged, .keyboardChange:
                    if testSucceeded {
                        newScreen.successfulBehaviors = [behavior]
                    }
                case .noChange:
                    newScreen.failedBehaviors = [behavior]
                }
            } else if testSucceeded {
                newScreen.successfulBehaviors = [behavior]
            }

            knowledge.screenSequence.append(newScreen)
        }
    }

    private func mergeFlowEdge(
        into knowledge: inout UITestAgentKnowledge,
        fromFingerprint: String,
        toFingerprint: String,
        actionBehavior: String
    ) {
        let strippedBehavior = stripValues(from: actionBehavior)
        let edgeExists = knowledge.flowGraph.contains { edge in
            edge.fromFingerprint == fromFingerprint
            && edge.toFingerprint == toFingerprint
            && edge.actionBehavior == strippedBehavior
        }

        if !edgeExists {
            knowledge.flowGraph.append(FlowEdge(
                fromFingerprint: fromFingerprint,
                toFingerprint: toFingerprint,
                actionBehavior: strippedBehavior
            ))
        }
    }

    /// Strip quoted values from action descriptions to make them behavioral.
    /// e.g. "Enter text 'Alberta' into the province field" → "Enter text into the province field"
    private func stripValues(from description: String) -> String {
        // Remove single-quoted values: 'Alberta' → empty
        guard let regex = try? NSRegularExpression(
            pattern: #"'[^']*'\s*"#,
            options: []
        ) else { return description }

        let cleaned = regex.stringByReplacingMatches(
            in: description,
            options: [],
            range: NSRange(description.startIndex..., in: description),
            withTemplate: ""
        )

        // Clean up extra spaces
        return cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
