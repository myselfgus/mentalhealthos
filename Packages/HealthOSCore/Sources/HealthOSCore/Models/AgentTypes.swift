import Foundation

// MARK: - Agent Task

public typealias AgentTaskKind = String
public typealias AgentResultStatus = String
public typealias AgentEventKind = String
public typealias AgentRuntimeName = String
public typealias AgentSource = String

/// Intent/task routed to an agent.
public struct AgentTask: Codable, Identifiable, Sendable {
    public var id: String { taskId }

    public let taskId: String
    public let conversationId: String
    public let runId: String
    public var agentId: String
    public var kind: AgentTaskKind
    public var input: String
    public var inputRefs: [String]
    public var patientId: String?
    public var sessionId: String?
    public var requiresApproval: Bool
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case conversationId = "conversation_id"
        case runId = "run_id"
        case agentId = "agent_id"
        case kind, input
        case inputRefs = "input_refs"
        case patientId = "patient_id"
        case sessionId = "session_id"
        case requiresApproval = "requires_approval"
        case createdAt = "created_at"
    }
}

// MARK: - Agent Result

/// Output from an agent execution.
public struct AgentResult: Codable, Sendable {
    public var status: AgentResultStatus
    public var content: String?
    public var outputRefs: [String]?
    public var handoffTo: String?
    public var reviewRequired: Bool?
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case status, content
        case outputRefs = "output_refs"
        case handoffTo = "handoff_to"
        case reviewRequired = "review_required"
        case error
    }

    public init(status: String, content: String? = nil) {
        self.status = status
        self.content = content
    }
}

// MARK: - Agent Event (Telemetry)

/// Append-only event trace entry for agent execution.
public struct AgentEvent: Codable, Identifiable, Sendable {
    public var id: String { eventId }

    public let eventId: String
    public let runId: String
    public let conversationId: String
    public var taskId: String?
    public var parentEventId: String?
    public var agentId: String
    public var kind: AgentEventKind
    public var status: String
    public var patientId: String?
    public var sessionId: String?
    public var runtime: AgentRuntimeName?
    public var inputRefs: [String]?
    public var outputRefs: [String]?
    public var startedAt: String?
    public var endedAt: String?
    public var error: String?
    public var metadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case runId = "run_id"
        case conversationId = "conversation_id"
        case taskId = "task_id"
        case parentEventId = "parent_event_id"
        case agentId = "agent_id"
        case kind, status
        case patientId = "patient_id"
        case sessionId = "session_id"
        case runtime
        case inputRefs = "input_refs"
        case outputRefs = "output_refs"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case error, metadata
    }
}

// MARK: - Agent Definition

/// Declarative agent definition — used in registry and catalog.
public struct AgentDefinition: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var source: AgentSource
    public var category: String?
    public var purpose: String?
    public var runtimePolicy: String?
    public var tools: [String]?
    public var path: String?
    public var prompt: String?
    public var patientId: String?
    public var hasPrompt: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, source, category, purpose
        case runtimePolicy = "runtime_policy"
        case tools, path, prompt
        case patientId = "patient_id"
        case hasPrompt = "has_prompt"
    }

    public init(id: String, title: String, source: String, category: String? = nil, purpose: String? = nil) {
        self.id = id
        self.title = title
        self.source = source
        self.category = category
        self.purpose = purpose
    }
}

// MARK: - Chat Message (for Conversation UI)

/// A single message in a conversation.
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public var content: String
    public let timestamp: Date
    public var toolCalls: [ToolCallInfo]?
    public var isStreaming: Bool

    public init(
        role: ChatRole,
        content: String,
        toolCalls: [ToolCallInfo]? = nil,
        isStreaming: Bool = false
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.isStreaming = isStreaming
    }
}

public enum ChatRole: String, Sendable {
    case user
    case assistant
    case system
    case tool
}

public struct ToolCallInfo: Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public var arguments: String?
    public var result: String?
    public var status: ToolCallStatus

    public init(toolName: String, arguments: String? = nil) {
        self.id = UUID()
        self.toolName = toolName
        self.arguments = arguments
        self.status = .running
    }
}

public enum ToolCallStatus: String, Sendable {
    case running, completed, failed
}
