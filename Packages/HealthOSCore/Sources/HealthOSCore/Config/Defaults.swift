import Foundation

// MARK: - HealthOS Defaults

/// Centralized Swift-native configuration constants.
public enum HealthOSDefaults {

    /// Characters per token estimate for LLM input planning.
    public static let charsPerToken = 4

    /// Default timeout values in seconds.
    public enum Timeouts {
        public static let short: TimeInterval = 30
        public static let medium: TimeInterval = 120
        public static let long: TimeInterval = 300
        public static let extraLong: TimeInterval = 600

        public static func forOperation(_ op: PipelineStage) -> TimeInterval {
            switch op {
            case .transcribe: medium
            case .process: medium
            case .speech: medium
            case .asl: long
            case .vdlp: long
            case .gem: extraLong
            }
        }
    }

    /// LLM temperature presets.
    public enum Temperature {
        public static let extraction: Double = 0.1
        public static let analysis: Double = 0.3
        public static let narrative: Double = 0.7
    }

    /// Retry configuration for LLM calls.
    public enum Retry {
        public static let maxAttempts = 3
        public static let baseDelayMs = 2000
        public static let rateLimitDelayMs = 10_000
    }

    /// Prompt caching configuration.
    public enum Cache {
        public static let extendedTTL = "1h"
    }

    /// Canonical directory and file names.
    public enum FileNames {
        public static let patientProfile = "patient.json"
        public static let memory = "memory.md"
        public static let careAgent = "care-agent.md"
        public static let professionalConfig = "professional-config.json"
        public static let activeProfessional = "active-professional.json"
        public static let transcription = "transcription.json"
        public static let patientSpeechText = "patient-speech.txt"
        public static let patientSpeechJson = "patient-speech.json"
        public static let patientSpeechMd = "patient-speech.md"
        public static let asl = "asl.json"
        public static let vdlp = "vdlp.json"
        public static let gem = "gem.json"
    }
}

// MARK: - Pipeline Stage

/// The 6 pipeline stages in canonical order.
public enum PipelineStage: String, Codable, CaseIterable, Sendable {
    case transcribe
    case process
    case speech
    case asl
    case vdlp
    case gem

    /// Stable native identifier used by Swift pipeline contracts.
    public var nativeIdentifier: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .transcribe: "Transcrição"
        case .process: "Processamento"
        case .speech: "Fala do Paciente"
        case .asl: "ASL"
        case .vdlp: "VDLP"
        case .gem: "GEM"
        }
    }

    public var systemImage: String {
        switch self {
        case .transcribe: "waveform"
        case .process: "doc.text.magnifyingglass"
        case .speech: "person.wave.2"
        case .asl: "text.magnifyingglass"
        case .vdlp: "chart.dots.scatter"
        case .gem: "brain.head.profile"
        }
    }

    public var nativeCommand: PipelineStageCommand {
        PipelineStageCommand(
            executable: "swift",
            arguments: ["run", "HealthOSCLI", "pipeline", nativeIdentifier]
        )
    }

    /// Stage index (0-based).
    public var index: Int {
        PipelineStage.allCases.firstIndex(of: self)!
    }
}

/// Executable command metadata for a pipeline stage.
public struct PipelineStageCommand: Codable, Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var components: [String] {
        [executable] + arguments
    }

    public var shellString: String {
        components.joined(separator: " ")
    }
}

// MARK: - LLM Runtime Names

/// Available LLM runtime backends.
public enum LLMRuntimeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case claudeCode = "ClaudeCode"
    case claudeAPI = "ClaudeAPI"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .claudeAPI: "Claude API"
        }
    }

    public var cliName: String {
        switch self {
        case .codex: "codex"
        case .claudeCode: "claude"
        case .claudeAPI: "claude-api"
        }
    }

    public var selectionHint: String {
        switch self {
        case .codex:
            "Codex CLI local via login ChatGPT e ~/.codex."
        case .claudeCode:
            "Claude Code CLI local via comando claude."
        case .claudeAPI:
            "Anthropic Messages API via ANTHROPIC_API_KEY."
        }
    }

    public var isLocalCLI: Bool {
        switch self {
        case .codex, .claudeCode: true
        case .claudeAPI: false
        }
    }

    public static let fallbackRuntime: LLMRuntimeType = .codex
    public static var defaultRuntime: LLMRuntimeType {
        LLMRuntimePreference.resolve()
    }

    public init?(preferenceValue value: String?) {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "codex", "codex-cli", "codexrunner", "codex-runner":
            self = .codex
        case "claude", "claude-code", "claudecode", "claude-cli", "claude-code-cli":
            self = .claudeCode
        case "claude-api", "claudeapi", "anthropic", "anthropic-api":
            self = .claudeAPI
        default:
            return nil
        }
    }
}
