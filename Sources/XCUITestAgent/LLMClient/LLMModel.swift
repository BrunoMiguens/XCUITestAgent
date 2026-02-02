import Foundation

/// Unified model enum with associated values per provider.
/// Each case wraps a provider-specific model enum and shared image detail setting.
public enum LLMModel {
    case openAI(model: OpenAIModel = .gpt4_1_mini, imageDetail: LLMClientImageDetail = .high)

    /// Raw model identifier string for API calls and cost calculation.
    public var modelIdentifier: String {
        switch self {
        case .openAI(let model, _):
            return model.rawValue
        }
    }

    /// Image detail level configured for this model.
    public var imageDetail: LLMClientImageDetail {
        switch self {
        case .openAI(_, let imageDetail):
            return imageDetail
        }
    }
}

/// OpenAI model identifiers.
public enum OpenAIModel: String, CaseIterable {
    case gpt4_1 = "gpt-4.1"
    case gpt4_1_mini = "gpt-4.1-mini"
    case gpt4_1_nano = "gpt-4.1-nano"
    case gpt4_o = "gpt-4o"
    case gpt4_o_mini = "gpt-4o-mini"
}
