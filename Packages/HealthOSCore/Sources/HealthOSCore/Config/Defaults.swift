import Foundation

// MARK: - HealthOS Defaults

/// Centralized configuration constants — mirrors `src/config/defaults.ts`.
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
public enum PipelineStage: String, CaseIterable, Sendable {
    case transcribe
    case process
    case speech
    case asl
    case vdlp
    case gem

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

    public var npmScript: String {
        switch self {
        case .transcribe: "npm run transcribe"
        case .process: "npm run pipeline:process"
        case .speech: "npm run pipeline:speech"
        case .asl: "npm run pipeline:asl"
        case .vdlp: "npm run pipeline:vdlp"
        case .gem: "npm run pipeline:gem"
        }
    }

    /// Stage index (0-based).
    public var index: Int {
        PipelineStage.allCases.firstIndex(of: self)!
    }
}

// MARK: - LLM Runtime Names

/// Available LLM runtime backends.
public enum LLMRuntimeType: String, CaseIterable, Sendable {
    case claudeAPI = "ClaudeAPI"
    case claudeCode = "ClaudeCode"
    case codex = "Codex"

    public var displayName: String {
        switch self {
        case .claudeAPI: "Claude API"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}
