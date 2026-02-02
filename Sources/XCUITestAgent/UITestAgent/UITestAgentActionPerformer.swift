import Foundation

public protocol UITestAgentActionPerformer {
    func perform(_ actionSequence: ActionSequence)
    func reportCost(_ cost: LLMClientCost)
    func reportTotalCost(_ totalCost: Double, callCount: Int)
}

public extension UITestAgentActionPerformer {
    func reportCost(_ cost: LLMClientCost) {}
    func reportTotalCost(_ totalCost: Double, callCount: Int) {}
}
