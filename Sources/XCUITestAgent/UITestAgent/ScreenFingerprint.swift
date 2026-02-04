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

    /// Compute SHA-256 hex string.
    private func sha256(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
