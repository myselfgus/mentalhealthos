import Foundation
import HealthOSCore

public enum HealthOSWorkspaceLocator {
    public static func detectBaseDirectory(
        startingAt start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL {
        if let envBase = ProcessInfo.processInfo.environment["HEALTHOS_BASE"], !envBase.isEmpty {
            return URL(fileURLWithPath: envBase)
        }

        var current = start
        for _ in 0..<8 {
            let swiftPackage = current.appendingPathComponent("Package.swift")
            let corePackage = current.appendingPathComponent("Packages/HealthOSCore/Package.swift")
            let patients = current.appendingPathComponent("patients")
            let professionals = current.appendingPathComponent("professionals")
            if FileManager.default.fileExists(atPath: swiftPackage.path) ||
                FileManager.default.fileExists(atPath: corePackage.path) ||
                FileManager.default.fileExists(atPath: patients.path) ||
                FileManager.default.fileExists(atPath: professionals.path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("mentalhealthos")
    }
}

public struct ProfessionalChatContext: Codable, Sendable {
    public let id: String
    public let name: String
    public let registro: String
    public let workspacePath: String
    public let disambiguationContext: String?
    public let chatAgentPath: String?
    public let chatAgent: String?
    public let memoryPath: String?
    public let memory: String?
}

public struct SessionArtifactFlags: Codable, Sendable {
    public let transcription: Bool
    public let patientSpeech: Bool
    public let asl: Bool
    public let vdlp: Bool
    public let gem: Bool

    public var labels: [String] {
        var values: [String] = []
        if transcription { values.append("transcription") }
        if patientSpeech { values.append("patient-speech") }
        if asl { values.append("ASL") }
        if vdlp { values.append("VDLP") }
        if gem { values.append("GEM") }
        return values
    }
}

public struct PatientSessionChatContext: Codable, Sendable {
    public let id: String
    public let path: String
    public let artifactFlags: SessionArtifactFlags
}

public struct PatientChatContext: Codable, Sendable {
    public let patientId: String
    public let displayName: String
    public let workspacePath: String
    public let sessionCount: Int
    public let sessions: [PatientSessionChatContext]
    public let patientJSON: String?
    public let memoryPath: String?
    public let memory: String?
    public let careAgentPath: String?
    public let careAgent: String?
    public let exists: Bool
}

public struct ChatContextSnapshot: Codable, Sendable {
    public let baseDir: String
    public let professional: ProfessionalChatContext?
    public let patient: PatientChatContext?
    public let inputRefs: [String]
}

public struct ChatContextBuilder: Sendable {
    public let manager: WorkspaceManager

    public init(manager: WorkspaceManager) {
        self.manager = manager
    }

    public func buildSnapshot(activePatientId: String? = nil, sessionId: String? = nil) throws -> ChatContextSnapshot {
        let professional = try buildProfessional()
        let patient = try buildPatient(activePatientId: activePatientId, sessionId: sessionId)
        let inputRefs = collectContextReferences(activePatientId: activePatientId, sessionId: sessionId)
        return ChatContextSnapshot(
            baseDir: manager.baseDir.path,
            professional: professional,
            patient: patient,
            inputRefs: inputRefs
        )
    }

    public func renderProfessionalContext() throws -> String {
        guard let professional = try buildProfessional() else {
            return "Nenhum profissional ativo configurado."
        }

        var lines = [
            "## Profissional ativo",
            "- Nome: \(professional.name)",
            "- Registro: \(professional.registro)",
            "- Workspace: \(professional.workspacePath)",
        ]
        if let disambiguationContext = professional.disambiguationContext {
            lines.append("- Contexto de desambiguacao: \(disambiguationContext)")
        }
        if let chatAgent = professional.chatAgent {
            lines.append("\n## Perfil conversacional do profissional\n\n\(chatAgent)")
        }
        if let memory = professional.memory {
            lines.append("\n## Memoria do profissional\n\n\(memory)")
        }
        return lines.joined(separator: "\n")
    }

    public func renderPatientContext(activePatientId: String?, sessionId: String? = nil) throws -> String {
        guard let patient = try buildPatient(activePatientId: activePatientId, sessionId: sessionId) else {
            return "Nenhum paciente fixado para este chat."
        }

        var lines = [
            "## Paciente ativo do chat",
            "- Patient ID: \(patient.patientId)",
            "- Nome: \(patient.displayName)",
            "- Workspace: \(patient.workspacePath)",
            "- Sessoes: \(patient.sessionCount)",
        ]
        if !patient.exists {
            lines.append("- Estado: patient.json nao encontrado")
        }

        if !patient.sessions.isEmpty {
            let rows = patient.sessions.map { session in
                let flags = session.artifactFlags.labels.isEmpty
                    ? "sem artefatos"
                    : session.artifactFlags.labels.joined(separator: ", ")
                return "- \(session.id): \(flags)"
            }
            lines.append("\n## Sessoes do paciente\n" + rows.joined(separator: "\n"))
        }

        if let patientJSON = patient.patientJSON {
            lines.append("\n## patient.json\n\n\(String(patientJSON.prefix(60_000)))")
        }
        if let memory = patient.memory {
            lines.append("\n## memory.md\n\n\(String(memory.prefix(20_000)))")
        }
        if let careAgent = patient.careAgent {
            lines.append("\n## care-agent.md\n\n\(String(careAgent.prefix(20_000)))")
        }

        return lines.joined(separator: "\n")
    }

    public func renderSystemPrompt(activePatientId: String?, sessionId: String? = nil) throws -> String {
        let professionalContext = try renderProfessionalContext()
        let patientContext = try renderPatientContext(activePatientId: activePatientId, sessionId: sessionId)
        let baseDir = manager.baseDir.path

        return """
        Voce e o assistente clinico integrado do HealthOS, um sistema local de inteligencia clinica para psiquiatria.

        \(professionalContext)

        \(patientContext)

        ## Papel local

        Voce ajuda o profissional a navegar o workspace, planejar workflows de agentes, interpretar artefatos ja existentes e preparar proximas execucoes.
        Nao invente achados clinicos, diagnosticos, risco, medicacao ou resultados de ASL/VDLP/GEM ausentes.
        Se o runtime LLM ou executor local necessario nao estiver configurado, retorne um erro estruturado de configuracao em vez de uma resposta clinica simulada.

        ## Arquitetura HealthOS

        Pipeline de 6 estagios:
        1. Transcricao - audio para JSON com diarizacao
        2. Processamento - metadados e dossies canonicos
        3. ASL - Analise Sistemica Linguistica
        4. VDLP - Vetores/Dimensoes da Linguagem-Pensamento
        5. GEM - Grafo do Espaco-Campo Mental
        6. Narrativa - sintese fenomenologica multiagente

        ## Estrutura de dados

        ```
        \(baseDir)/
        |-- patients/
        |   `-- PAT_000001/
        |       |-- patient.json
        |       |-- memory.md
        |       |-- care-agent.md
        |       |-- agents/
        |       `-- sessions/
        |           `-- C1/
        |               |-- session.json
        |               |-- source/transcription.json
        |               `-- analysis/
        |                   |-- patient-speech.*
        |                   |-- asl.json
        |                   |-- vdlp.json
        |                   `-- gem.json
        |-- audio/transcriptions/
        |-- prompts/
        `-- Packages/
        ```

        ## Diretrizes

        - Responda em portugues brasileiro.
        - Trate o paciente ativo como contexto padrao quando existir, salvo pedido explicito em contrario.
        - Use evidencia direta de arquivos carregados; marque lacunas e incertezas.
        - Para operacoes destrutivas, exija confirmacao explicita.
        - Use apenas descritores e executores locais deste runtime Swift.
        """
    }

    public func collectContextReferences(activePatientId: String?, sessionId: String? = nil) -> [String] {
        var refs: [String] = []
        if let professional = manager.activeProfessional {
            let workspace = ProfessionalWorkspace(id: professional.id, baseDir: manager.baseDir)
            refs.appendIfExists(workspace.configPath)
            refs.appendIfExists(workspace.memoryPath)
            refs.appendIfExists(workspace.chatAgentPath)
        }

        guard let activePatientId else { return refs }
        let patientDir = manager.patientsDir.appendingPathComponent(activePatientId)
        refs.appendIfExists(patientDir.appendingPathComponent("patient.json"))
        refs.appendIfExists(patientDir.appendingPathComponent("memory.md"))
        refs.appendIfExists(patientDir.appendingPathComponent("care-agent.md"))

        let sessionIds: [String]
        if let sessionId {
            sessionIds = [sessionId]
        } else if let profile = try? manager.loadPatientProfile(activePatientId) {
            sessionIds = profile.sessions.map(\.id)
        } else {
            sessionIds = []
        }

        for sessionId in sessionIds {
            let workspace = manager.sessionWorkspace(patientId: activePatientId, sessionId: sessionId)
            refs.appendIfExists(workspace.sessionPath)
            refs.appendIfExists(workspace.transcriptionPath)
            refs.appendIfExists(workspace.patientSpeechTextPath)
            refs.appendIfExists(workspace.patientSpeechMarkdownPath)
            refs.appendIfExists(workspace.aslPath)
            refs.appendIfExists(workspace.vdlpPath)
            refs.appendIfExists(workspace.gemPath)
        }

        return Array(Set(refs)).sorted()
    }

    private func buildProfessional() throws -> ProfessionalChatContext? {
        try manager.loadActiveProfessional()
        guard let professional = manager.activeProfessional else { return nil }
        let workspace = ProfessionalWorkspace(id: professional.id, baseDir: manager.baseDir)
        let chatAgent = readStringIfExists(workspace.chatAgentPath)
        let memory = try manager.loadProfessionalMemory()
        return ProfessionalChatContext(
            id: professional.id,
            name: professional.nome,
            registro: professional.registro,
            workspacePath: workspace.dir.path,
            disambiguationContext: professional.disambiguationContext,
            chatAgentPath: FileManager.default.fileExists(atPath: workspace.chatAgentPath.path) ? workspace.chatAgentPath.path : nil,
            chatAgent: chatAgent,
            memoryPath: FileManager.default.fileExists(atPath: workspace.memoryPath.path) ? workspace.memoryPath.path : nil,
            memory: memory
        )
    }

    private func buildPatient(activePatientId: String?, sessionId: String?) throws -> PatientChatContext? {
        guard let activePatientId else { return nil }
        let patientDir = manager.patientsDir.appendingPathComponent(activePatientId)
        let profile = try manager.loadPatientProfile(activePatientId)
        let sessions = try buildSessionContexts(profile: profile, patientId: activePatientId, sessionId: sessionId)
        let patientJSONPath = patientDir.appendingPathComponent("patient.json")
        let memoryPath = patientDir.appendingPathComponent("memory.md")
        let careAgentPath = patientDir.appendingPathComponent("care-agent.md")

        return PatientChatContext(
            patientId: activePatientId,
            displayName: profile?.displayName ?? activePatientId,
            workspacePath: patientDir.path,
            sessionCount: profile?.sessions.count ?? 0,
            sessions: sessions,
            patientJSON: readStringIfExists(patientJSONPath),
            memoryPath: FileManager.default.fileExists(atPath: memoryPath.path) ? memoryPath.path : nil,
            memory: readStringIfExists(memoryPath),
            careAgentPath: FileManager.default.fileExists(atPath: careAgentPath.path) ? careAgentPath.path : nil,
            careAgent: readStringIfExists(careAgentPath),
            exists: profile != nil
        )
    }

    private func buildSessionContexts(
        profile: PatientProfile?,
        patientId: String,
        sessionId: String?
    ) throws -> [PatientSessionChatContext] {
        let sessionIds: [String]
        if let sessionId {
            sessionIds = [sessionId]
        } else {
            sessionIds = profile?.sessions.map(\.id) ?? []
        }

        return sessionIds.map { id in
            let workspace = manager.sessionWorkspace(patientId: patientId, sessionId: id)
            let flags = SessionArtifactFlags(
                transcription: FileManager.default.fileExists(atPath: workspace.transcriptionPath.path),
                patientSpeech: FileManager.default.fileExists(atPath: workspace.patientSpeechTextPath.path) ||
                    FileManager.default.fileExists(atPath: workspace.patientSpeechMarkdownPath.path),
                asl: FileManager.default.fileExists(atPath: workspace.aslPath.path),
                vdlp: FileManager.default.fileExists(atPath: workspace.vdlpPath.path),
                gem: FileManager.default.fileExists(atPath: workspace.gemPath.path)
            )
            return PatientSessionChatContext(
                id: id,
                path: workspace.dir.path,
                artifactFlags: flags
            )
        }
    }

    private func readStringIfExists(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

private extension Array where Element == String {
    mutating func appendIfExists(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            append(url.path)
        }
    }
}
