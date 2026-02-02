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

        let descriptionsLabel = screen.descriptions.joined(separator: ", ")
        lines.append("KNOWLEDGE FOR THIS SCREEN TYPE (seen as: \(descriptionsLabel)):")

        if !screen.successfulBehaviors.isEmpty {
            lines.append("Successful behaviors:")
            for behavior in screen.successfulBehaviors {
                lines.append("- \(behavior)")
            }
        }

        if !screen.failedBehaviors.isEmpty {
            lines.append("Known issues:")
            for behavior in screen.failedBehaviors {
                lines.append("- \(behavior)")
            }
        } else {
            lines.append("Known issues: (none for this screen type)")
        }

        if !screen.notes.isEmpty {
            lines.append("Notes:")
            for note in screen.notes {
                lines.append("- \(note)")
            }
        }

        lines.append("Encountered \(screen.encounterCount) time(s) across \(successfulRunCount) successful run(s).")
        lines.append("Adapt to current screen state — specific values and layout may differ from previous runs.")

        return lines.joined(separator: "\n")
    }
}
