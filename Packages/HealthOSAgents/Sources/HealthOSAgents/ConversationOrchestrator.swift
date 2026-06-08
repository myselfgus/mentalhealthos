import Foundation
import HealthOSCore
import HealthOSPipeline

public struct ConversationOrchestratorOptions: Sendable {
    public var conversationId: String
    public var patientId: String?
    public var sessionId: String?
    public var runtimeName: String
    public var workspaceManager: WorkspaceManager?
    public var registry: AgentRegistry

    public init(
        conversationId: String = "conv_\(UUID().uuidString.lowercased())",
        patientId: String? = nil,
        sessionId: String? = nil,
        runtimeName: String = "deterministic",
        workspaceManager: WorkspaceManager? = nil,
        registry: AgentRegistry = .shared
    ) {
        self.conversationId = conversationId
        self.patientId = patientId
        self.sessionId = sessionId
        self.runtimeName = runtimeName
        self.workspaceManager = workspaceManager
        self.registry = registry
    }
}

public final class ConversationOrchestrator: @unchecked Sendable {
    public private(set) var conversationId: String
    public private(set) var patientId: String?
    public private(set) var sessionId: String?
    public private(set) var runtimeName: String
    public var messages: [ChatMessage] = []

    private var provider: (any LLMProvider)?
    private var workspaceManager: WorkspaceManager?
    private var registry: AgentRegistry

    public init(options: ConversationOrchestratorOptions = ConversationOrchestratorOptions()) {
        self.conversationId = options.conversationId
        self.patientId = options.patientId
        self.sessionId = options.sessionId
        self.runtimeName = options.runtimeName
        self.workspaceManager = options.workspaceManager
        self.registry = options.registry
    }

    public convenience init(
        patientId: String? = nil,
        sessionId: String? = nil,
        workspaceManager: WorkspaceManager? = nil,
        provider: (any LLMProvider)? = nil
    ) {
        self.init(options: ConversationOrchestratorOptions(
            patientId: patientId,
            sessionId: sessionId,
            runtimeName: provider?.name ?? "deterministic",
            workspaceManager: workspaceManager
        ))
        self.provider = provider
    }

    public func setProvider(_ provider: (any LLMProvider)?) {
        self.provider = provider
        self.runtimeName = provider?.name ?? "deterministic"
    }

    public func setRuntimeName(_ runtimeName: String) {
        self.runtimeName = runtimeName
    }

    public func setActivePatient(_ patientId: String?, sessionId: String? = nil) {
        self.patientId = patientId
        self.sessionId = sessionId
    }

    public func routeIntentToAgent(_ input: String) -> String {
        AgentWorkflowDetector.detect(
            input: input,
            options: AgentWorkflowDetectionOptions(patientId: patientId)
        ).agentId
    }

    public func detectWorkflow(_ input: String, stage: PipelineWorkflowStage? = nil) -> AgentWorkflowDetection {
        detectAgentWorkflow(input, patientId: patientId, stage: stage)
    }

    public func planWorkflow(_ input: String, stage: PipelineWorkflowStage? = nil) -> AgentWorkflowPlan {
        let refs = contextReferences()
        return AgentWorkflowDetector.plan(
            input: input,
            patientId: patientId,
            sessionId: sessionId,
            stage: stage,
            inputRefs: refs
        )
    }

    public func processInput(_ input: String) async throws -> String {
        let result = await processInputResult(input)
        if result.status == "failed" {
            throw HealthOSAgentsError.notConfigured(LocalAgentErrorPayload(
                code: .runtimeNotConfigured,
                message: result.error ?? "HealthOSAgents runtime is not configured.",
                agentId: routeIntentToAgent(input),
                workflowKind: detectWorkflow(input).kind.rawValue,
                requiredRuntime: "LLMProvider"
            ))
        }
        return result.content ?? ""
    }

    public func processInputResult(_ input: String, stage: PipelineWorkflowStage? = nil) async -> AgentResult {
        messages.append(ChatMessage(role: .user, content: input))
        let plan = planWorkflow(input, stage: stage)
        let detection = plan.detection

        if detection.requiresPatient, patientId == nil {
            let result = AgentResult.patientRequired(
                agentId: detection.agentId,
                workflowKind: detection.kind.rawValue
            )
            messages.append(ChatMessage(role: .assistant, content: result.content ?? result.error ?? ""))
            return result
        }

        if isDeterministicOnly(plan) {
            let result = deterministicResult(for: input, plan: plan)
            messages.append(ChatMessage(role: .assistant, content: result.content ?? ""))
            return result
        }

        if detection.kind == .pipelineStage {
            let result = AgentResult.toolNotConfigured(
                toolName: "run_pipeline",
                agentId: detection.agentId,
                workflowKind: detection.kind.rawValue
            )
            messages.append(ChatMessage(role: .assistant, content: result.content ?? result.error ?? ""))
            return result
        }

        guard let provider else {
            let result = AgentResult.runtimeNotConfigured(
                agentId: detection.agentId,
                workflowKind: detection.kind.rawValue
            )
            messages.append(ChatMessage(role: .assistant, content: result.content ?? result.error ?? ""))
            return result
        }

        do {
            let request = LLMRequest(
                userPrompt: input,
                systemPrompt: try systemPrompt(),
                temperature: 0.2,
                timeoutSeconds: 120,
                useCache: true
            )
            let response = try await provider.complete(request: request)
            var result = AgentResult(status: "completed", content: response.content)
            result.outputRefs = plan.inputRefs
            result.reviewRequired = detection.reviewRequired
            messages.append(ChatMessage(role: .assistant, content: response.content))
            return result
        } catch {
            var result = AgentResult(status: "failed", content: nil)
            result.outputRefs = []
            result.error = error.localizedDescription
            messages.append(ChatMessage(role: .assistant, content: error.localizedDescription))
            return result
        }
    }

    private func deterministicResult(for input: String, plan: AgentWorkflowPlan) -> AgentResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let payload: [String: String] = [
            "conversation_id": conversationId,
            "agent_id": plan.detection.agentId,
            "workflow_kind": plan.detection.kind.rawValue,
            "runtime": runtimeName,
        ]

        let content: String
        if plan.detection.kind == .contextMapping, let manager = workspaceManager {
            content = (try? ChatContextBuilder(manager: manager).renderSystemPrompt(
                activePatientId: patientId,
                sessionId: sessionId
            )) ?? encode(payload, with: encoder)
        } else if input.trimmingCharacters(in: .whitespacesAndNewlines) == "/agents" {
            let agents = registry.listAgentDefinitions(options: ListAgentDefinitionsOptions(
                includeScenario: true,
                includeCodex: true,
                includePrompts: false,
                patientId: patientId
            ))
            content = encode(agents, with: encoder)
        } else {
            content = encode(plan, with: encoder)
        }

        var result = AgentResult(status: "completed", content: content)
        result.outputRefs = plan.inputRefs
        result.reviewRequired = plan.detection.reviewRequired
        return result
    }

    private func isDeterministicOnly(_ plan: AgentWorkflowPlan) -> Bool {
        if plan.detection.kind == .pipelineStage {
            return false
        }
        return !plan.requiresRuntime
    }

    private func systemPrompt() throws -> String? {
        guard let workspaceManager else { return nil }
        return try ChatContextBuilder(manager: workspaceManager)
            .renderSystemPrompt(activePatientId: patientId, sessionId: sessionId)
    }

    private func contextReferences() -> [String] {
        guard let workspaceManager else { return [] }
        return ChatContextBuilder(manager: workspaceManager)
            .collectContextReferences(activePatientId: patientId, sessionId: sessionId)
    }

    private func encode<T: Encodable>(_ value: T, with encoder: JSONEncoder) -> String {
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
