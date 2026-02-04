import Foundation

/// Formats screen knowledge into a text context string for injection into the LLM prompt.
///
/// When the current screen's fingerprint matches a known screen type, this builder
/// produces a concise behavioral summary. When there is no match, no context is produced.
public struct UITestAgentKnowledgeContextBuilder {

    public init() {}

    /// Build a knowledge context string for the current screen.
    /// - Parameters:
    ///   - screenFingerprint: The fingerprint of the current screen.
    ///   - knowledge: The loaded knowledge for this test.
    /// - Returns: A formatted context string, or `nil` if the screen is unknown.
    public func buildContext(
        for screenFingerprint: String,
        from knowledge: UITestAgentKnowledge
    ) -> String? {
        guard let screen = knowledge.screenSequence.first(
            where: { $0.screenFingerprint == screenFingerprint }
        ) else {
            return nil
        }

        return formatScreenKnowledge(screen, successfulRunCount: knowledge.successfulRunCount)
    }

    // MARK: - Private

    private func formatScreenKnowledge(
        _ screen: ScreenKnowledge,
        successfulRunCount: Int
    ) -> String {
        var lines: [String] = []

        let descriptionsLabel = screen.descriptions.prefix(3).joined(separator: ", ")
        let moreCount = max(0, screen.descriptions.count - 3)
        let descriptionsText = moreCount > 0 ? "\(descriptionsLabel) +\(moreCount) more" : descriptionsLabel
        lines.append("KNOWLEDGE FOR THIS SCREEN TYPE (seen as: \(descriptionsText)):")

        if !screen.successfulBehaviors.isEmpty {
            // Limit to 3 most concise behaviors to reduce prompt size and confusion
            let topBehaviors = selectMostRelevantBehaviors(screen.successfulBehaviors, limit: 3)
            lines.append("Successful behaviors:")
            for behavior in topBehaviors {
                lines.append("- \(behavior)")
            }
            if screen.successfulBehaviors.count > topBehaviors.count {
                lines.append("(\(screen.successfulBehaviors.count - topBehaviors.count) similar variations omitted for clarity)")
            }
        }

        if !screen.failedBehaviors.isEmpty {
            // Limit failed behaviors too
            let topFailed = selectMostRelevantBehaviors(screen.failedBehaviors, limit: 2)
            lines.append("Known issues:")
            for behavior in topFailed {
                lines.append("- \(behavior)")
            }
        } else {
            lines.append("Known issues: (none for this screen type)")
        }

        if !screen.notes.isEmpty {
            lines.append("Notes:")
            for note in screen.notes.prefix(3) {
                lines.append("- \(note)")
            }
        }

        lines.append("Encountered \(screen.encounterCount) time(s) across \(successfulRunCount) successful run(s).")
        lines.append("Adapt to current screen state — specific values and layout may differ from previous runs.")

        return lines.joined(separator: "\n")
    }

    /// Select the most relevant behaviors by preferring shorter, clearer descriptions
    private func selectMostRelevantBehaviors(_ behaviors: [String], limit: Int) -> [String] {
        // Sort by length (shorter is usually clearer) and take the first N
        return behaviors
            .sorted { $0.count < $1.count }
            .prefix(limit)
            .map { $0 }
    }
}
