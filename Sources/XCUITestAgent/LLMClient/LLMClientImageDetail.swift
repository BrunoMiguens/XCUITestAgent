import Foundation

/// Image detail level for vision-capable LLM providers.
/// Each provider maps this to its API-specific representation.
public enum LLMClientImageDetail {
    case low
    case high
    case auto
}
