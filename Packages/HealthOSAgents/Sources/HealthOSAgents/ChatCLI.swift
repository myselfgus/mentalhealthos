import Foundation
import HealthOSCore
import HealthOSPipeline

// MARK: - SYSTEM PROMPT Generation

public func buildProfessionalContext(manager: WorkspaceManager) throws -> String {
    try manager.loadActiveProfessional()
    let prof = manager.activeProfessional
    let mem = try manager.loadProfessionalMemory()
    
    var lines = ["## Profissional ativo"]
    if let prof = prof {
        lines.append("- Nome: \(prof.nome)")
        lines.append("- Registro: \(prof.registro)")
        let ws = ProfessionalWorkspace(id: prof.id, baseDir: manager.baseDir)
        lines.append("- Workspace: \(ws.dir.path)")
        if let dc = prof.disambiguationContext {
            lines.append("- Contexto de desambiguação: \(dc)")
        }
        
        let fileManager = FileManager.default
        let chatAgentPath = ws.chatAgentPath
        if fileManager.fileExists(atPath: chatAgentPath.path) {
            let chatAgent = try String(contentsOf: chatAgentPath, encoding: .utf8)
            lines.append("\n## Perfil conversacional do profissional\n\n\(chatAgent)")
        }
    } else {
        return "Nenhum profissional ativo configurado."
    }
    
    if let memory = mem {
        lines.append("\n## Memória do profissional\n\n\(memory)")
    }
    
    return lines.joined(separator: "\n")
}

public func buildActivePatientContext(manager: WorkspaceManager, activePatientId: String?) throws -> String {
    guard let activePatientId = activePatientId else {
        return "Nenhum paciente fixado para este chat."
    }
    
    let profile = try manager.loadPatientProfile(activePatientId)
    let workspace = manager.patientsDir.appendingPathComponent(activePatientId)
    
    var lines = [
        "## Paciente ativo do chat",
        "- Patient ID: \(activePatientId)"
    ]
    
    if let profile = profile {
        let name = profile.identity?.fullName ?? profile.patientName ?? activePatientId
        lines.append("- Nome: \(name)")
    } else {
        lines.append("- Nome: \(activePatientId)")
    }
    lines.append("- Workspace: \(workspace.path)")
    
    var sessionRows: [String] = []
    if let profile = profile {
        lines.append("- Sessoes: \(profile.sessions.count)")
        for session in profile.sessions {
            let ws = manager.sessionWorkspace(patientId: activePatientId, sessionId: session.id)
            var flags: [String] = []
            if FileManager.default.fileExists(atPath: ws.transcriptionPath.path) { flags.append("transcription") }
            if FileManager.default.fileExists(atPath: ws.patientSpeechTextPath.path) || FileManager.default.fileExists(atPath: ws.patientSpeechMarkdownPath.path) { flags.append("patient-speech") }
            if FileManager.default.fileExists(atPath: ws.aslPath.path) { flags.append("ASL") }
            if FileManager.default.fileExists(atPath: ws.vdlpPath.path) { flags.append("VDLP") }
            if FileManager.default.fileExists(atPath: ws.gemPath.path) { flags.append("GEM") }
            let flagsStr = flags.isEmpty ? "sem artefatos" : flags.joined(separator: ", ")
            sessionRows.append("- \(session.id): \(flagsStr)")
        }
    } else {
        lines.append("- Sessoes: 0")
    }
    
    if !sessionRows.isEmpty {
        lines.append("\n## Sessoes do paciente\n" + sessionRows.joined(separator: "\n"))
    }
    
    if let profile = profile {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let profileData = try encoder.encode(profile)
        let profileStr = String(data: profileData, encoding: .utf8) ?? ""
        lines.append("\n## patient.json\n\n\(String(profileStr.prefix(60_000)))")
    }
    
    let careAgentPath = workspace.appendingPathComponent("care-agent.md")
    if FileManager.default.fileExists(atPath: careAgentPath.path) {
        let careAgent = try String(contentsOf: careAgentPath, encoding: .utf8)
        lines.append("\n## care-agent.md\n\n\(String(careAgent.prefix(20_000)))")
    }
    
    return lines.joined(separator: "\n")
}

public func generateSystemPrompt(manager: WorkspaceManager, activePatientId: String?) throws -> String {
    let profContext = try buildProfessionalContext(manager: manager)
    let patientContext = try buildActivePatientContext(manager: manager, activePatientId: activePatientId)
    let baseDir = manager.baseDir.path
    
    return """
    Você é o assistente clínico integrado do HealthOS — um sistema de inteligência clínica para psiquiatria.

    \(profContext)

    \(patientContext)

    ## Seu papel

    Você é simultaneamente:
    1. **Assistente clínico** — interpreta dados de pacientes, análises linguísticas (ASL), dimensões do espaço mental (VDLP), e grafos mentais (GEM)
    2. **Operador do sistema** — executa pipeline stages, gerencia dossiês, edita configurações
    3. **Desenvolvedor** — lê, edita e cria arquivos do sistema HealthOS

    Você tem acesso completo ao filesystem via Read, Write, Edit, Bash, Glob, Grep. Use-os livremente.

    ## Arquitetura HealthOS

    Pipeline de 6 estágios:
    1. **Transcrição** — Áudio → ElevenLabs Scribe → JSON com diarização
    2. **Processamento** — Runtime LLM selecionado extrai metadados e organiza em dossiês
    3. **ASL** — Análise Sistêmica Linguística (8 domínios psicolinguísticos)
    4. **VDLP** — 15 Dimensões do Espaço Mental ℳ (meta-afetiva, meta-cognitiva, meta-linguística)
    5. **GEM** — Grafo do Espaço-Campo Mental (camadas .aje, .ire, .e, .epe)
    6. **Narrativa** — Narrativa fenomenológica multi-agente

    ## Estrutura de dados

    ```
    \(baseDir)/
    ├── patients/                    # Dossiês de pacientes
    │   └── PAT_000001/
    │       ├── patient.json         # Identidade e metadados do paciente
    │       ├── memory.md            # Memória clínica explícita
    │       ├── care-agent.md        # Perfil operacional do caso
    │       ├── agents/              # Subagentes específicos do paciente
    │       └── sessions/
    │           └── C1/
    │               ├── session.json
    │               ├── source/transcription.json
    │               └── analysis/
    │                   ├── patient-speech.*
    │                   ├── asl.json
    │                   ├── vdlp.json
    │                   └── gem.json
    ├── audio/transcriptions/        # Transcrições brutas
    ├── prompts/                     # Prompts de referência
    └── src/                         # Código-fonte do sistema
    ```

    ## Diretrizes

    - Responda sempre em português brasileiro
    - Ao apresentar dados clínicos, seja preciso e use terminologia adequada
    - Para operações destrutivas (deletar, sobrescrever), confirme antes de executar
    - Ao analisar dados de pacientes, conecte achados entre ASL/VDLP/GEM quando possível
    - Se houver Paciente ativo do chat, trate esse paciente como contexto padrão para perguntas clínicas e operações de dossiê, salvo pedido explícito em contrário
    - Mantenha tom profissional mas acessível — você conversa com o Dr. Gustavo
    - Use as ferramentas built-in (Read, Write, Edit, Bash, Glob, Grep) para operações no filesystem
    - Use as custom tools (list_patients, search_content, run_pipeline) para operações clínicas
    """
}

// MARK: - MCP Tools

public struct MCPTool: Sendable {
    public let name: String
    public let description: String
    
    // We omit dictionary for Sendable and simply define schema in code or as string if needed,
    // but the requirement asks to define matching TypeScript schemas.
    // So we can define them as struct types matching the JSON schema.
    public let parametersSchema: String?
    
    public init(name: String, description: String, parametersSchema: String? = nil) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
    }
}

public let healthOSTools: [MCPTool] = [
    MCPTool(
        name: "list_patients",
        description: "Lista todos os pacientes com contagem de arquivos por estágio do pipeline (transcrições, ASL, VDLP, GEM). Visão geral rápida do sistema."
    ),
    MCPTool(
        name: "search_content",
        description: "Busca texto em arquivos de pacientes ou em todo o sistema. Útil para encontrar menções a medicamentos, sintomas, temas recorrentes, palavras-chave clínicas.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "query": { "type": "string", "description": "Texto a buscar (case-insensitive)" },
            "patient_id": { "type": "string", "description": "Filtrar por paciente (ex: PAT_000001)" },
            "file_type": { "type": "string", "enum": ["json", "md", "txt", "all"], "description": "Tipo de arquivo (default: all)" }
          },
          "required": ["query"]
        }
        """
    ),
    MCPTool(
        name: "run_pipeline",
        description: "Executa um estágio do pipeline HealthOS. Estágios: process, speech, asl, vdlp, gem.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "stage": { "type": "string", "enum": ["process", "speech", "asl", "vdlp", "gem"], "description": "Estágio do pipeline" }
          },
          "required": ["stage"]
        }
        """
    ),
    MCPTool(
        name: "run_agent_workflow",
        description: "Executa um workflow multiagente completo: ContextAgent monta referencias, especialista executa, SafetyReviewAgent revisa quando clinico, e tudo gera eventos.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "input": { "type": "string", "description": "Intencao/tarefa conversacional do usuario" },
            "patient_id": { "type": "string", "description": "Paciente alvo; se omitido, usa o paciente ativo do chat quando houver" },
            "session_id": { "type": "string", "description": "Sessao especifica opcional" },
            "stage": { "type": "string", "enum": ["process", "speech", "asl", "vdlp", "gem"], "description": "Forca workflow de pipeline em um estagio" },
            "review": { "type": "boolean", "description": "Forca ou desliga revisao clinica; default segue a politica do workflow" }
          },
          "required": ["input"]
        }
        """
    ),
    MCPTool(
        name: "list_healthos_agents",
        description: "Lista agentes do projeto HealthOS definidos em src/agents para arquitetura, seguranca, documentacao, planejamento, pesquisa, implementacao e QA.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "includeScenario": { "type": "boolean", "description": "Inclui agentes de uso apenas em cenarios especificos" }
          }
        }
        """
    ),
    MCPTool(
        name: "list_agent_definitions",
        description: "Lista o registry multiagente completo: agentes internos do sistema, agentes HealthOS, subagentes Codex e agentes de paciente quando informado.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "includeScenario": { "type": "boolean", "description": "Inclui agentes HealthOS de cenario especifico" },
            "includeCodex": { "type": "boolean", "description": "Inclui subagentes Codex instalados localmente" },
            "patient_id": { "type": "string", "description": "Inclui agentes declarativos de um paciente" }
          }
        }
        """
    ),
    MCPTool(
        name: "list_patient_agents",
        description: "Lista care-agent.md e agentes markdown em patients/<PAT_ID>/agents para um paciente.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "patient_id": { "type": "string", "description": "Patient ID canonico ou nome do paciente" }
          },
          "required": ["patient_id"]
        }
        """
    ),
    MCPTool(
        name: "run_patient_agent",
        description: "Executa um agente de paciente usando src/lib/llm/runtime.ts, respeitando HEALTHOS_LLM_RUNTIME/HEALTHOS_CHAT_RUNTIME.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "patient_id": { "type": "string", "description": "Patient ID canonico ou nome do paciente" },
            "task": { "type": "string", "description": "Tarefa objetiva para o agente do paciente" },
            "agent_id": { "type": "string", "description": "Agente em patients/<PAT_ID>/agents sem .md; default: care-agent" }
          },
          "required": ["patient_id", "task"]
        }
        """
    ),
    MCPTool(
        name: "list_codex_agents",
        description: "Lista subagentes Codex instalados em ~/.codex/agents para delegacao local com a configuracao Codex do usuario."
    ),
    MCPTool(
        name: "run_codex_subagent",
        description: "Delega uma tarefa para um subprocesso Codex local, podendo especializar com agente HealthOS em src/agents ou subagente Codex em ~/.codex/agents.",
        parametersSchema: """
        {
          "type": "object",
          "properties": {
            "task": { "type": "string", "description": "Tarefa objetiva para o subagente Codex executar" },
            "agent": { "type": "string", "description": "ID opcional de agente HealthOS ou subagente Codex, sem .toml" }
          },
          "required": ["task"]
        }
        """
    )
]

// MARK: - CLI Implementation

public struct Colors {
    public static let cyan = "\\u{001B}[36m"
    public static let green = "\\u{001B}[32m"
    public static let blue = "\\u{001B}[34m"
    public static let magenta = "\\u{001B}[35m"
    public static let dim = "\\u{001B}[2m"
    public static let bold = "\\u{001B}[1m"
    public static let yellow = "\\u{001B}[33m"
    public static let red = "\\u{001B}[31m"
    public static let reset = "\\u{001B}[0m"
}

public func terminalWidth() -> Int {
    return 88
}

public func rule(char: String = "-") -> String {
    return String(repeating: char, count: terminalWidth())
}

public func padRight(_ text: String, width: Int) -> String {
    if text.count >= width {
        return String(text.prefix(width))
    }
    return text + String(repeating: " ", count: width - text.count)
}

public func badge(_ label: String, color: String = Colors.cyan) -> String {
    return "\(color)\(Colors.bold) \(label) \(Colors.reset)"
}

public func printLine(label: String, value: String, color: String = Colors.dim) {
    print("\(color)\(padRight(label, width: 14))\(Colors.reset)\(value)")
}

public func printHeader(runtime: String, manager: WorkspaceManager, activePatientId: String?) {
    print("")
    let badgeColor = runtime == "codex" ? Colors.magenta : Colors.cyan
    print("\(Colors.bold)\(Colors.cyan)HealthOS Chat CLI\(Colors.reset) \(badge(runtime.uppercased(), color: badgeColor))")
    print("\(Colors.dim)\(rule())\(Colors.reset)")
    
    let runtimeStr = runtime == "codex" ? "Codex local via ChatGPT login + ~/.codex" : "Claude Code Agent SDK + HealthOS MCP tools"
    printLine(label: "runtime", value: runtimeStr)
    
    if let prof = manager.activeProfessional {
        printLine(label: "professional", value: "\(prof.nome) (\(prof.registro))")
        let ws = ProfessionalWorkspace(id: prof.id, baseDir: manager.baseDir)
        printLine(label: "prof. memory", value: ws.memoryPath.path)
        printLine(label: "chat agent", value: ws.chatAgentPath.path)
    } else {
        printLine(label: "professional", value: "n/a")
        printLine(label: "prof. memory", value: "n/a")
        printLine(label: "chat agent", value: "n/a")
    }
    
    if let pid = activePatientId, let profile = try? manager.loadPatientProfile(pid) {
        let name = profile.identity?.fullName ?? profile.patientName ?? pid
        printLine(label: "patient", value: "\(pid) \(name)")
    } else {
        if let pid = activePatientId {
            printLine(label: "patient", value: "\(pid)")
        } else {
            printLine(label: "patient", value: "n/a")
        }
    }
    
    printLine(label: "workspace", value: manager.baseDir.path)
    printLine(label: "patients", value: manager.patientsDir.path)
    printLine(label: "codex", value: "ok")
    print("\(Colors.dim)\(rule())\(Colors.reset)")
    print("\(Colors.dim)Comandos: /help, /runtime claude|codex, /agents, /status, /clear, /quit\(Colors.reset)\\n")
}

public func printHelp(runtime: String, manager: WorkspaceManager, activePatientId: String?) {
    print("\\n\(Colors.bold)\(Colors.cyan)Comandos\(Colors.reset)")
    print("  /runtime claude       usar Claude Code Agent SDK")
    print("  /runtime codex        usar Codex local com ~/.codex")
    print("  /agents               listar subagentes Codex instalados")
    print("  /agent                mostrar perfil conversacional do profissional")
    print("  /memory               mostrar memória do profissional")
    print("  /remember texto       salvar memória explícita do profissional")
    print("  /status               mostrar runtime, paths e auth")
    print("  /clear                redesenhar a tela")
    print("  /quit                 sair")
    
    print("\\n\(Colors.bold)\(Colors.cyan)Exemplos\(Colors.reset)")
    print("  lista meus pacientes")
    print("  busca sertralina em todos os pacientes")
    print("  roda ASL")
    print("  prepara a proxima sessao deste paciente")
    print("  checa risco clinico deste caso")
    print("  use o subagente context-architect para mapear este refactor")
    
    print("\\n\(Colors.dim)Runtime atual: \(runtime)\(Colors.reset)\\n")
    if let pid = activePatientId, let profile = try? manager.loadPatientProfile(pid) {
        let name = profile.identity?.fullName ?? profile.patientName ?? pid
        print("\(Colors.dim)Paciente ativo: \(pid) \(name)\(Colors.reset)\\n")
    }
}

public func printAgents() {
    print("\\n\(Colors.bold)\(Colors.cyan)Agentes internos multiagent\(Colors.reset)")
    print("  \(Colors.bold)conversation-agent\(Colors.reset) \(Colors.dim)conversation · Orquestrador de conversas\(Colors.reset)")
    
    print("\\n\(Colors.bold)\(Colors.magenta)Agentes HealthOS\(Colors.reset)")
    print("  \(Colors.bold)patient-care-agent\(Colors.reset) \(Colors.dim)clinical · Agente clinico geral\(Colors.reset)")
    
    print("\\n\(Colors.bold)\(Colors.magenta)Subagentes Codex instalados\(Colors.reset)")
    print("  (mocked list of codex agents)")
    print("")
}
