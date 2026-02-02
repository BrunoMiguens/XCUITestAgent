import Foundation

open class UITestAgent {
    private let retryLimit: Int = 3

    public let client: LLMClient
    public let responseMapper: LLMClientResponseMapper

    public let promptProvider: UITestAgentPromptProvider
    public let actionPerformer: UITestAgentActionPerformer
    public let logger: UITestAgentLogger
    public let auditProvider: UITestAgentAuditProvider?
    public let knowledgeProvider: UITestAgentKnowledgeProvider?

    private var actionHistory: [ActionSequence] = []
    private var retries = 0
    private var llmCallIndex = 0
    private var testOutcome: UITestAgentAuditOutcome?

    private let costCalculator = LLMClientCostCalculator()
    private var costs: [LLMClientCost] = []
    private let screenChangeDetector = ScreenChangeDetector()
    private let screenFingerprinter = ScreenFingerprint()
    private let knowledgeContextBuilder = UITestAgentKnowledgeContextBuilder()
    private let knowledgeDiffBuilder = UITestAgentKnowledgeDiffBuilder()
    private let knowledgeBuilder = UITestAgentKnowledgeBuilder()
    private var iterationRecords: [UITestAgentKnowledgeBuilder.IterationRecord] = []
    private var loadedKnowledge: UITestAgentKnowledge?
    private var currentTestIdentifier: String?

    public init(
        client: LLMClient,
        responseMapper: LLMClientResponseMapper,
        promptProvider: UITestAgentPromptProvider,
        actionPerformer: UITestAgentActionPerformer,
        logger: UITestAgentLogger = UITestAgentDefaultLogger(),
        auditProvider: UITestAgentAuditProvider? = nil,
        knowledgeProvider: UITestAgentKnowledgeProvider? = nil
    ) {
        self.client = client
        self.responseMapper = responseMapper
        self.promptProvider = promptProvider
        self.actionPerformer = actionPerformer
        self.logger = logger
        self.auditProvider = auditProvider
        self.knowledgeProvider = knowledgeProvider
    }

    public func runTest(_ testPrompt: String, function: String = #function, file: String = #file) {
        resetSession()

        // derive test identifier and load prior knowledge
        let testIdentifier = Self.makeTestIdentifier(file: file, function: function)
        currentTestIdentifier = testIdentifier
        loadedKnowledge = knowledgeProvider?.loadKnowledge(for: testIdentifier)
        if let knowledge = loadedKnowledge {
            logger.info(
                category: .agentLoop,
                "Knowledge loaded: \(knowledge.screenSequence.count) screen type(s), \(knowledge.successfulRunCount) successful run(s)"
            )
        }

        auditProvider?.testDidStart(testPrompt: testPrompt)
        logger.logSeparator(.heavy, "Starting test: \(testPrompt)")

        // main test run loop
        var shouldContinue = true
        var iteration = 0
        while shouldContinue {
            iteration += 1
            logger.logSeparator(.light, "Iteration \(iteration)")
            shouldContinue = performNextActionSequence(testPrompt: testPrompt, iteration: iteration)
        }

        let resultSummary: String
        if !costs.isEmpty {
            let totalCost = costs.reduce(0.0) { $0 + $1.totalCost }
            let formattedCost = String(format: "$%.6f", totalCost)
            resultSummary = "Completed after \(iteration) iteration(s) | Cost: \(formattedCost) across \(costs.count) LLM call(s)"
            actionPerformer.reportTotalCost(totalCost, callCount: costs.count)
        } else {
            resultSummary = "Completed after \(iteration) iteration(s)"
        }
        logger.logSeparator(.heavy, resultSummary)

        // save knowledge from this run
        let testSucceeded: Bool
        if case .success = testOutcome {
            testSucceeded = true
        } else {
            testSucceeded = false
        }
        saveKnowledge(
            testIdentifier: testIdentifier,
            testSucceeded: testSucceeded
        )

        auditProvider?.testDidEnd(
            testPrompt: testPrompt,
            iterations: iteration,
            outcome: testOutcome ?? .failure
        )
    }

    private func performNextActionSequence(testPrompt: String, iteration: Int) -> Bool {
        // 1. capture screen state before LLM call
        let beforeScreenState = promptProvider.captureScreenState()

        // 2. fingerprint current screen and look up knowledge
        var currentFingerprint: String?
        var knowledgeContext: String?
        if let hierarchy = beforeScreenState {
            let fingerprint = screenFingerprinter.fingerprint(from: hierarchy)
            currentFingerprint = fingerprint
            if let knowledge = loadedKnowledge {
                knowledgeContext = knowledgeContextBuilder.buildContext(
                    for: fingerprint,
                    from: knowledge
                )
                if knowledgeContext != nil {
                    logger.debug(category: .agentLoop, "Knowledge context injected for screen fingerprint: \(String(fingerprint.prefix(12)))...")
                }
            }
        }

        // 3. determine next sequence (with knowledge context injected)
        let nextActionSequence = nextAction(
            testPrompt,
            actionHistory: actionHistory,
            iteration: iteration,
            knowledgeContext: knowledgeContext
        )
        guard let lastAction = nextActionSequence.actions.last else {
            logger.error(category: .agentLoop, "Unable to determine next action, failing test")
            actionPerformer.perform(ActionSequence(
                description: "Unable to determine next action.",
                actions: [
                    .failure
                ]
            ))
            testOutcome = .failure
            return false
        }

        // 4. perform action sequence
        logger.info(category: .agentLoop, "Performing: \(nextActionSequence.description)")
        logger.debug(category: .agentLoop, "Actions in sequence: \(nextActionSequence.actions.count)")
        actionPerformer.perform(nextActionSequence)
        switch lastAction {
        case .success:
            logger.info(category: .agentLoop, "Test PASSED: \(nextActionSequence.description)")
            testOutcome = .success
            // record final iteration for knowledge (success terminal)
            recordIterationForKnowledge(
                hierarchy: beforeScreenState,
                fingerprint: currentFingerprint,
                actionDescription: nextActionSequence.description,
                changeSummary: nil
            )
            return false
        case .failure:
            logger.error(category: .agentLoop, "Test FAILED: \(nextActionSequence.description)")
            testOutcome = .failure
            // record final iteration for knowledge (failure terminal)
            recordIterationForKnowledge(
                hierarchy: beforeScreenState,
                fingerprint: currentFingerprint,
                actionDescription: nextActionSequence.description,
                changeSummary: nil
            )
            return false
        default:
            // 5. capture screen state after action + delay
            let afterScreenState = promptProvider.captureScreenState()

            // 6. compare and enrich action description with screen change feedback
            var changeSummary: ScreenChangeDetector.ScreenChangeSummary?
            let enrichedSequence: ActionSequence
            if let before = beforeScreenState, let after = afterScreenState {
                let summary = screenChangeDetector.compare(before: before, after: after)
                changeSummary = summary
                logger.debug(category: .agentLoop, "Screen change: \(summary.changeType.rawValue)")
                enrichedSequence = ActionSequence(
                    description: "\(nextActionSequence.description)\n\(summary.summary)",
                    actions: nextActionSequence.actions,
                    delayUntilNextSequence: nextActionSequence.delayUntilNextSequence
                )
            } else {
                enrichedSequence = nextActionSequence
            }

            // 7. record iteration for knowledge building
            recordIterationForKnowledge(
                hierarchy: beforeScreenState,
                fingerprint: currentFingerprint,
                actionDescription: nextActionSequence.description,
                changeSummary: changeSummary
            )

            actionHistory.append(enrichedSequence)
            logger.debug(category: .agentLoop, "Action history now contains \(actionHistory.count) sequence(s)")
            return true
        }
    }

    private func resetSession() {
        logger.debug(category: .agentLoop, "Resetting session state")
        actionHistory = []
        retries = 0
        costs = []
        llmCallIndex = 0
        testOutcome = nil
        iterationRecords = []
        loadedKnowledge = nil
        currentTestIdentifier = nil
    }

    private func nextAction(
        _ testPrompt: String,
        actionHistory: [ActionSequence],
        iteration: Int,
        knowledgeContext: String? = nil
    ) -> ActionSequence {
        var prompt: LLMClientPrompt?
        var callStart: Date?

        do {
            logger.debug(category: .agentLoop, "Building prompt for LLM")
            let basePrompt = try promptProvider.makePrompt(
                testPrompt,
                actionHistory: actionHistory
            )

            // inject knowledge context if available
            let builtPrompt: LLMClientPrompt
            if let knowledgeContext = knowledgeContext {
                builtPrompt = LLMClientPrompt(
                    systemPrompt: basePrompt.systemPrompt,
                    testPrompt: basePrompt.testPrompt,
                    testContext: basePrompt.testContext,
                    screenshotData: basePrompt.screenshotData,
                    debugViewHierarchy: basePrompt.debugViewHierarchy,
                    knowledgeContext: knowledgeContext
                )
            } else {
                builtPrompt = basePrompt
            }
            prompt = builtPrompt

            logger.debug(category: .agentLoop, "Sending prompt to LLM client")
            llmCallIndex += 1
            callStart = Date()
            let result = try performPromptSync(prompt: builtPrompt)
            let duration = Date().timeIntervalSince(callStart!)

            var cost: LLMClientCost?
            if let usage = result.usage {
                logger.debug(category: .agentLoop, "Token usage — prompt: \(usage.promptTokens), completion: \(usage.completionTokens), total: \(usage.totalTokens), model: \(usage.model)")
                let calculatedCost = costCalculator.calculate(for: usage)
                cost = calculatedCost
                costs.append(calculatedCost)
                let formattedCost = String(format: "$%.6f", calculatedCost.totalCost)
                logger.info(category: .agentLoop, "LLM call cost: \(formattedCost) (\(calculatedCost.model), \(calculatedCost.usage.promptTokens) prompt + \(calculatedCost.usage.completionTokens) completion tokens)")
                actionPerformer.reportCost(calculatedCost)
            } else {
                logger.debug(category: .agentLoop, "No token usage data returned by LLM client")
            }

            logger.debug(category: .agentLoop, "Mapping LLM response to action sequence")
            let action = try responseMapper.map(response: result.content)
            retries = 0

            recordAuditEntry(
                iteration: iteration,
                prompt: builtPrompt,
                result: result,
                errorDescription: nil,
                duration: duration,
                mappedActionDescription: action.description,
                mappedActionCount: action.actions.count,
                cost: cost
            )

            return action
        } catch let error {
            let duration = callStart.map { Date().timeIntervalSince($0) } ?? 0

            if let prompt = prompt {
                recordAuditEntry(
                    iteration: iteration,
                    prompt: prompt,
                    result: nil,
                    errorDescription: error.localizedDescription,
                    duration: duration,
                    mappedActionDescription: nil,
                    mappedActionCount: nil,
                    cost: nil
                )
            }

            retries += 1
            logger.warning(category: .agentLoop, "Error on attempt \(retries)/\(retryLimit): \(error.localizedDescription)")
            guard retries < retryLimit else {
                logger.error(category: .agentLoop, "Retry limit (\(retryLimit)) exceeded. Last error: \(error.localizedDescription)")
                return ActionSequence(
                    description: error.localizedDescription,
                    actions: [
                        .failure
                    ]
                )
            }
            logger.info(category: .agentLoop, "Retrying (attempt \(retries + 1)/\(retryLimit))...")
            return nextAction(
                testPrompt,
                actionHistory: actionHistory,
                iteration: iteration
            )
        }
    }

    private func recordAuditEntry(
        iteration: Int,
        prompt: LLMClientPrompt,
        result: LLMClientResult?,
        errorDescription: String?,
        duration: TimeInterval,
        mappedActionDescription: String?,
        mappedActionCount: Int?,
        cost: LLMClientCost?
    ) {
        guard let auditProvider else { return }

        let entry = UITestAgentAuditEntry(
            timestamp: Date(),
            iteration: iteration,
            llmCallIndex: llmCallIndex,
            prompt: prompt,
            result: result,
            errorDescription: errorDescription,
            duration: duration,
            mappedActionDescription: mappedActionDescription,
            mappedActionCount: mappedActionCount,
            cost: cost
        )

        auditProvider.record(entry)
    }

    private func performPromptSync(prompt: LLMClientPrompt) throws -> LLMClientResult {
        logger.debug(category: .agentLoop, "Dispatching async LLM call via semaphore bridge")
        let responseSemaphore = DispatchSemaphore(value: 0)
        var result: LLMClientResult?
        var responseError: Error?
        Task {
            do {
                result = try await client.prompt(prompt)
            } catch let error {
                responseError = error
            }
            responseSemaphore.signal()
        }
        responseSemaphore.wait()
        guard let result else {
            logger.error(category: .agentLoop, "LLM call failed: \(responseError?.localizedDescription ?? "unknown error")")
            throw responseError!
        }
        logger.debug(category: .agentLoop, "LLM call completed, response length: \(result.content.count) characters")
        return result
    }

    // MARK: - Knowledge helpers

    private func recordIterationForKnowledge(
        hierarchy: String?,
        fingerprint: String?,
        actionDescription: String,
        changeSummary: ScreenChangeDetector.ScreenChangeSummary?
    ) {
        guard knowledgeProvider != nil, let hierarchy = hierarchy, let fingerprint = fingerprint else { return }

        let record = UITestAgentKnowledgeBuilder.IterationRecord(
            screenHierarchy: hierarchy,
            screenFingerprint: fingerprint,
            screenDescription: screenFingerprinter.screenDescription(from: hierarchy),
            keyElements: screenFingerprinter.keyElements(from: hierarchy),
            actionDescription: actionDescription,
            screenChangeSummary: changeSummary
        )
        iterationRecords.append(record)
    }

    private func saveKnowledge(testIdentifier: String, testSucceeded: Bool) {
        guard let knowledgeProvider = knowledgeProvider else { return }
        guard !iterationRecords.isEmpty else {
            logger.debug(category: .agentLoop, "Knowledge: No iteration records to save")
            return
        }

        let updatedKnowledge = knowledgeBuilder.build(
            existing: loadedKnowledge,
            testIdentifier: testIdentifier,
            records: iterationRecords,
            testSucceeded: testSucceeded
        )

        knowledgeProvider.saveKnowledge(updatedKnowledge, for: testIdentifier)
        logger.info(
            category: .agentLoop,
            "Knowledge: Saved \(updatedKnowledge.screenSequence.count) screen type(s), \(updatedKnowledge.flowGraph.count) flow edge(s)"
        )

        // Write diff file if prior knowledge existed
        if let diff = knowledgeDiffBuilder.diff(prior: loadedKnowledge, updated: updatedKnowledge) {
            saveDiff(diff, testIdentifier: testIdentifier)
        }

        // Write manifest
        saveManifest(
            testIdentifier: testIdentifier,
            outcome: testSucceeded ? "success" : "failure",
            iterations: iterationRecords.count,
            hadPriorKnowledge: loadedKnowledge != nil,
            screenTypesEncountered: updatedKnowledge.screenSequence.count,
            newScreenTypes: diff(prior: loadedKnowledge, updated: updatedKnowledge)
        )
    }

    private func diff(prior: UITestAgentKnowledge?, updated: UITestAgentKnowledge) -> Int {
        guard let prior = prior else { return updated.screenSequence.count }
        let priorFingerprints = Set(prior.screenSequence.map(\.screenFingerprint))
        let updatedFingerprints = Set(updated.screenSequence.map(\.screenFingerprint))
        return updatedFingerprints.subtracting(priorFingerprints).count
    }

    private func saveDiff(_ diff: UITestAgentKnowledgeDiff, testIdentifier: String) {
        guard diff.hasDifferences else { return }
        guard let fileProvider = knowledgeProvider as? UITestAgentFileKnowledgeProvider else { return }

        let filename = "knowledge_diff_\(UITestAgentFileKnowledgeProvider.sanitizeForFilename(testIdentifier)).json"
        let fileURL = fileProvider.configuration.outputDirectory.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(diff)
            try data.write(to: fileURL, options: .atomic)
            logger.info(category: .agentLoop, "Knowledge: Diff written to \(fileURL.path)")
        } catch {
            logger.warning(category: .agentLoop, "Knowledge: Failed to write diff: \(error.localizedDescription)")
        }
    }

    private func saveManifest(
        testIdentifier: String,
        outcome: String,
        iterations: Int,
        hadPriorKnowledge: Bool,
        screenTypesEncountered: Int,
        newScreenTypes: Int
    ) {
        guard let fileProvider = knowledgeProvider as? UITestAgentFileKnowledgeProvider else { return }

        let manifest: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "tests": [[
                "testIdentifier": testIdentifier,
                "outcome": outcome,
                "iterations": iterations,
                "hadPriorKnowledge": hadPriorKnowledge,
                "screenTypesEncountered": screenTypesEncountered,
                "newScreenTypes": newScreenTypes,
                "knowledgeFile": UITestAgentFileKnowledgeProvider.knowledgeFilename(for: testIdentifier)
            ]]
        ]

        let fileURL = fileProvider.configuration.outputDirectory.appendingPathComponent("knowledge_manifest.json")

        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            logger.info(category: .agentLoop, "Knowledge: Manifest written to \(fileURL.path)")
        } catch {
            logger.warning(category: .agentLoop, "Knowledge: Failed to write manifest: \(error.localizedDescription)")
        }
    }

    static func makeTestIdentifier(file: String, function: String) -> String {
        let fileName = (file as NSString).lastPathComponent
            .replacingOccurrences(of: ".swift", with: "")
        let functionName = function
            .replacingOccurrences(of: "()", with: "")
        return "\(fileName)_\(functionName)"
    }
}
