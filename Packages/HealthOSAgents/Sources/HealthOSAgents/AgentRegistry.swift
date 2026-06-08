import Foundation
import HealthOSCore

public struct ListAgentDefinitionsOptions: Sendable {
    public var includeScenario: Bool
    public var includeCodex: Bool
    public var includePrompts: Bool
    public var patientId: String?

    public init(
        includeScenario: Bool = false,
        includeCodex: Bool = true,
        includePrompts: Bool = false,
        patientId: String? = nil
    ) {
        self.includeScenario = includeScenario
        self.includeCodex = includeCodex
        self.includePrompts = includePrompts
        self.patientId = patientId
    }
}

public struct AgentRegistry: Sendable {
    public static let shared = AgentRegistry()

    public let baseDir: URL?
    public let codexAgentsDir: URL

    public init(
        baseDir: URL? = nil,
        codexAgentsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("agents")
    ) {
        self.baseDir = baseDir
        self.codexAgentsDir = codexAgentsDir
    }

    public func listAgentDefinitions(
        options: ListAgentDefinitionsOptions = ListAgentDefinitionsOptions()
    ) -> [AgentDefinition] {
        let resolvedBaseDir = baseDir ?? HealthOSWorkspaceLocator.detectBaseDirectory()
        var definitions = Self.systemAgentDefinitions
        definitions.append(contentsOf: Self.healthOSAgentDefinitions(
            includeScenario: options.includeScenario,
            includePrompts: options.includePrompts
        ))
        if options.includeCodex {
            definitions.append(contentsOf: listCodexAgentDefinitions(includePrompts: options.includePrompts))
        }
        if let patientId = options.patientId,
           let resolvedPatientId = resolvePatientId(patientId, baseDir: resolvedBaseDir) {
            definitions.append(contentsOf: listPatientAgentDefinitions(
                patientId: resolvedPatientId,
                baseDir: resolvedBaseDir,
                includePrompts: options.includePrompts
            ))
        }
        return definitions.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func listAgentDefinitions(
        includeScenario: Bool = false,
        includeCodex: Bool = true,
        patientId: String? = nil
    ) -> [AgentDefinition] {
        listAgentDefinitions(options: ListAgentDefinitionsOptions(
            includeScenario: includeScenario,
            includeCodex: includeCodex,
            includePrompts: false,
            patientId: patientId
        ))
    }

    public func resolveAgentDefinition(
        _ id: String,
        options: ListAgentDefinitionsOptions = ListAgentDefinitionsOptions(includeScenario: true)
    ) -> AgentDefinition? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return listAgentDefinitions(options: options).first { definition in
            definition.id.lowercased() == normalized ||
            definition.title.lowercased() == normalized
        }
    }

    public func listPatientAgentDefinitions(
        patientId: String,
        includePrompts: Bool = false
    ) -> [AgentDefinition] {
        let resolvedBaseDir = baseDir ?? HealthOSWorkspaceLocator.detectBaseDirectory()
        guard let resolvedPatientId = resolvePatientId(patientId, baseDir: resolvedBaseDir) else {
            return []
        }
        return listPatientAgentDefinitions(
            patientId: resolvedPatientId,
            baseDir: resolvedBaseDir,
            includePrompts: includePrompts
        )
    }

    private func listCodexAgentDefinitions(includePrompts: Bool) -> [AgentDefinition] {
        guard FileManager.default.fileExists(atPath: codexAgentsDir.path) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: codexAgentsDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []

        return files
            .filter { ["toml", "md"].contains($0.pathExtension.lowercased()) }
            .map { file in
                var definition = makeAgentDefinition(
                    id: file.deletingPathExtension().lastPathComponent,
                    title: file.deletingPathExtension().lastPathComponent,
                    source: "codex",
                    category: "codex-subagent",
                    purpose: "Subagente Codex instalado localmente em ~/.codex/agents.",
                    runtimePolicy: "codex-local",
                    tools: ["codex exec"],
                    path: "~/.codex/agents/\(file.lastPathComponent)"
                )
                if includePrompts {
                    definition.prompt = try? String(contentsOf: file, encoding: .utf8)
                }
                definition.hasPrompt = FileManager.default.fileExists(atPath: file.path)
                return definition
            }
    }

    private func listPatientAgentDefinitions(
        patientId: String,
        baseDir: URL,
        includePrompts: Bool
    ) -> [AgentDefinition] {
        let patientDir = baseDir.appendingPathComponent("patients").appendingPathComponent(patientId)
        guard FileManager.default.fileExists(atPath: patientDir.path) else { return [] }

        var definitions: [AgentDefinition] = []
        let careAgentPath = patientDir.appendingPathComponent("care-agent.md")
        if FileManager.default.fileExists(atPath: careAgentPath.path) {
            var careAgent = makeAgentDefinition(
                id: "\(patientId):care-agent",
                title: "Care Agent",
                source: "patient",
                category: "care-agent",
                purpose: "Agente operacional do paciente \(patientId).",
                runtimePolicy: "llm-runtime",
                tools: ["run_patient_agent"],
                path: careAgentPath.path,
                patientId: patientId
            )
            careAgent.hasPrompt = true
            if includePrompts {
                careAgent.prompt = try? String(contentsOf: careAgentPath, encoding: .utf8)
            }
            definitions.append(careAgent)
        }

        let agentsDir = patientDir.appendingPathComponent("agents")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        for file in files where file.pathExtension.lowercased() == "md" {
            let agentId = file.deletingPathExtension().lastPathComponent
            var definition = makeAgentDefinition(
                id: "\(patientId):\(agentId)",
                title: agentId.readableAgentTitle(),
                source: "patient",
                category: "patient-agent",
                purpose: "Agente declarativo do paciente \(patientId).",
                runtimePolicy: "llm-runtime",
                tools: ["run_patient_agent"],
                path: file.path,
                patientId: patientId
            )
            definition.hasPrompt = true
            if includePrompts {
                definition.prompt = try? String(contentsOf: file, encoding: .utf8)
            }
            definitions.append(definition)
        }
        return definitions
    }

    private func resolvePatientId(_ rawId: String, baseDir: URL) -> String? {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let directPath = baseDir.appendingPathComponent("patients").appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: directPath.path) {
            return trimmed
        }

        let manager = WorkspaceManager(baseDir: baseDir)
        try? manager.loadAllPatients()
        let normalized = trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "pt_BR")
        ).lowercased()
        return manager.patients.first { profile in
            let names = ([profile.patientId, profile.patientName, profile.identity?.fullName] + (profile.aliases ?? []))
                .compactMap { $0 }
            return names.contains { candidate in
                candidate.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "pt_BR")
                ).lowercased() == normalized
            }
        }?.patientId
    }
}

private extension AgentRegistry {
    static let systemAgentDefinitions: [AgentDefinition] = [
        makeAgentDefinition(
            id: "conversation-agent",
            title: "ConversationAgent",
            source: "system",
            category: "orchestration",
            purpose: "Receber a intenção do usuário, manter posse da resposta final e coordenar especialistas.",
            runtimePolicy: "llm-runtime",
            tools: ["agent-router", "event-writer"]
        ),
        makeAgentDefinition(
            id: "context-agent",
            title: "ContextAgent",
            source: "system",
            category: "governance",
            purpose: "Montar contexto profissional, paciente, sessão e artefatos por referência.",
            runtimePolicy: "deterministic",
            tools: ["professional_context", "patient_context", "artifact_refs"]
        ),
        makeAgentDefinition(
            id: "tool-runner-agent",
            title: "ToolRunnerAgent",
            source: "system",
            category: "execution",
            purpose: "Planejar execução local de subprocessos, pipeline stages e tools com trace.",
            runtimePolicy: "deterministic",
            tools: ["run_pipeline", "run_codex_subagent"]
        ),
        makeAgentDefinition(
            id: "transcription-agent",
            title: "TranscriptionAgent",
            source: "system",
            category: "pipeline",
            purpose: "Executar ou revisar a etapa de transcrição de áudio.",
            runtimePolicy: "deterministic",
            tools: ["transcribe"]
        ),
        makeAgentDefinition(
            id: "session-structuring-agent",
            title: "SessionStructuringAgent",
            source: "system",
            category: "pipeline",
            purpose: "Estruturar transcrições em sessões e dossiês canônicos.",
            runtimePolicy: "llm-runtime",
            tools: ["pipeline:process"]
        ),
        makeAgentDefinition(
            id: "speech-attribution-agent",
            title: "SpeechAttributionAgent",
            source: "system",
            category: "pipeline",
            purpose: "Extrair e conferir falas do paciente.",
            runtimePolicy: "llm-runtime",
            tools: ["pipeline:speech"]
        ),
        makeAgentDefinition(
            id: "asl-agent",
            title: "ASLAgent",
            source: "system",
            category: "pipeline",
            purpose: "Gerar ou revisar Análise Sistêmica Linguística.",
            runtimePolicy: "llm-runtime",
            tools: ["pipeline:asl"]
        ),
        makeAgentDefinition(
            id: "vdlp-agent",
            title: "VDLPAgent",
            source: "system",
            category: "pipeline",
            purpose: "Gerar ou revisar vetores/dimensões do espaço mental.",
            runtimePolicy: "llm-runtime",
            tools: ["pipeline:vdlp"]
        ),
        makeAgentDefinition(
            id: "gem-agent",
            title: "GEMAgent",
            source: "system",
            category: "pipeline",
            purpose: "Gerar ou revisar o Grafo do Espaço-Campo Mental.",
            runtimePolicy: "llm-runtime",
            tools: ["pipeline:gem"]
        ),
        makeAgentDefinition(
            id: "patient-care-agent",
            title: "PatientCareAgent",
            source: "system",
            category: "clinical",
            purpose: "Responder tarefas clínico-operacionais de um paciente usando seu dossiê.",
            runtimePolicy: "llm-runtime",
            tools: ["run_patient_agent"]
        ),
        makeAgentDefinition(
            id: "risk-check-agent",
            title: "RiskCheckAgent",
            source: "system",
            category: "clinical-safety",
            purpose: "Checar risco clínico com evidência direta e incerteza explícita.",
            runtimePolicy: "llm-runtime",
            tools: ["run_patient_agent:risk-check"]
        ),
        makeAgentDefinition(
            id: "session-prep-agent",
            title: "SessionPrepAgent",
            source: "system",
            category: "clinical",
            purpose: "Preparar próxima sessão com perguntas, lacunas e temas prioritários.",
            runtimePolicy: "llm-runtime",
            tools: ["run_patient_agent:session-prep"]
        ),
        makeAgentDefinition(
            id: "longitudinal-reviewer-agent",
            title: "LongitudinalReviewerAgent",
            source: "system",
            category: "clinical",
            purpose: "Cruzar sessões, memória e análises para revisão longitudinal.",
            runtimePolicy: "llm-runtime",
            tools: ["run_patient_agent:longitudinal-reviewer"]
        ),
        makeAgentDefinition(
            id: "safety-review-agent",
            title: "SafetyReviewAgent",
            source: "system",
            category: "clinical-safety",
            purpose: "Revisar segurança clínica, LGPD, overclaim e evidências antes de responder.",
            runtimePolicy: "llm-runtime",
            tools: ["safety_review", "responsible_ai"]
        ),
        makeAgentDefinition(
            id: "memory-agent",
            title: "MemoryAgent",
            source: "system",
            category: "memory",
            purpose: "Propor ou gravar memória somente quando houver pedido explícito.",
            runtimePolicy: "deterministic",
            tools: ["memory_policy", "/remember"]
        ),
        makeAgentDefinition(
            id: "qa-agent",
            title: "QAAgent",
            source: "system",
            category: "qa",
            purpose: "Validar schemas, eventos, regressão CLI e outputs dos agentes.",
            runtimePolicy: "deterministic",
            tools: ["swift_test", "smoke_validation"]
        ),
    ]

    static func healthOSAgentDefinitions(
        includeScenario: Bool,
        includePrompts: Bool
    ) -> [AgentDefinition] {
        healthOSAgentCatalog
            .filter { includeScenario || $0.availability == .active }
            .map { entry in
                var definition = makeAgentDefinition(
                    id: entry.id,
                    title: entry.title,
                    source: "healthos",
                    category: entry.category,
                    purpose: entry.purpose,
                    runtimePolicy: "llm-runtime",
                    tools: ["prompt-injection"]
                )
                definition.hasPrompt = true
                if includePrompts {
                    definition.prompt = entry.prompt
                }
                return definition
            }
    }
}

private enum HealthOSAgentAvailability: String, Sendable {
    case active
    case scenario
}

private struct HealthOSAgentCatalogEntry: Sendable {
    let id: String
    let title: String
    let category: String
    let availability: HealthOSAgentAvailability
    let purpose: String
    let prompt: String
}

private let healthOSAgentCatalog: [HealthOSAgentCatalogEntry] = [
    HealthOSAgentCatalogEntry(
        id: "context-architect",
        title: "Context Architect",
        category: "governance",
        availability: .active,
        purpose: "Mapear contexto profissional, paciente, sessão e artefatos antes de acionar análise ou execução.",
        prompt: "Organize o contexto em referências verificáveis, explicite lacunas e recomende o próximo agente ou estágio do pipeline. Não invente dados ausentes."
    ),
    HealthOSAgentCatalogEntry(
        id: "pipeline-operator",
        title: "Pipeline Operator",
        category: "pipeline",
        availability: .active,
        purpose: "Executar e revisar etapas transcribe, process, speech, ASL, VDLP e GEM com rastreabilidade.",
        prompt: "Atue como operador técnico do pipeline HealthOS. Preserve arquivos existentes, relate comandos, entradas, saídas e erros. Use Codex local quando a tarefa exigir subprocesso ou edição."
    ),
    HealthOSAgentCatalogEntry(
        id: "clinical-synthesizer",
        title: "Clinical Synthesizer",
        category: "clinical",
        availability: .active,
        purpose: "Sintetizar achados clínicos a partir de dossiê, ASL, VDLP, GEM, memória e histórico longitudinal.",
        prompt: "Produza sínteses clínicas com evidência explícita, incerteza proporcional e linguagem útil para o profissional. Não extrapole para além dos dados carregados."
    ),
    HealthOSAgentCatalogEntry(
        id: "risk-safety-reviewer",
        title: "Risk Safety Reviewer",
        category: "clinical-safety",
        availability: .active,
        purpose: "Revisar risco clínico, privacidade, LGPD, overclaim e segurança da resposta.",
        prompt: "Revise a resposta com foco em segurança clínica, limites de evidência, privacidade e conduta responsável. Aponte lacunas e reformule quando necessário."
    ),
    HealthOSAgentCatalogEntry(
        id: "patient-agent-builder",
        title: "Patient Agent Builder",
        category: "patient-agents",
        availability: .scenario,
        purpose: "Criar ou revisar agentes declarativos específicos de paciente em care-agent.md e patients/<PAT_ID>/agents.",
        prompt: "Construa agentes de paciente com escopo estreito, instruções clínicas prudentes, referências ao dossiê e regras de privacidade. Evite memória implícita."
    ),
    HealthOSAgentCatalogEntry(
        id: "qa-validator",
        title: "QA Validator",
        category: "qa",
        availability: .active,
        purpose: "Validar schemas, outputs, CLI, app Swift e regressões depois de mudanças.",
        prompt: "Priorize falhas reproduzíveis, erros de build, imports quebrados, schemas inválidos e regressões de UX. Sugira correções pequenas e verificáveis."
    ),
]

private func makeAgentDefinition(
    id: String,
    title: String,
    source: String,
    category: String,
    purpose: String,
    runtimePolicy: String,
    tools: [String],
    path: String? = nil,
    patientId: String? = nil
) -> AgentDefinition {
    var definition = AgentDefinition(
        id: id,
        title: title,
        source: source,
        category: category,
        purpose: purpose
    )
    definition.runtimePolicy = runtimePolicy
    definition.tools = tools
    definition.path = path
    definition.patientId = patientId
    definition.hasPrompt = false
    return definition
}

private extension String {
    func readableAgentTitle() -> String {
        split(separator: "-")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}
