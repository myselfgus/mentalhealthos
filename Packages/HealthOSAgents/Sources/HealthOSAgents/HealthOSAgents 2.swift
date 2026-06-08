import Foundation
import HealthOSCore

// MARK: - Conversation Orchestrator

@Observable
public final class ConversationOrchestrator: @unchecked Sendable {
    public var messages: [ChatMessage] = []
    
    public init() {}
    
    public func routeIntentToAgent(_ input: String) -> String {
        return "conversation-agent"
    }
    
    public func processInput(_ input: String) async throws -> String {
        return "Resposta do agente (stub)."
    }
}

// MARK: - Agent Registry

public struct AgentRegistry: Sendable {
    public static let shared = AgentRegistry()
    public func listAgentDefinitions() -> [AgentDefinition] {
        return []
    }
}
