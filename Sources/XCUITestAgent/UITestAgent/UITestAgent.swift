import Foundation

open class UITestAgent {
    private let configuration: UITestAgentConfiguration

    public let client: LLMClient
    public let responseMapper: LLMClientResponseMapper

    public let promptProvider: UITestAgentPromptProvider
    public let actionPerformer: UITestAgentActionPerformer
    public let logger: UITestAgentLogger
    public let auditProvider: UITestAgentAuditProvider?

    private var actionHistory: [ActionSequence] = []
    private var retries = 0
    private var llmCallIndex = 0
    private var testOutcome: UITestAgentAuditOutcome?
    private var pendingTerminalSequence: ActionSequence?

    private let costCalculator = LLMClientCostCalculator()
    private var costs: [LLMClientCost] = []
    private let screenFingerprinter = ScreenFingerprint()
    private var recentScreenFingerprints: [String] = []
    private var lastScreenFingerprint: String?
    private var currentScreenAttemptCount: Int = 0

    public init(
        client: LLMClient,
        responseMapper: LLMClientResponseMapper,
        promptProvider: UITestAgentPromptProvider,
        actionPerformer: UITestAgentActionPerformer,
        logger: UITestAgentLogger = UITestAgentDefaultLogger(),
        auditProvider: UITestAgentAuditProvider? = nil,
        configuration: UITestAgentConfiguration = UITestAgentConfiguration()
    ) {
        self.client = client
        self.responseMapper = responseMapper
        self.promptProvider = promptProvider
        self.actionPerformer = actionPerformer
        self.logger = logger
        self.auditProvider = auditProvider
        self.configuration = configuration
    }

    public func runTest(_ testPrompt: String, function: String = #function, file: String = #file) {
        resetSession()

        auditProvider?.testDidStart(testPrompt: testPrompt)
        logger.logSeparator(.heavy, "Starting test: \(testPrompt)")

        // main test run loop
        var shouldContinue = true
        var iteration = 0
        while shouldContinue {
            iteration += 1

            if iteration > configuration.maxIterations {
                logger.error(
                    category: .agentLoop,
                    "Maximum iteration limit (\(configuration.maxIterations)) reached. Failing test to prevent unbounded execution."
                )
                pendingTerminalSequence = ActionSequence(
                    description: "Maximum iteration limit (\(configuration.maxIterations)) reached.",
                    actions: [.failure]
                )
                testOutcome = .failure
                break
            }

            logger.logSeparator(.light, "Iteration \(iteration)/\(configuration.maxIterations)")
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

        auditProvider?.testDidEnd(
            testPrompt: testPrompt,
            iterations: iteration,
            outcome: testOutcome ?? .failure
        )

        // Perform terminal action LAST — XCTFail aborts the test when
        // continueAfterFailure is false, so knowledge and audit must be saved first.
        if let terminalSequence = pendingTerminalSequence {
            actionPerformer.perform(terminalSequence)
        }
    }

    private func performNextActionSequence(testPrompt: String, iteration: Int) -> Bool {
        // 1. capture screen state before LLM call
        let beforeScreenState = promptProvider.captureScreenState()

        // 2. fingerprint current screen and look up knowledge
        var currentFingerprint: String?
        if let hierarchy = beforeScreenState {
            let fingerprint = screenFingerprinter.fingerprint(from: hierarchy)
            currentFingerprint = fingerprint

            if lastScreenFingerprint == fingerprint {
                currentScreenAttemptCount += 1
            } else {
                currentScreenAttemptCount = 1
                lastScreenFingerprint = fingerprint
            }

            if currentScreenAttemptCount > configuration.maxAttemptsPerScreen {
                logger.error(
                    category: .agentLoop,
                    "Max attempts per screen (\(configuration.maxAttemptsPerScreen)) exceeded for current screen. Failing to avoid being stuck."
                )
                pendingTerminalSequence = ActionSequence(
                    description: "Maximum attempts per screen (\(configuration.maxAttemptsPerScreen)) reached.",
                    actions: [.failure]
                )
                testOutcome = .failure
                return false
            }

            // Track fingerprint for loop detection (window scales with per-screen attempt budget).
            recentScreenFingerprints.append(fingerprint)
            let loopWindowSize = configuration.resolvedLoopWindowSize()
            if recentScreenFingerprints.count > loopWindowSize {
                recentScreenFingerprints.removeFirst(recentScreenFingerprints.count - loopWindowSize)
            }

            // Detect loops: if we've seen the same screen 3+ times in last 6 iterations
            if detectLoop(fingerprint: fingerprint) {
                logger.error(category: .agentLoop, "Loop detected: same screen visited multiple times without progress")
                pendingTerminalSequence = ActionSequence(
                    description: "Loop detected: agent is stuck revisiting the same screens without making progress.",
                    actions: [.failure]
                )
                testOutcome = .failure
                return false
            }

        }

        // 3. determine next sequence
        let nextActionSequence = nextAction(
            testPrompt,
            actionHistory: actionHistory,
            iteration: iteration
        )
        guard let lastAction = nextActionSequence.actions.last else {
            logger.error(category: .agentLoop, "Unable to determine next action, failing test")
            pendingTerminalSequence = ActionSequence(
                description: "Unable to determine next action.",
                actions: [.failure]
            )
            testOutcome = .failure
            return false
        }

        // 4. perform action sequence
        logger.info(category: .agentLoop, "Performing: \(nextActionSequence.description)")
        logger.debug(category: .agentLoop, "Actions in sequence: \(nextActionSequence.actions.count)")

        switch lastAction {
        case .success:
            // Perform non-terminal actions in the sequence (if any)
            let nonTerminalActions = nextActionSequence.actions.dropLast()
            if !nonTerminalActions.isEmpty {
                actionPerformer.perform(ActionSequence(
                    description: nextActionSequence.description,
                    actions: Array(nonTerminalActions)
                ))
            }
            logger.info(category: .agentLoop, "Test PASSED: \(nextActionSequence.description)")
            testOutcome = .success
            pendingTerminalSequence = nextActionSequence
            return false
        case .failure:
            // Perform non-terminal actions in the sequence (if any)
            let nonTerminalActions = nextActionSequence.actions.dropLast()
            if !nonTerminalActions.isEmpty {
                actionPerformer.perform(ActionSequence(
                    description: nextActionSequence.description,
                    actions: Array(nonTerminalActions)
                ))
            }
            logger.error(category: .agentLoop, "Test FAILED: \(nextActionSequence.description)")
            testOutcome = .failure
            pendingTerminalSequence = nextActionSequence
            return false
        default:
            actionPerformer.perform(nextActionSequence)
            actionHistory.append(nextActionSequence)
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
        pendingTerminalSequence = nil
        recentScreenFingerprints = []
        lastScreenFingerprint = nil
        currentScreenAttemptCount = 0
    }

    private func nextAction(
        _ testPrompt: String,
        actionHistory: [ActionSequence],
        iteration: Int
    ) -> ActionSequence {
        var prompt: LLMClientPrompt?
        var callStart: Date?

        do {
            logger.debug(category: .agentLoop, "Building prompt for LLM")
            let basePrompt = try promptProvider.makePrompt(
                testPrompt,
                actionHistory: actionHistory
            )

            prompt = basePrompt

            logger.debug(category: .agentLoop, "Sending prompt to LLM client")
            llmCallIndex += 1
            callStart = Date()
            let result = try performPromptSync(prompt: basePrompt)
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
                prompt: basePrompt,
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
            logger.warning(category: .agentLoop, "Error on attempt \(retries)/\(configuration.retryLimit): \(error.localizedDescription)")
            guard retries < configuration.retryLimit else {
                logger.error(category: .agentLoop, "Retry limit (\(configuration.retryLimit)) exceeded. Last error: \(error.localizedDescription)")
                return ActionSequence(
                    description: error.localizedDescription,
                    actions: [
                        .failure
                    ]
                )
            }
            logger.info(category: .agentLoop, "Retrying (attempt \(retries + 1)/\(configuration.retryLimit))...")
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

    // MARK: - Helpers

    private func detectLoop(fingerprint: String) -> Bool {
        let loopWindowSize = configuration.resolvedLoopWindowSize()
        // Require a full window before declaring a loop to avoid early failures.
        guard recentScreenFingerprints.count >= loopWindowSize else {
            return false
        }

        // Count occurrences of current fingerprint in the recent window.
        let occurrences = recentScreenFingerprints.filter { $0 == fingerprint }.count

        // If we've seen this screen at least maxAttemptsPerScreen times within the window,
        // it's likely an A/B (or similar) loop without progress.
        return occurrences >= configuration.maxAttemptsPerScreen
    }

}
