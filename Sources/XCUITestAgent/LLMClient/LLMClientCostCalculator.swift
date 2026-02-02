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
        "gpt-4o": ModelPricing(inputPricePerMillion: 2.50, outputPricePerMillion: 10.00),
        "gpt-4o-2024-08-06": ModelPricing(inputPricePerMillion: 2.50, outputPricePerMillion: 10.00),
        "gpt-4o-2024-11-20": ModelPricing(inputPricePerMillion: 2.50, outputPricePerMillion: 10.00),
        "gpt-4o-mini": ModelPricing(inputPricePerMillion: 0.15, outputPricePerMillion: 0.60),
    ]

    public init(pricingTable: [String: ModelPricing] = LLMClientCostCalculator.defaultPricingTable) {
        self.pricingTable = pricingTable
    }

    public func calculate(for usage: LLMClientUsage) -> LLMClientCost? {
        guard let pricing = pricingTable[usage.model] else {
            return nil
        }
        let promptCost = Double(usage.promptTokens) / 1_000_000.0 * pricing.inputPricePerMillion
        let completionCost = Double(usage.completionTokens) / 1_000_000.0 * pricing.outputPricePerMillion
        return LLMClientCost(
            promptCost: promptCost,
            completionCost: completionCost,
            model: usage.model,
            usage: usage
        )
    }
}
