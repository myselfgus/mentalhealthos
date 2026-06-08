import Foundation

// MARK: - Professional Configuration

/// Professional workspace configuration — maps to `professional-config.json`.
public struct ProfessionalConfig: Codable, Identifiable, Sendable {
    public var id: String
    public var nome: String
    public var registro: String
    public var disambiguationContext: String?
    public var lastUpdated: String

    enum CodingKeys: String, CodingKey {
        case id, nome, registro
        case disambiguationContext = "disambiguation_context"
        case lastUpdated = "last_updated"
    }

    public init(id: String, nome: String, registro: String, disambiguationContext: String? = nil) {
        self.id = id
        self.nome = nome
        self.registro = registro
        self.disambiguationContext = disambiguationContext
        self.lastUpdated = ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - Professional Workspace Paths

/// Resolved filesystem paths for a professional workspace.
public struct ProfessionalWorkspace: Sendable {
    public let id: String
    public let dir: URL
    public let configPath: URL
    public let memoryPath: URL
    public let chatAgentPath: URL
    public let logsDir: URL
    public let telemetryDir: URL
    public let sessionsDir: URL
    public let artifactsDir: URL

    public init(id: String, baseDir: URL) {
        self.id = id
        let profDir = baseDir.appendingPathComponent("professionals")
            .appendingPathComponent(id)
        self.dir = profDir
        self.configPath = profDir.appendingPathComponent("professional-config.json")
        self.memoryPath = profDir.appendingPathComponent("memory.md")
        self.chatAgentPath = profDir.appendingPathComponent("chat-agent.md")
        self.logsDir = profDir.appendingPathComponent("logs")
        self.telemetryDir = profDir.appendingPathComponent("telemetry")
        self.sessionsDir = profDir.appendingPathComponent("sessions")
        self.artifactsDir = profDir.appendingPathComponent("artifacts")
    }
}

// MARK: - Active Professional

/// Pointer to the currently active professional — maps to `active-professional.json`.
public struct ActiveProfessional: Codable, Sendable {
    public var activeProfessionalId: String

    enum CodingKeys: String, CodingKey {
        case activeProfessionalId = "active_professional_id"
    }
}
