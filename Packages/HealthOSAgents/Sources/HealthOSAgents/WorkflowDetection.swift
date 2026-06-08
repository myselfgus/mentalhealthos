import Foundation

public enum PipelineWorkflowStage: String, Codable, CaseIterable, Sendable {
    case transcribe
    case process
    case speech
    case asl
    case vdlp
    case gem
}

public enum AgentWorkflowKind: String, Codable, CaseIterable, Sendable {
    case conversation
    case clinicalCare = "clinical_care"
    case clinicalRiskCheck = "clinical_risk_check"
    case clinicalSessionPrep = "clinical_session_prep"
    case clinicalLongitudinalReview = "clinical_longitudinal_review"
    case pipelineStage = "pipeline_stage"
    case memoryCommit = "memory_commit"
    case contextMapping = "context_mapping"
    case qaValidation = "qa_validation"
}

public struct AgentWorkflowDetection: Codable, Sendable {
    public let kind: AgentWorkflowKind
    public let agentId: String
    public let patientAgentId: String?
    public let stage: PipelineWorkflowStage?
    public let requiresPatient: Bool
    public let reviewRequired: Bool

    public init(
        kind: AgentWorkflowKind,
        agentId: String,
        patientAgentId: String? = nil,
        stage: PipelineWorkflowStage? = nil,
        requiresPatient: Bool,
        reviewRequired: Bool
    ) {
        self.kind = kind
        self.agentId = agentId
        self.patientAgentId = patientAgentId
        self.stage = stage
        self.requiresPatient = requiresPatient
        self.reviewRequired = reviewRequired
    }
}

public struct AgentWorkflowDetectionOptions: Sendable {
    public var patientId: String?
    public var stage: PipelineWorkflowStage?

    public init(patientId: String? = nil, stage: PipelineWorkflowStage? = nil) {
        self.patientId = patientId
        self.stage = stage
    }
}

public struct AgentWorkflowStepPlan: Codable, Sendable {
    public let agentId: String
    public let kind: String
    public let toolNames: [String]
    public let requiresRuntime: Bool

    public init(agentId: String, kind: String, toolNames: [String], requiresRuntime: Bool) {
        self.agentId = agentId
        self.kind = kind
        self.toolNames = toolNames
        self.requiresRuntime = requiresRuntime
    }
}

public struct AgentWorkflowPlan: Codable, Sendable {
    public let detection: AgentWorkflowDetection
    public let contextStep: AgentWorkflowStepPlan
    public let primaryStep: AgentWorkflowStepPlan
    public let reviewStep: AgentWorkflowStepPlan?
    public let inputRefs: [String]
    public let notes: [String]

    public var requiresRuntime: Bool {
        primaryStep.requiresRuntime || (reviewStep?.requiresRuntime ?? false)
    }
}

public enum AgentWorkflowDetector {
    public static func detect(
        input: String,
        options: AgentWorkflowDetectionOptions = AgentWorkflowDetectionOptions()
    ) -> AgentWorkflowDetection {
        let text = normalize(input)
        let stage = options.stage ?? detectPipelineStage(text)
        if let stage {
            return AgentWorkflowDetection(
                kind: .pipelineStage,
                agentId: pipelineAgentId(stage),
                stage: stage,
                requiresPatient: false,
                reviewRequired: false
            )
        }

        if isExplicitMemoryCommit(text) {
            return AgentWorkflowDetection(
                kind: .memoryCommit,
                agentId: "memory-agent",
                requiresPatient: false,
                reviewRequired: false
            )
        }

        if mentionsRisk(text) {
            return AgentWorkflowDetection(
                kind: .clinicalRiskCheck,
                agentId: "risk-check-agent",
                patientAgentId: "risk-check",
                requiresPatient: true,
                reviewRequired: true
            )
        }

        if mentionsSessionPrep(text) {
            return AgentWorkflowDetection(
                kind: .clinicalSessionPrep,
                agentId: "session-prep-agent",
                patientAgentId: "session-prep",
                requiresPatient: true,
                reviewRequired: true
            )
        }

        if mentionsLongitudinalReview(text) {
            return AgentWorkflowDetection(
                kind: .clinicalLongitudinalReview,
                agentId: "longitudinal-reviewer-agent",
                patientAgentId: "longitudinal-reviewer",
                requiresPatient: true,
                reviewRequired: true
            )
        }

        if options.patientId != nil, mentionsClinicalCare(text) {
            return AgentWorkflowDetection(
                kind: .clinicalCare,
                agentId: "patient-care-agent",
                requiresPatient: true,
                reviewRequired: true
            )
        }

        if mentionsContext(text) {
            return AgentWorkflowDetection(
                kind: .contextMapping,
                agentId: "context-agent",
                requiresPatient: false,
                reviewRequired: false
            )
        }

        if mentionsQA(text) {
            return AgentWorkflowDetection(
                kind: .qaValidation,
                agentId: "qa-agent",
                requiresPatient: false,
                reviewRequired: false
            )
        }

        return AgentWorkflowDetection(
            kind: .conversation,
            agentId: "conversation-agent",
            requiresPatient: false,
            reviewRequired: false
        )
    }

    public static func plan(
        input: String,
        patientId: String? = nil,
        sessionId: String? = nil,
        stage: PipelineWorkflowStage? = nil,
        inputRefs: [String] = []
    ) -> AgentWorkflowPlan {
        let detection = detect(
            input: input,
            options: AgentWorkflowDetectionOptions(patientId: patientId, stage: stage)
        )
        let contextStep = AgentWorkflowStepPlan(
            agentId: "context-agent",
            kind: "governance",
            toolNames: ["professional_context", "patient_context", "artifact_refs"],
            requiresRuntime: false
        )
        let primaryTools = toolsForDetection(detection)
        let primaryStep = AgentWorkflowStepPlan(
            agentId: detection.agentId,
            kind: taskKind(for: detection),
            toolNames: primaryTools,
            requiresRuntime: primaryRequiresRuntime(detection)
        )
        let reviewStep = detection.reviewRequired
            ? AgentWorkflowStepPlan(
                agentId: "safety-review-agent",
                kind: "governance",
                toolNames: ["safety_review", "evidence_check"],
                requiresRuntime: true
            )
            : nil

        var notes = [
            "Workflow planned locally in the Swift runtime.",
            "Clinical generation requires an injected LLMProvider.",
        ]
        if detection.requiresPatient, patientId == nil {
            notes.append("This workflow requires a patientId before execution.")
        }
        if let sessionId {
            notes.append("Session scope: \(sessionId).")
        }

        return AgentWorkflowPlan(
            detection: detection,
            contextStep: contextStep,
            primaryStep: primaryStep,
            reviewStep: reviewStep,
            inputRefs: inputRefs,
            notes: notes
        )
    }
}

public func detectAgentWorkflow(
    _ input: String,
    patientId: String? = nil,
    stage: PipelineWorkflowStage? = nil
) -> AgentWorkflowDetection {
    AgentWorkflowDetector.detect(
        input: input,
        options: AgentWorkflowDetectionOptions(patientId: patientId, stage: stage)
    )
}

public func routeIntentToAgent(_ input: String, patientId: String? = nil) -> String {
    detectAgentWorkflow(input, patientId: patientId).agentId
}

public func pipelineAgentId(_ stage: PipelineWorkflowStage) -> String {
    switch stage {
    case .transcribe:
        "transcription-agent"
    case .process:
        "session-structuring-agent"
    case .speech:
        "speech-attribution-agent"
    case .asl:
        "asl-agent"
    case .vdlp:
        "vdlp-agent"
    case .gem:
        "gem-agent"
    }
}

private func normalize(_ input: String) -> String {
    input
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
        .lowercased()
}

private func detectPipelineStage(_ text: String) -> PipelineWorkflowStage? {
    if text.contains("patient-speech") || text.contains("fala do paciente") || text.contains("falas do paciente") {
        return .speech
    }
    if text.contains("transcri") || text.contains("scribe") || text.contains("audio") {
        return .transcribe
    }
    if text.contains("asl") || text.contains("analise sistemica linguistica") {
        return .asl
    }
    if text.contains("vdlp") || text.contains("dimens") || text.contains("vetor") {
        return .vdlp
    }
    if text.contains("gem") || text.contains("grafo") {
        return .gem
    }
    if text.contains("pipeline") || text.contains("process") || text.contains("dossie") || text.contains("organiza") {
        return .process
    }
    return nil
}

private func isExplicitMemoryCommit(_ text: String) -> Bool {
    text.hasPrefix("/remember") ||
    text.contains("salva memoria") ||
    text.contains("salve memoria") ||
    text.contains("guardar memoria") ||
    text.contains("registre memoria")
}

private func mentionsRisk(_ text: String) -> Bool {
    text.contains("risk") ||
    text.contains("risco") ||
    text.contains("suicid") ||
    text.contains("automutil") ||
    text.contains("seguranca") ||
    text.contains("medicacao") ||
    text.contains("medicamento")
}

private func mentionsSessionPrep(_ text: String) -> Bool {
    (text.contains("prepar") || text.contains("planej")) &&
    (text.contains("sess") || text.contains("consulta") || text.contains("atendimento"))
}

private func mentionsLongitudinalReview(_ text: String) -> Bool {
    text.contains("longitudinal") ||
    text.contains("linha do tempo") ||
    text.contains("historico") ||
    text.contains("evolucao")
}

private func mentionsClinicalCare(_ text: String) -> Bool {
    text.contains("caso") ||
    text.contains("paciente") ||
    text.contains("clinico") ||
    text.contains("clinica") ||
    text.contains("hipotese") ||
    text.contains("diagnost") ||
    text.contains("sintese") ||
    text.contains("resumo")
}

private func mentionsContext(_ text: String) -> Bool {
    text.contains("context") ||
    text.contains("arquitet") ||
    text.contains("referencia") ||
    text.contains("map")
}

private func mentionsQA(_ text: String) -> Bool {
    text.contains("qa") ||
    text.contains("teste") ||
    text.contains("valid") ||
    text.contains("regress")
}

private func taskKind(for detection: AgentWorkflowDetection) -> String {
    switch detection.kind {
    case .pipelineStage:
        "pipeline"
    case .clinicalCare, .clinicalRiskCheck, .clinicalSessionPrep, .clinicalLongitudinalReview:
        "clinical"
    case .memoryCommit:
        "memory"
    case .contextMapping:
        "governance"
    case .qaValidation:
        "qa"
    case .conversation:
        "conversation"
    }
}

private func primaryRequiresRuntime(_ detection: AgentWorkflowDetection) -> Bool {
    switch detection.kind {
    case .contextMapping, .memoryCommit, .qaValidation:
        false
    case .pipelineStage:
        detection.stage != .transcribe
    case .conversation, .clinicalCare, .clinicalRiskCheck, .clinicalSessionPrep, .clinicalLongitudinalReview:
        true
    }
}

private func toolsForDetection(_ detection: AgentWorkflowDetection) -> [String] {
    switch detection.kind {
    case .pipelineStage:
        if let stage = detection.stage {
            return ["run_pipeline:\(stage.rawValue)"]
        }
        return ["run_pipeline"]
    case .clinicalCare:
        return ["run_patient_agent"]
    case .clinicalRiskCheck:
        return ["run_patient_agent:risk-check"]
    case .clinicalSessionPrep:
        return ["run_patient_agent:session-prep"]
    case .clinicalLongitudinalReview:
        return ["run_patient_agent:longitudinal-reviewer"]
    case .memoryCommit:
        return ["memory_policy", "append_professional_memory"]
    case .contextMapping:
        return ["professional_context", "patient_context", "artifact_refs"]
    case .qaValidation:
        return ["swift_test", "schema_validation"]
    case .conversation:
        return ["llm_completion"]
    }
}
