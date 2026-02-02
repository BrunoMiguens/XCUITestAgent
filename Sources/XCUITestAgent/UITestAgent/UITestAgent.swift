import Foundation

open class UITestAgent {
    private let retryLimit: Int = 3

    public let client: LLMClient
    public let responseMapper: LLMClientResponseMapper

    public let promptProvider: UITestAgentPromptProvider
    public let actionPerformer: UITestAgentActionPerformer
    public let logger: UITestAgentLogger

    private var actionHistory: [ActionSequence] = []
    private var retries = 0

    private let costCalculator = LLMClientCostCalculator()
    private var costs: [LLMClientCost] = []

    public init(
        client: LLMClient,
        responseMapper: LLMClientResponseMapper,
        promptProvider: UITestAgentPromptProvider,
        actionPerformer: UITestAgentActionPerformer,
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.client = client
        self.responseMapper = responseMapper
        self.promptProvider = promptProvider
        self.actionPerformer = actionPerformer
        self.logger = logger
    }

    public func runTest(_ testPrompt: String) {
        resetSession()
        logger.info(category: .agentLoop, "Starting test: \(testPrompt)")

        // main test run loop
        var shouldContinue = true
        var iteration = 0
        while shouldContinue {
            iteration += 1
            logger.debug(category: .agentLoop, "Iteration \(iteration) starting")
            shouldContinue = performNextActionSequence(testPrompt: testPrompt)
        }

        logger.info(category: .agentLoop, "Test completed after \(iteration) iteration(s)")

        if !costs.isEmpty {
            let totalCost = costs.reduce(0.0) { $0 + $1.totalCost }
            let formattedCost = String(format: "$%.6f", totalCost)
            logger.info(category: .agentLoop, "Total cost: \(formattedCost) across \(costs.count) LLM call(s)")
            actionPerformer.reportTotalCost(totalCost, callCount: costs.count)
        }
    }

    private func performNextActionSequence(testPrompt: String) -> Bool {
        // determine next sequence
        let nextActionSequence = nextAction(
            testPrompt,
            actionHistory: actionHistory
        )
        guard let lastAction = nextActionSequence.actions.last else {
            logger.error(category: .agentLoop, "Unable to determine next action, failing test")
            actionPerformer.perform(ActionSequence(
                description: "Unable to determine next action.",
                actions: [
                    .failure
                ]
            ))
            return false
        }

        // perform action sequence
        logger.info(category: .agentLoop, "Performing: \(nextActionSequence.description)")
        logger.debug(category: .agentLoop, "Actions in sequence: \(nextActionSequence.actions.count)")
        actionPerformer.perform(nextActionSequence)
        switch lastAction {
        case .success:
            logger.info(category: .agentLoop, "Test PASSED: \(nextActionSequence.description)")
            return false
        case .failure:
            logger.error(category: .agentLoop, "Test FAILED: \(nextActionSequence.description)")
            return false
        default:
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
    }

    private func nextAction(_ testPrompt: String, actionHistory: [ActionSequence]) -> ActionSequence {
        do {
            logger.debug(category: .agentLoop, "Building prompt for LLM")
            let prompt = try promptProvider.makePrompt(
                testPrompt,
                actionHistory: actionHistory
            )
            logger.debug(category: .agentLoop, "Sending prompt to LLM client")
            let result = try performPromptSync(prompt: prompt)

            if let usage = result.usage {
                logger.debug(category: .agentLoop, "Token usage — prompt: \(usage.promptTokens), completion: \(usage.completionTokens), total: \(usage.totalTokens), model: \(usage.model)")
                let cost = costCalculator.calculate(for: usage)
                costs.append(cost)
                let formattedCost = String(format: "$%.6f", cost.totalCost)
                logger.info(category: .agentLoop, "LLM call cost: \(formattedCost) (\(cost.model), \(cost.usage.promptTokens) prompt + \(cost.usage.completionTokens) completion tokens)")
                actionPerformer.reportCost(cost)
            } else {
                logger.debug(category: .agentLoop, "No token usage data returned by LLM client")
            }

            logger.debug(category: .agentLoop, "Mapping LLM response to action sequence")
            let action = try responseMapper.map(response: result.content)
            retries = 0
            return action
        } catch let error {
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
                actionHistory: actionHistory
            )
        }
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
}
