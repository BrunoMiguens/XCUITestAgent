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
                    if testSucceeded && !containsSimilarBehavior(screen.successfulBehaviors, behavior) {
                        screen.successfulBehaviors.append(behavior)
                    }
                case .noChange:
                    if !containsSimilarBehavior(screen.failedBehaviors, behavior) {
                        screen.failedBehaviors.append(behavior)
                    }
                case .keyboardChange:
                    // Keyboard changes are neutral — may be expected (text entry) or noise
                    if testSucceeded && !containsSimilarBehavior(screen.successfulBehaviors, behavior) {
                        screen.successfulBehaviors.append(behavior)
                    }
                }
            } else if testSucceeded {
                // No screen change data available — trust success
                if !containsSimilarBehavior(screen.successfulBehaviors, behavior) {
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
                    if testSucceeded && !containsSimilarBehavior(newScreen.successfulBehaviors, behavior) {
                        newScreen.successfulBehaviors.append(behavior)
                    }
                case .noChange:
                    if !containsSimilarBehavior(newScreen.failedBehaviors, behavior) {
                        newScreen.failedBehaviors.append(behavior)
                    }
                }
            } else if testSucceeded && !containsSimilarBehavior(newScreen.successfulBehaviors, behavior) {
                newScreen.successfulBehaviors.append(behavior)
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

        // Check for exact match
        let exactMatch = knowledge.flowGraph.firstIndex { edge in
            edge.fromFingerprint == fromFingerprint
            && edge.toFingerprint == toFingerprint
            && edge.actionBehavior == strippedBehavior
        }

        if exactMatch != nil {
            return // Exact duplicate, skip
        }

        // Check for similar behavior on same transition (semantic duplicate)
        let similarEdge = knowledge.flowGraph.firstIndex { edge in
            edge.fromFingerprint == fromFingerprint
            && edge.toFingerprint == toFingerprint
            && areSimilarBehaviors(strippedBehavior, edge.actionBehavior)
        }

        if let index = similarEdge {
            // Replace with shorter, cleaner description
            if strippedBehavior.count < knowledge.flowGraph[index].actionBehavior.count {
                knowledge.flowGraph[index] = FlowEdge(
                    fromFingerprint: fromFingerprint,
                    toFingerprint: toFingerprint,
                    actionBehavior: strippedBehavior
                )
            }
        } else {
            // New unique edge
            knowledge.flowGraph.append(FlowEdge(
                fromFingerprint: fromFingerprint,
                toFingerprint: toFingerprint,
                actionBehavior: strippedBehavior
            ))
        }
    }

    /// Check if two behaviors are semantically similar using simple similarity threshold
    private func areSimilarBehaviors(_ a: String, _ b: String) -> Bool {
        // If one string contains most of the other's words, they're likely similar
        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))

        let intersection = wordsA.intersection(wordsB).count
        let minCount = min(wordsA.count, wordsB.count)

        // If 70% or more words overlap, consider them similar
        return minCount > 0 && Double(intersection) / Double(minCount) >= 0.7
    }

    /// Check if a behavior list already contains a similar behavior
    private func containsSimilarBehavior(_ behaviors: [String], _ behavior: String) -> Bool {
        return behaviors.contains { existing in
            existing == behavior || areSimilarBehaviors(existing, behavior)
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

        var cleaned = regex.stringByReplacingMatches(
            in: description,
            options: [],
            range: NSRange(description.startIndex..., in: description),
            withTemplate: ""
        )

        // Normalize common variations to create more consistent behaviors
        cleaned = normalizeAction(cleaned)

        // Clean up extra spaces
        return cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Normalize action descriptions to reduce semantic duplicates
    private func normalizeAction(_ text: String) -> String {
        var normalized = text.lowercased()

        // Normalize button/tap variations
        normalized = normalized.replacingOccurrences(of: "tap the button", with: "tap button")
        normalized = normalized.replacingOccurrences(of: "click the button", with: "tap button")
        normalized = normalized.replacingOccurrences(of: "press the button", with: "tap button")
        normalized = normalized.replacingOccurrences(of: "select the button", with: "tap button")

        // Normalize field/input variations
        normalized = normalized.replacingOccurrences(of: "text field", with: "field")
        normalized = normalized.replacingOccurrences(of: "input field", with: "field")
        normalized = normalized.replacingOccurrences(of: "enter text into", with: "enter")
        normalized = normalized.replacingOccurrences(of: "type text into", with: "enter")
        normalized = normalized.replacingOccurrences(of: "input text into", with: "enter")

        // Remove common filler phrases that add no semantic value
        let fillerPhrases = [
            "as required by the onboarding instructions",
            "as required",
            "to proceed",
            "and then",
            "in order to",
            "and wait for",
        ]
        for filler in fillerPhrases {
            normalized = normalized.replacingOccurrences(of: filler, with: "")
        }

        // Clean up articles and determiners for consistency
        normalized = normalized.replacingOccurrences(of: " the ", with: " ")
        normalized = normalized.replacingOccurrences(of: " a ", with: " ")
        normalized = normalized.replacingOccurrences(of: " an ", with: " ")

        // Trim and collapse multiple spaces
        normalized = normalized.trimmingCharacters(in: .whitespaces)
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }

        return normalized
    }
}
