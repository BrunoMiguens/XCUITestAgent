import Foundation
import CryptoKit

/// Generates a structural fingerprint from a view hierarchy string.
///
/// The fingerprint is a SHA-256 hash of the normalized structural elements
/// (element types + indentation depth), ignoring text content, frame values,
/// and attributes. Two screens with the same UI structure (e.g. a "First Name"
/// and "Last Name" text entry screen) produce the same fingerprint.
public struct ScreenFingerprint {

    public init() {}

    /// Generate a fingerprint from a view hierarchy string.
    /// - Parameter hierarchy: The cleaned debug view hierarchy (as from `debugDescription`).
    /// - Returns: A hex-encoded SHA-256 hash of the normalized structure.
    public func fingerprint(from hierarchy: String) -> String {
        let structuralLines = extractStructuralLines(from: hierarchy)
        let normalized = structuralLines.sorted().joined(separator: "\n")
        return sha256(normalized)
    }

    /// Extract the key structural element types from the hierarchy for human-readable reference.
    /// - Parameter hierarchy: The cleaned debug view hierarchy.
    /// - Returns: Deduplicated list of element type names found (e.g. ["NavigationBar", "TextField", "Button"]).
    public func keyElements(from hierarchy: String) -> [String] {
        let lines = hierarchy.components(separatedBy: .newlines)
        var elementTypes: [String] = []
        var seen = Set<String>()

        for line in lines {
            if let elementType = extractElementType(from: line), !seen.contains(elementType) {
                seen.insert(elementType)
                elementTypes.append(elementType)
            }
        }

        return elementTypes
    }

    /// Extract a human-readable screen description from the hierarchy.
    ///
    /// Looks for NavigationBar title first, then falls back to the first StaticText.
    /// - Parameter hierarchy: The cleaned debug view hierarchy.
    /// - Returns: A description like "First Name" or "Unknown Screen".
    public func screenDescription(from hierarchy: String) -> String {
        let lines = hierarchy.components(separatedBy: .newlines)

        // Look for NavigationBar title
        var inNavigationBar = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("NavigationBar") {
                inNavigationBar = true
                continue
            }
            if inNavigationBar {
                if let title = extractTextValue(from: trimmed) {
                    return title
                }
                // If we hit a non-indented line or a different element type, exit nav bar
                if !trimmed.isEmpty && indentationDepth(of: line) <= 1 {
                    inNavigationBar = false
                }
            }
        }

        // Fallback: first StaticText value
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("StaticText") {
                if let text = extractTextValue(from: trimmed) {
                    return text
                }
            }
        }

        return "Unknown Screen"
    }

    // MARK: - Private

    /// Extract structural lines: "depth:ElementType" — no text, no frames, no attributes.
    private func extractStructuralLines(from hierarchy: String) -> [String] {
        let lines = hierarchy.components(separatedBy: .newlines)
        var structural: [String] = []

        for line in lines {
            let depth = indentationDepth(of: line)
            if let elementType = extractElementType(from: line) {
                structural.append("\(depth):\(elementType)")
            }
        }

        return structural
    }

    /// Calculate indentation depth (number of leading spaces / 2, as XCUITest uses 2-space indent).
    private func indentationDepth(of line: String) -> Int {
        let stripped = line.drop(while: { $0 == " " })
        let spaces = line.count - stripped.count
        return spaces / 2
    }

    /// Extract the element type name from a hierarchy line.
    ///
    /// Lines typically look like: `    StaticText, label: 'Hello'`
    /// or `  Application, ...`
    private func extractElementType(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Element type is the first word before a comma, space, or end of line
        // Common patterns: "Button", "StaticText, label: 'X'", "TextField, value: Y"
        let firstComponent: String
        if let commaIndex = trimmed.firstIndex(of: ",") {
            firstComponent = String(trimmed[trimmed.startIndex..<commaIndex])
        } else {
            firstComponent = trimmed
        }

        let candidate = firstComponent.trimmingCharacters(in: .whitespaces)

        // Filter out lines that don't look like element types
        // Element types are typically CamelCase identifiers
        guard !candidate.isEmpty,
              candidate.first?.isUppercase == true || candidate.first?.isLetter == true,
              !candidate.contains("{"),
              !candidate.contains(":"),
              !candidate.contains("=") else {
            return nil
        }

        return candidate
    }

    /// Extract a text value from a hierarchy line (e.g. `label: 'Hello'` or `value: 'World'`).
    private func extractTextValue(from line: String) -> String? {
        // Match patterns like: label: 'Some Text' or value: 'Some Text'
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:label|value):\s*'([^']+)'"#,
            options: []
        ) else { return nil }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let text = String(line[captureRange])
        return text.isEmpty ? nil : text
    }

    /// Compute SHA-256 hex string.
    private func sha256(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
