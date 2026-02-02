import Foundation

/// File-based audit provider that writes a JSON audit log per test run.
///
/// Each test run produces one JSON file containing all LLM interactions.
/// Files are named with a timestamp for easy identification on CI.
///
/// Thread safety: This provider is designed to be called from a single
/// thread (the agent's synchronous test loop). It is NOT thread-safe
/// for concurrent access.
public final class UITestAgentFileAuditProvider: UITestAgentAuditProvider {

    /// Configuration for the file audit provider.
    public struct Configuration {
        /// Directory where audit JSON files are written.
        /// Defaults to a `XCUITestAgent_Audits` subdirectory of `NSTemporaryDirectory()`.
        public let outputDirectory: URL

        /// Whether to include screenshot data (base64-encoded JPEG) in the audit.
        /// Defaults to `false` to keep file sizes manageable.
        public let includeScreenshots: Bool

        /// JSON encoding formatting options.
        /// Defaults to `.prettyPrinted` and `.sortedKeys` for human readability and stable diffs.
        public let jsonOutputFormatting: JSONEncoder.OutputFormatting

        public init(
            outputDirectory: URL? = nil,
            includeScreenshots: Bool = false,
            jsonOutputFormatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys]
        ) {
            self.outputDirectory = outputDirectory
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("XCUITestAgent_Audits", isDirectory: true)
            self.includeScreenshots = includeScreenshots
            self.jsonOutputFormatting = jsonOutputFormatting
        }
    }

    /// The full audit report written to disk.
    private struct AuditReport: Codable {
        let testPrompt: String
        let startedAt: Date
        var completedAt: Date?
        var iterations: Int?
        var outcome: UITestAgentAuditOutcome?
        var entries: [UITestAgentAuditEntry]
    }

    private let configuration: Configuration
    private let logger: UITestAgentLogger

    private var currentReport: AuditReport?
    private var currentFileURL: URL?

    public init(
        configuration: Configuration = Configuration(),
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.configuration = configuration
        self.logger = logger
    }

    // MARK: - UITestAgentAuditProvider

    public func testDidStart(testPrompt: String) {
        do {
            try FileManager.default.createDirectory(
                at: configuration.outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning(
                category: .agentLoop,
                "Audit: Failed to create output directory: \(error.localizedDescription)"
            )
        }

        let timestamp = Self.fileTimestamp()
        let sanitizedPrompt = Self.sanitizeForFilename(testPrompt)
        let filename = "audit_\(timestamp)_\(sanitizedPrompt).json"
        currentFileURL = configuration.outputDirectory.appendingPathComponent(filename)

        currentReport = AuditReport(
            testPrompt: testPrompt,
            startedAt: Date(),
            entries: []
        )

        logger.info(
            category: .agentLoop,
            "Audit: Recording to \(currentFileURL?.path ?? "unknown")"
        )
    }

    public func record(_ entry: UITestAgentAuditEntry) {
        let entryToRecord: UITestAgentAuditEntry
        let shouldStripScreenshot = !configuration.includeScreenshots && entry.prompt.screenshotData != nil
        let shouldStripKnowledge = entry.prompt.knowledgeContext != nil
        if shouldStripScreenshot || shouldStripKnowledge {
            entryToRecord = UITestAgentAuditEntry(
                timestamp: entry.timestamp,
                iteration: entry.iteration,
                llmCallIndex: entry.llmCallIndex,
                prompt: LLMClientPrompt(
                    systemPrompt: entry.prompt.systemPrompt,
                    testPrompt: entry.prompt.testPrompt,
                    testContext: entry.prompt.testContext,
                    screenshotData: shouldStripScreenshot ? nil : entry.prompt.screenshotData,
                    debugViewHierarchy: entry.prompt.debugViewHierarchy,
                    knowledgeContext: nil
                ),
                result: entry.result,
                errorDescription: entry.errorDescription,
                duration: entry.duration,
                mappedActionDescription: entry.mappedActionDescription,
                mappedActionCount: entry.mappedActionCount,
                cost: entry.cost
            )
        } else {
            entryToRecord = entry
        }

        currentReport?.entries.append(entryToRecord)
        writeCurrentReport()
    }

    public func testDidEnd(
        testPrompt: String,
        iterations: Int,
        outcome: UITestAgentAuditOutcome
    ) {
        currentReport?.completedAt = Date()
        currentReport?.iterations = iterations
        currentReport?.outcome = outcome
        writeCurrentReport()

        logger.info(
            category: .agentLoop,
            "Audit: Finished recording \(currentReport?.entries.count ?? 0) entries to \(currentFileURL?.path ?? "unknown")"
        )

        currentReport = nil
        currentFileURL = nil
    }

    // MARK: - Private

    private func writeCurrentReport() {
        guard let report = currentReport, let fileURL = currentFileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = configuration.jsonOutputFormatting
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning(
                category: .agentLoop,
                "Audit: Failed to write audit file: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func sanitizeForFilename(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = String(
            string.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        )
        return String(sanitized.prefix(50)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
