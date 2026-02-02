import Foundation

/// Compares two view hierarchy snapshots and produces a categorized summary
/// of what changed between them.
///
/// Screen changes are classified as:
/// - **keyboard**: Only keyboard-related elements changed (appear/disappear)
/// - **screenChanged**: Meaningful structural/content changes detected
/// - **noChange**: No significant differences (action may not have worked)
///
/// Noise filtering is configurable via `Configuration.noisePatterns`.
/// Consumers can extend patterns as new noise sources are discovered.
public struct ScreenChangeDetector {

    /// Configurable noise patterns for filtering hierarchy differences.
    public struct Configuration {
        /// Substrings that identify lines as noise to be excluded from comparison.
        /// Lines matching any of these patterns are ignored entirely.
        public var noisePatterns: [String]

        /// Substrings that identify keyboard-related lines.
        /// Changes affecting only these lines are reported as `[KEYBOARD]`.
        public var keyboardPatterns: [String]

        /// Maximum number of changed element details to include in the summary.
        public var maxDetailItems: Int

        public init(
            noisePatterns: [String] = [
                "StatusBar",
                "StatusBarWindow",
                "hasKeyboardFocus",
                "isFocused",
                "isSelected",
                "value: "
            ],
            keyboardPatterns: [String] = [
                "Keyboard",
                "Key:",
                "UIKeyboard",
                "kb-"
            ],
            maxDetailItems: Int = 15
        ) {
            self.noisePatterns = noisePatterns
            self.keyboardPatterns = keyboardPatterns
            self.maxDetailItems = maxDetailItems
        }
    }

    /// Result of comparing two hierarchy snapshots.
    public struct ScreenChangeSummary {
        public enum ChangeType: String {
            case noChange
            case keyboardChange
            case screenChanged
        }

        public let changeType: ChangeType
        public let summary: String
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Compare two hierarchy snapshots and return a categorized summary.
    /// - Parameters:
    ///   - before: View hierarchy captured before the action.
    ///   - after: View hierarchy captured after the action.
    /// - Returns: A categorized summary of what changed.
    public func compare(before: String, after: String) -> ScreenChangeSummary {
        let beforeLines = normalizeLines(before)
        let afterLines = normalizeLines(after)

        let beforeSet = Set(beforeLines)
        let afterSet = Set(afterLines)

        let added = afterSet.subtracting(beforeSet)
        let removed = beforeSet.subtracting(afterSet)

        // No differences at all
        if added.isEmpty && removed.isEmpty {
            return ScreenChangeSummary(
                changeType: .noChange,
                summary: "[NO CHANGE] Screen did not change. Action may not have worked."
            )
        }

        // Categorize the changed lines
        let addedKeyboard = added.filter { isKeyboardLine($0) }
        let removedKeyboard = removed.filter { isKeyboardLine($0) }
        let addedMeaningful = added.subtracting(addedKeyboard)
        let removedMeaningful = removed.subtracting(removedKeyboard)

        // Only keyboard changes
        if addedMeaningful.isEmpty && removedMeaningful.isEmpty {
            let keyboardSummary: String
            if !addedKeyboard.isEmpty && removedKeyboard.isEmpty {
                keyboardSummary = "[KEYBOARD] Keyboard appeared."
            } else if addedKeyboard.isEmpty && !removedKeyboard.isEmpty {
                keyboardSummary = "[KEYBOARD] Keyboard dismissed."
            } else {
                keyboardSummary = "[KEYBOARD] Keyboard state changed."
            }
            return ScreenChangeSummary(
                changeType: .keyboardChange,
                summary: keyboardSummary
            )
        }

        // Meaningful screen changes
        var details: [String] = []

        let addedDescriptions = Array(addedMeaningful.prefix(configuration.maxDetailItems))
        let removedDescriptions = Array(removedMeaningful.prefix(configuration.maxDetailItems - addedDescriptions.count))

        for line in addedDescriptions {
            details.append("+ \(line)")
        }
        for line in removedDescriptions {
            details.append("- \(line)")
        }

        let truncationNote: String
        let totalChanges = addedMeaningful.count + removedMeaningful.count
        if totalChanges > configuration.maxDetailItems {
            truncationNote = " (\(totalChanges - details.count) more changes omitted)"
        } else {
            truncationNote = ""
        }

        let detailBlock = details.joined(separator: "\n")
        return ScreenChangeSummary(
            changeType: .screenChanged,
            summary: "[SCREEN CHANGED]\n\(detailBlock)\(truncationNote)"
        )
    }

    // MARK: - Private

    /// Normalize hierarchy lines: trim, filter empty, strip frames, strip noise.
    private func normalizeLines(_ hierarchy: String) -> [String] {
        return hierarchy
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { stripFrameCoordinates($0) }
            .filter { !isNoiseLine($0) }
    }

    /// Strip frame coordinate values like `{{100.0, 200.0}, {120.0, 60.0}}`
    /// so that focus shifts or minor layout changes don't register as differences.
    private func stripFrameCoordinates(_ line: String) -> String {
        // Match patterns like {{123.0, 456.0}, {78.0, 90.0}}
        guard let regex = try? NSRegularExpression(
            pattern: #"\{\{[\d.]+,\s*[\d.]+\},\s*\{[\d.]+,\s*[\d.]+\}\}"#,
            options: []
        ) else {
            return line
        }
        return regex.stringByReplacingMatches(
            in: line,
            options: [],
            range: NSRange(line.startIndex..., in: line),
            withTemplate: "{frame}"
        )
    }

    /// Check if a line matches any configured noise pattern.
    private func isNoiseLine(_ line: String) -> Bool {
        return configuration.noisePatterns.contains { pattern in
            line.contains(pattern)
        }
    }

    /// Check if a line is keyboard-related.
    private func isKeyboardLine(_ line: String) -> Bool {
        return configuration.keyboardPatterns.contains { pattern in
            line.contains(pattern)
        }
    }
}
