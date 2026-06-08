import Foundation

public struct LocalToolDescriptor: Codable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let description: String
    public let parameters: LocalToolSchema?
    public let transport: LocalToolTransport

    public init(
        name: String,
        description: String,
        parameters: LocalToolSchema? = nil,
        transport: LocalToolTransport = .localSwift
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.transport = transport
    }

    public var parametersSchema: String? {
        guard let parameters else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(parameters) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum LocalToolTransport: String, Codable, Sendable {
    case localSwift = "local_swift"
}

public struct LocalToolSchema: Codable, Sendable {
    public let type: String
    public let properties: [String: LocalToolParameter]
    public let required: [String]
    public let additionalProperties: Bool

    public init(
        properties: [String: LocalToolParameter],
        required: [String] = [],
        additionalProperties: Bool = false
    ) {
        self.type = "object"
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    enum CodingKeys: String, CodingKey {
        case type, properties, required
        case additionalProperties
    }
}

public struct LocalToolParameter: Codable, Sendable {
    public let type: String
    public let description: String
    public let enumValues: [String]?
    public let defaultValue: String?

    public init(
        type: String,
        description: String,
        enumValues: [String]? = nil,
        defaultValue: String? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.defaultValue = defaultValue
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
        case defaultValue = "default"
    }
}

public let healthOSTools: [LocalToolDescriptor] = [
    LocalToolDescriptor(
        name: "list_patients",
        description: "Lista pacientes locais e o estado de artefatos por estágio do pipeline."
    ),
    LocalToolDescriptor(
        name: "search_content",
        description: "Busca texto em arquivos locais de pacientes ou no workspace HealthOS.",
        parameters: LocalToolSchema(
            properties: [
                "query": LocalToolParameter(
                    type: "string",
                    description: "Texto a buscar, sem diferenciar maiúsculas/minúsculas."
                ),
                "patient_id": LocalToolParameter(
                    type: "string",
                    description: "Filtra por paciente, por exemplo PAT_000001."
                ),
                "file_type": LocalToolParameter(
                    type: "string",
                    description: "Tipo de arquivo a considerar.",
                    enumValues: ["json", "md", "txt", "all"],
                    defaultValue: "all"
                ),
            ],
            required: ["query"]
        )
    ),
    LocalToolDescriptor(
        name: "run_pipeline",
        description: "Descreve a execução local de um estágio do pipeline; requer executor Swift/CLI configurado.",
        parameters: LocalToolSchema(
            properties: [
                "stage": LocalToolParameter(
                    type: "string",
                    description: "Estágio do pipeline.",
                    enumValues: PipelineWorkflowStage.allCases.map(\.rawValue)
                ),
                "patient_id": LocalToolParameter(
                    type: "string",
                    description: "Paciente alvo quando o estágio exigir escopo clínico."
                ),
                "session_id": LocalToolParameter(
                    type: "string",
                    description: "Sessão específica opcional."
                ),
            ],
            required: ["stage"]
        )
    ),
    LocalToolDescriptor(
        name: "plan_agent_workflow",
        description: "Detecta e planeja o workflow multiagente local sem gerar saída clínica.",
        parameters: LocalToolSchema(
            properties: [
                "input": LocalToolParameter(
                    type: "string",
                    description: "Intenção ou tarefa conversacional do usuário."
                ),
                "patient_id": LocalToolParameter(
                    type: "string",
                    description: "Paciente alvo; se omitido, usa o paciente ativo quando houver."
                ),
                "session_id": LocalToolParameter(
                    type: "string",
                    description: "Sessão específica opcional."
                ),
                "stage": LocalToolParameter(
                    type: "string",
                    description: "Força workflow de pipeline em um estágio.",
                    enumValues: PipelineWorkflowStage.allCases.map(\.rawValue)
                ),
            ],
            required: ["input"]
        )
    ),
    LocalToolDescriptor(
        name: "list_healthos_agents",
        description: "Lista agentes HealthOS declarados no catálogo Swift local.",
        parameters: LocalToolSchema(
            properties: [
                "includeScenario": LocalToolParameter(
                    type: "boolean",
                    description: "Inclui agentes de uso apenas em cenários específicos."
                ),
                "includePrompts": LocalToolParameter(
                    type: "boolean",
                    description: "Inclui corpo dos prompts declarativos."
                ),
            ]
        )
    ),
    LocalToolDescriptor(
        name: "list_agent_definitions",
        description: "Lista o registry multiagente local: sistema, HealthOS, Codex e agentes de paciente.",
        parameters: LocalToolSchema(
            properties: [
                "includeScenario": LocalToolParameter(
                    type: "boolean",
                    description: "Inclui agentes HealthOS de cenário específico."
                ),
                "includeCodex": LocalToolParameter(
                    type: "boolean",
                    description: "Inclui subagentes Codex instalados localmente."
                ),
                "includePrompts": LocalToolParameter(
                    type: "boolean",
                    description: "Inclui prompts quando disponíveis."
                ),
                "patient_id": LocalToolParameter(
                    type: "string",
                    description: "Inclui agentes declarativos do paciente informado."
                ),
            ]
        )
    ),
    LocalToolDescriptor(
        name: "list_patient_agents",
        description: "Lista care-agent.md e agentes Markdown em patients/<PAT_ID>/agents.",
        parameters: LocalToolSchema(
            properties: [
                "patient_id": LocalToolParameter(
                    type: "string",
                    description: "Patient ID canônico ou nome resolvível."
                ),
                "includePrompts": LocalToolParameter(
                    type: "boolean",
                    description: "Inclui conteúdo dos agentes Markdown."
                ),
            ],
            required: ["patient_id"]
        )
    ),
    LocalToolDescriptor(
        name: "run_patient_agent",
        description: "Planeja execução de agente de paciente; geração clínica exige LLMProvider configurado.",
        parameters: LocalToolSchema(
            properties: [
                "patient_id": LocalToolParameter(
                    type: "string",
                    description: "Patient ID canônico ou nome resolvível."
                ),
                "task": LocalToolParameter(
                    type: "string",
                    description: "Tarefa objetiva para o agente do paciente."
                ),
                "agent_id": LocalToolParameter(
                    type: "string",
                    description: "Agente em patients/<PAT_ID>/agents sem .md; default: care-agent."
                ),
            ],
            required: ["patient_id", "task"]
        )
    ),
    LocalToolDescriptor(
        name: "list_codex_agents",
        description: "Lista subagentes Codex instalados em ~/.codex/agents para delegação local."
    ),
    LocalToolDescriptor(
        name: "run_codex_subagent",
        description: "Planeja delegação para subprocesso Codex local; execução exige runner configurado.",
        parameters: LocalToolSchema(
            properties: [
                "task": LocalToolParameter(
                    type: "string",
                    description: "Tarefa objetiva para o subagente Codex executar."
                ),
                "agent": LocalToolParameter(
                    type: "string",
                    description: "ID opcional de agente HealthOS ou subagente Codex, sem extensão."
                ),
            ],
            required: ["task"]
        )
    ),
]
