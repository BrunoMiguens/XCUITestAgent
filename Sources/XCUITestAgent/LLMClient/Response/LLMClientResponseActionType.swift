import Foundation

enum LLMClientResponseActionType: String, Codable {
    case tap
    case enterText
    case typeText
    case swipe
    case idle
    case success
    case failure
}
