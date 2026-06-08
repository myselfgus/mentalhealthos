import Foundation

// MARK: - Session Index

/// Session entry in the patient profile — maps to `sessions[]` in `patient.json`.
public struct PatientSessionIndex: Codable, Identifiable, Sendable {
    public var id: String { sessionId }

    public let sessionId: String
    public var sessionNumber: Int?
    public var date: String?
    public var sourceFile: String?
    public var sourceSlug: String?
    public var tags: [String]?
    public var path: String?
    public var processedAt: String?
    public var status: SessionPipelineStatus
    public var artifacts: [PatientArtifactIndex]?
    public var clinicalDelta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionNumber = "session_number"
        case date
        case sourceFile = "source_file"
        case sourceSlug = "source_slug"
        case tags, path
        case processedAt = "processed_at"
        case status, artifacts
        case clinicalDelta = "clinical_delta"
    }
}

// MARK: - Pipeline Status

/// Status of each pipeline stage for a session.
public struct SessionPipelineStatus: Codable, Sendable {
    public var audio: Bool
    public var transcription: Bool
    public var patientSpeech: Bool
    public var asl: Bool
    public var vdlp: Bool
    public var gem: Bool

    enum CodingKeys: String, CodingKey {
        case audio, transcription
        case patientSpeech = "patient_speech"
        case asl, vdlp, gem
    }

    public init(
        audio: Bool = false,
        transcription: Bool = false,
        patientSpeech: Bool = false,
        asl: Bool = false,
        vdlp: Bool = false,
        gem: Bool = false
    ) {
        self.audio = audio
        self.transcription = transcription
        self.patientSpeech = patientSpeech
        self.asl = asl
        self.vdlp = vdlp
        self.gem = gem
    }

    /// Number of completed stages (0–6).
    public var completedCount: Int {
        [audio, transcription, patientSpeech, asl, vdlp, gem].filter(\.self).count
    }

    /// Fraction completed (0.0–1.0).
    public var progress: Double {
        Double(completedCount) / 6.0
    }
}

// MARK: - Artifact Index

/// Artifact entry in the patient profile — maps to `artifacts[]`.
public struct PatientArtifactIndex: Codable, Identifiable, Sendable {
    public var id: String { artifactId }

    public let artifactId: String
    public let kind: PatientArtifactKind
    public var sessionId: String?
    public var path: String
    public var format: String?
    public var source: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case kind
        case sessionId = "session_id"
        case path, format, source
        case createdAt = "created_at"
    }
}

public enum PatientArtifactKind: String, Codable, Sendable {
    case audio
    case transcription
    case patientSpeech = "patient_speech"
    case asl
    case vdlp
    case gem
    case clinicalDocument = "clinical_document"
    case source
    case other
}

// MARK: - Session Workspace Paths

/// Resolved filesystem paths for a patient session workspace.
public struct PatientSessionWorkspace: Sendable {
    public let id: String
    public let patientId: String
    public let patientDir: URL
    public let dir: URL
    public let sessionPath: URL
    public let sourceDir: URL
    public let audioDir: URL
    public let analysisDir: URL
    public let documentsDir: URL
    public let artifactsDir: URL
    public let logsDir: URL
    public let transcriptionPath: URL
    public let patientSpeechTextPath: URL
    public let patientSpeechJsonPath: URL
    public let patientSpeechMarkdownPath: URL
    public let aslPath: URL
    public let vdlpPath: URL
    public let gemPath: URL

    public init(patientId: String, sessionId: String, patientsBaseDir: URL) {
        self.id = sessionId
        self.patientId = patientId
        let patDir = patientsBaseDir.appendingPathComponent(patientId)
        self.patientDir = patDir
        let sessDir = patDir.appendingPathComponent("sessions").appendingPathComponent(sessionId)
        self.dir = sessDir
        self.sessionPath = sessDir.appendingPathComponent("session.json")
        self.sourceDir = sessDir.appendingPathComponent("source")
        self.audioDir = sourceDir.appendingPathComponent("audio")
        self.analysisDir = sessDir.appendingPathComponent("analysis")
        self.documentsDir = sessDir.appendingPathComponent("documents")
        self.artifactsDir = sessDir.appendingPathComponent("artifacts")
        self.logsDir = sessDir.appendingPathComponent("logs")
        self.transcriptionPath = sourceDir.appendingPathComponent("transcription.json")
        self.patientSpeechTextPath = analysisDir.appendingPathComponent("patient-speech.txt")
        self.patientSpeechJsonPath = analysisDir.appendingPathComponent("patient-speech.json")
        self.patientSpeechMarkdownPath = analysisDir.appendingPathComponent("patient-speech.md")
        self.aslPath = analysisDir.appendingPathComponent("asl.json")
        self.vdlpPath = analysisDir.appendingPathComponent("vdlp.json")
        self.gemPath = analysisDir.appendingPathComponent("gem.json")
    }
}
