import Foundation

/// File-based knowledge provider using a two-directory architecture.
///
/// - `sourceDirectory`: Read-only. Contains committed knowledge files from the repo.
///   May be `nil` if no prior knowledge exists (first run).
/// - `outputDirectory`: Write-only. Knowledge files are written here after each run.
///   These are CI artifacts that can be reviewed and committed to the repo.
///
/// **CI workflow:**
/// 1. Run tests → knowledge written to `outputDirectory`
/// 2. Archive `outputDirectory` as CI artifact
/// 3. Developer reviews diff files, copies knowledge files to `sourceDirectory`
/// 4. Commit updated knowledge to the repo
///
/// Thread safety: Designed for single-thread access from the agent's synchronous test loop.
public final class UITestAgentFileKnowledgeProvider: UITestAgentKnowledgeProvider {

    /// Configuration for the file-based knowledge provider.
    public struct Configuration {
        /// Directory to read existing knowledge FROM (committed in repo).
        /// `nil` means no prior knowledge is available.
        public let sourceDirectory: URL?

        /// Directory to write updated knowledge TO (CI artifact / temp).
        public let outputDirectory: URL

        /// JSON formatting options for written files.
        public let jsonOutputFormatting: JSONEncoder.OutputFormatting

        public init(
            sourceDirectory: URL? = nil,
            outputDirectory: URL? = nil,
            jsonOutputFormatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys]
        ) {
            self.sourceDirectory = sourceDirectory
            self.outputDirectory = outputDirectory
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("XCUITestAgent_Knowledge", isDirectory: true)
            self.jsonOutputFormatting = jsonOutputFormatting
        }
    }

    public let configuration: Configuration
    private let logger: UITestAgentLogger

    public init(
        configuration: Configuration = Configuration(),
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.configuration = configuration
        self.logger = logger
    }

    // MARK: - UITestAgentKnowledgeProvider

    public func loadKnowledge(for testIdentifier: String) -> UITestAgentKnowledge? {
        guard let sourceDirectory = configuration.sourceDirectory else {
            logger.debug(category: .agentLoop, "Knowledge: No source directory configured, skipping load")
            return nil
        }

        let filename = Self.knowledgeFilename(for: testIdentifier)
        let fileURL = sourceDirectory.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.debug(category: .agentLoop, "Knowledge: No file found at \(fileURL.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let knowledge = try decoder.decode(UITestAgentKnowledge.self, from: data)
            logger.info(
                category: .agentLoop,
                "Knowledge: Loaded for '\(testIdentifier)' — \(knowledge.screenSequence.count) screen type(s), \(knowledge.successfulRunCount) successful run(s)"
            )
            return knowledge
        } catch {
            logger.warning(
                category: .agentLoop,
                "Knowledge: Failed to load from \(fileURL.path): \(error.localizedDescription)"
            )
            return nil
        }
    }

    public func saveKnowledge(_ knowledge: UITestAgentKnowledge, for testIdentifier: String) {
        do {
            try FileManager.default.createDirectory(
                at: configuration.outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning(
                category: .agentLoop,
                "Knowledge: Failed to create output directory: \(error.localizedDescription)"
            )
            return
        }

        let filename = Self.knowledgeFilename(for: testIdentifier)
        let fileURL = configuration.outputDirectory.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = configuration.jsonOutputFormatting
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(knowledge)
            try data.write(to: fileURL, options: .atomic)
            logger.info(
                category: .agentLoop,
                "Knowledge: Saved to \(fileURL.path)"
            )
        } catch {
            logger.warning(
                category: .agentLoop,
                "Knowledge: Failed to write to \(fileURL.path): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    static func knowledgeFilename(for testIdentifier: String) -> String {
        let sanitized = sanitizeForFilename(testIdentifier)
        return "knowledge_\(sanitized).json"
    }

    static func sanitizeForFilename(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = String(
            string.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        )
        return String(sanitized.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
