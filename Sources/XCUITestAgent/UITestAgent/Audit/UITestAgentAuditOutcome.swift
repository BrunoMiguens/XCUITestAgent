import Foundation

/// The outcome of a completed test run, reported via the audit provider.
public enum UITestAgentAuditOutcome: Codable {
    case success
    case failure
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case errorDescription
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success:
            try container.encode("success", forKey: .type)
        case .failure:
            try container.encode("failure", forKey: .type)
        case .error(let description):
            try container.encode("error", forKey: .type)
            try container.encode(description, forKey: .errorDescription)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "success":
            self = .success
        case "failure":
            self = .failure
        case "error":
            let description = try container.decode(String.self, forKey: .errorDescription)
            self = .error(description)
        default:
            self = .error("Unknown outcome type: \(type)")
        }
    }
}
