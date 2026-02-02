import Foundation

public struct LLMClientCost {
    public let promptCost: Double
    public let completionCost: Double
    public var totalCost: Double { promptCost + completionCost }
    public let model: String
    public let usage: LLMClientUsage

    public init(
        promptCost: Double,
        completionCost: Double,
        model: String,
        usage: LLMClientUsage
    ) {
        self.promptCost = promptCost
        self.completionCost = completionCost
        self.model = model
        self.usage = usage
    }
}

public struct LLMClientCostCalculator {
    public struct ModelPricing {
        public let inputPricePerMillion: Double
        public let outputPricePerMillion: Double

        public init(inputPricePerMillion: Double, outputPricePerMillion: Double) {
            self.inputPricePerMillion = inputPricePerMillion
            self.outputPricePerMillion = outputPricePerMillion
        }
    }

    private let pricingTable: [String: ModelPricing]

    public static let defaultPricingTable: [String: ModelPricing] = [
        "gpt-4.1": ModelPricing(inputPricePerMillion: 2.00, outputPricePerMillion: 8.00),
        "gpt-4.1-mini": ModelPricing(inputPricePerMillion: 0.40, outputPricePerMillion: 1.60),
        "gpt-4.1-nano": ModelPricing(inputPricePerMillion: 0.10, outputPricePerMillion: 0.40),
        "gpt-4o": ModelPricing(inputPricePerMillion: 2.50, outputPricePerMillion: 10.00),
        "gpt-4o-2024-08-06": ModelPricing(inputPricePerMillion: 2.50, outputPricePerMillion: 10.00),
        "gpt-4o-2024-11-20": ModelPricing(inputPricePerMillion: 2.50, outputPricePerMillion: 10.00),
        "gpt-4o-mini": ModelPricing(inputPricePerMillion: 0.15, outputPricePerMillion: 0.60),
    ]

    public init(pricingTable: [String: ModelPricing] = LLMClientCostCalculator.defaultPricingTable) {
        self.pricingTable = pricingTable
        Self.validatePricingCoverage(pricingTable: pricingTable)
    }

    /// Validates that every known model enum case has a corresponding entry in the pricing table.
    /// Triggers a precondition failure if any model is missing — catches mismatches at init time.
    private static func validatePricingCoverage(pricingTable: [String: ModelPricing]) {
        for model in OpenAIModel.allCases {
            precondition(
                pricingTable[model.rawValue] != nil,
                "Missing pricing entry for OpenAI model '\(model.rawValue)'. Update the pricing table."
            )
        }
    }

    public func calculate(for usage: LLMClientUsage) -> LLMClientCost {
        let pricing = resolvePricing(for: usage.model)
        let promptCost = Double(usage.promptTokens) / 1_000_000.0 * pricing.inputPricePerMillion
        let completionCost = Double(usage.completionTokens) / 1_000_000.0 * pricing.outputPricePerMillion
        return LLMClientCost(
            promptCost: promptCost,
            completionCost: completionCost,
            model: usage.model,
            usage: usage
        )
    }

    /// Resolves pricing for a model string. Tries exact match first, then strips
    /// date suffixes (e.g. "gpt-4.1-mini-2025-04-14" → "gpt-4.1-mini").
    /// Fails with precondition if no pricing is found.
    private func resolvePricing(for model: String) -> ModelPricing {
        if let pricing = pricingTable[model] {
            return pricing
        }
        // Strip date suffix: match "-YYYY-MM-DD" at end of string
        let stripped = model.replacingOccurrences(
            of: #"-\d{4}-\d{2}-\d{2}$"#,
            with: "",
            options: .regularExpression
        )
        if stripped != model, let pricing = pricingTable[stripped] {
            return pricing
        }
        preconditionFailure("No pricing available for model '\(model)'. Add an entry to the pricing table or update the OpenAIModel enum.")
    }
}
