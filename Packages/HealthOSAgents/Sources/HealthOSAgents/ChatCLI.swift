import Foundation
import HealthOSCore
import HealthOSPipeline

// MARK: - SYSTEM PROMPT Generation

public func buildProfessionalContext(manager: WorkspaceManager) throws -> String {
    try ChatContextBuilder(manager: manager).renderProfessionalContext()
}

public func buildActivePatientContext(manager: WorkspaceManager, activePatientId: String?) throws -> String {
    try ChatContextBuilder(manager: manager).renderPatientContext(activePatientId: activePatientId)
}

public func generateSystemPrompt(manager: WorkspaceManager, activePatientId: String?) throws -> String {
    try ChatContextBuilder(manager: manager).renderSystemPrompt(activePatientId: activePatientId)
}

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
    
    let runtimeStr = runtime == "codex"
        ? "Codex local via ChatGPT login + ~/.codex"
        : "Swift local agents + configured LLMProvider when available"
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

public func printAgents(registry: AgentRegistry = .shared) {
    let definitions = registry.listAgentDefinitions()
    let systemAgents = definitions.filter { $0.source == "system" }
    let healthOSAgents = definitions.filter { $0.source == "healthos" }
    let codexAgents = definitions.filter { $0.source == "codex" }

    print("\\n\(Colors.bold)\(Colors.cyan)Agentes internos multiagent\(Colors.reset)")
    for agent in systemAgents {
        let category = agent.category ?? "uncategorized"
        let purpose = agent.purpose ?? ""
        print("  \(Colors.bold)\(agent.id)\(Colors.reset) \(Colors.dim)\(category) · \(purpose)\(Colors.reset)")
    }
    
    print("\\n\(Colors.bold)\(Colors.magenta)Agentes HealthOS\(Colors.reset)")
    for agent in healthOSAgents {
        let category = agent.category ?? "uncategorized"
        let purpose = agent.purpose ?? ""
        print("  \(Colors.bold)\(agent.id)\(Colors.reset) \(Colors.dim)\(category) · \(purpose)\(Colors.reset)")
    }
    
    print("\\n\(Colors.bold)\(Colors.magenta)Subagentes Codex instalados\(Colors.reset)")
    if codexAgents.isEmpty {
        print("  \(Colors.dim)(nenhum subagente Codex local encontrado em ~/.codex/agents)\(Colors.reset)")
    } else {
        for agent in codexAgents {
            print("  \(Colors.bold)\(agent.id)\(Colors.reset) \(Colors.dim)\(agent.path ?? "")\(Colors.reset)")
        }
    }
    print("")
}
