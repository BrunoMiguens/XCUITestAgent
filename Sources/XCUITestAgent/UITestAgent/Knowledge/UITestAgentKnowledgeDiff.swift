import Foundation

/// Represents differences between prior knowledge and the current run's observations.
///
/// Written to the output directory alongside the knowledge file to help
/// developers review what changed and decide whether to update the committed knowledge.
public struct UITestAgentKnowledgeDiff: Codable {
    /// Screen types that appeared in this run but were not in prior knowledge.
    public var newScreenTypes: [ScreenTypeDiff]

    /// Screen types that were in prior knowledge but did not appear in this run.
    public var missingScreenTypes: [ScreenTypeDiff]

    /// Screen types where behaviors changed (new successful/failed behaviors discovered).
    public var updatedScreenTypes: [ScreenTypeUpdate]

    /// Whether the flow graph changed (new edges or removed edges).
    public var flowChanged: Bool

    public init(
        newScreenTypes: [ScreenTypeDiff] = [],
        missingScreenTypes: [ScreenTypeDiff] = [],
        updatedScreenTypes: [ScreenTypeUpdate] = [],
        flowChanged: Bool = false
    ) {
        self.newScreenTypes = newScreenTypes
        self.missingScreenTypes = missingScreenTypes
        self.updatedScreenTypes = updatedScreenTypes
        self.flowChanged = flowChanged
    }

    /// Whether any differences were detected.
    public var hasDifferences: Bool {
        return !newScreenTypes.isEmpty
            || !missingScreenTypes.isEmpty
            || !updatedScreenTypes.isEmpty
            || flowChanged
    }
}

/// A screen type that is new or missing relative to prior knowledge.
public struct ScreenTypeDiff: Codable {
    public let fingerprint: String
    public let descriptions: [String]
    public let note: String

    public init(fingerprint: String, descriptions: [String], note: String) {
        self.fingerprint = fingerprint
        self.descriptions = descriptions
        self.note = note
    }
}

/// A screen type whose behavioral knowledge was updated.
public struct ScreenTypeUpdate: Codable {
    public let fingerprint: String
    public let descriptions: [String]
    public let change: String

    public init(fingerprint: String, descriptions: [String], change: String) {
        self.fingerprint = fingerprint
        self.descriptions = descriptions
        self.change = change
    }
}

/// Computes the diff between prior knowledge and updated knowledge.
public struct UITestAgentKnowledgeDiffBuilder {

    public init() {}

    /// Compute what changed between prior and updated knowledge.
    /// - Parameters:
    ///   - prior: The knowledge that was loaded at the start (may be `nil`).
    ///   - updated: The knowledge after this run.
    /// - Returns: A diff describing the changes, or `nil` if no prior knowledge existed.
    public func diff(
        prior: UITestAgentKnowledge?,
        updated: UITestAgentKnowledge
    ) -> UITestAgentKnowledgeDiff? {
        guard let prior = prior else { return nil }

        var diff = UITestAgentKnowledgeDiff()

        let priorFingerprints = Set(prior.screenSequence.map(\.screenFingerprint))
        let updatedFingerprints = Set(updated.screenSequence.map(\.screenFingerprint))

        // New screen types
        for fingerprint in updatedFingerprints.subtracting(priorFingerprints) {
            if let screen = updated.screenSequence.first(where: { $0.screenFingerprint == fingerprint }) {
                diff.newScreenTypes.append(ScreenTypeDiff(
                    fingerprint: fingerprint,
                    descriptions: screen.descriptions,
                    note: "New screen type not in prior knowledge"
                ))
            }
        }

        // Missing screen types
        for fingerprint in priorFingerprints.subtracting(updatedFingerprints) {
            if let screen = prior.screenSequence.first(where: { $0.screenFingerprint == fingerprint }) {
                diff.missingScreenTypes.append(ScreenTypeDiff(
                    fingerprint: fingerprint,
                    descriptions: screen.descriptions,
                    note: "Expected but not seen this run"
                ))
            }
        }

        // Updated screen types
        for fingerprint in priorFingerprints.intersection(updatedFingerprints) {
            guard let priorScreen = prior.screenSequence.first(where: { $0.screenFingerprint == fingerprint }),
                  let updatedScreen = updated.screenSequence.first(where: { $0.screenFingerprint == fingerprint }) else {
                continue
            }

            var changes: [String] = []

            let newSuccessful = Set(updatedScreen.successfulBehaviors).subtracting(Set(priorScreen.successfulBehaviors))
            for behavior in newSuccessful {
                changes.append("Added successfulBehavior: '\(behavior)'")
            }

            let newFailed = Set(updatedScreen.failedBehaviors).subtracting(Set(priorScreen.failedBehaviors))
            for behavior in newFailed {
                changes.append("Added failedBehavior: '\(behavior)'")
            }

            let newDescriptions = Set(updatedScreen.descriptions).subtracting(Set(priorScreen.descriptions))
            for desc in newDescriptions {
                changes.append("Added description: '\(desc)'")
            }

            if !changes.isEmpty {
                diff.updatedScreenTypes.append(ScreenTypeUpdate(
                    fingerprint: fingerprint,
                    descriptions: updatedScreen.descriptions,
                    change: changes.joined(separator: "; ")
                ))
            }
        }

        // Flow graph changes
        let priorEdgeKeys = Set(prior.flowGraph.map { edgeKey($0) })
        let updatedEdgeKeys = Set(updated.flowGraph.map { edgeKey($0) })
        diff.flowChanged = priorEdgeKeys != updatedEdgeKeys

        return diff
    }

    private func edgeKey(_ edge: FlowEdge) -> String {
        "\(edge.fromFingerprint)->\(edge.toFingerprint):\(edge.actionBehavior)"
    }
}
