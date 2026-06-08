import Foundation
import HealthOSCore

public enum LocalAgentErrorCode: String, Codable, Sendable {
    case runtimeNotConfigured = "runtime_not_configured"
    case toolNotConfigured = "tool_not_configured"
    case patientRequired = "patient_required"
    case workflowNotRecognized = "workflow_not_recognized"
}

public struct LocalAgentErrorPayload: Codable, Sendable {
    public let code: LocalAgentErrorCode
    public let message: String
    public let agentId: String?
    public let workflowKind: String?
    public let requiredRuntime: String?
    public let remediation: [String]

    public init(
        code: LocalAgentErrorCode,
        message: String,
        agentId: String? = nil,
        workflowKind: String? = nil,
        requiredRuntime: String? = nil,
        remediation: [String] = []
    ) {
        self.code = code
        self.message = message
        self.agentId = agentId
        self.workflowKind = workflowKind
        self.requiredRuntime = requiredRuntime
        self.remediation = remediation
    }
}

public enum HealthOSAgentsError: LocalizedError, Sendable {
    case notConfigured(LocalAgentErrorPayload)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let payload):
            payload.message
        }
    }
}

public extension AgentResult {
    static func localFailure(_ payload: LocalAgentErrorPayload) -> AgentResult {
        var result = AgentResult(status: "failed", content: payload.prettyJSONString())
        result.outputRefs = []
        result.error = payload.message
        return result
    }

    static func runtimeNotConfigured(
        agentId: String,
        workflowKind: String? = nil,
        requiredRuntime: String = "LLMProvider",
        remediation: [String] = [
            "Inject a configured LLMProvider into ConversationOrchestrator.",
            "Keep deterministic planning/catalog/context calls separate from clinical generation.",
        ]
    ) -> AgentResult {
        .localFailure(LocalAgentErrorPayload(
            code: .runtimeNotConfigured,
            message: "Runtime/provider is not configured for agent \(agentId).",
            agentId: agentId,
            workflowKind: workflowKind,
            requiredRuntime: requiredRuntime,
            remediation: remediation
        ))
    }

    static func toolNotConfigured(
        toolName: String,
        agentId: String,
        workflowKind: String? = nil
    ) -> AgentResult {
        .localFailure(LocalAgentErrorPayload(
            code: .toolNotConfigured,
            message: "Local tool \(toolName) is described but has no Swift executor configured yet.",
            agentId: agentId,
            workflowKind: workflowKind,
            requiredRuntime: "LocalToolExecutor",
            remediation: [
                "Use AgentWorkflowPlan for routing until a local executor is wired.",
                "Wire a local Swift executor before enabling this tool.",
            ]
        ))
    }

    static func patientRequired(agentId: String, workflowKind: String? = nil) -> AgentResult {
        .localFailure(LocalAgentErrorPayload(
            code: .patientRequired,
            message: "This workflow requires an active patient id.",
            agentId: agentId,
            workflowKind: workflowKind,
            remediation: [
                "Start the chat with a patient id or pass patientId when planning/running the workflow.",
            ]
        ))
    }
}

private extension LocalAgentErrorPayload {
    func prettyJSONString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"code":"\#(code.rawValue)","message":"\#(message)"}"#
        }
        return text
    }
}
