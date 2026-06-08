import Foundation
import HealthOSCore

public enum PipelineStageRunStatus: String, Codable, Sendable {
    case completed
    case skipped
    case failed
}

public struct PipelineArtifactRef: Codable, Sendable, Equatable {
    public var kind: PatientArtifactKind
    public var path: String
    public var format: String

    public init(kind: PatientArtifactKind, path: String, format: String) {
        self.kind = kind
        self.path = path
        self.format = format
    }
}

public struct PipelineStageErrorInfo: Codable, Sendable, Equatable {
    public var code: String
    public var stage: PipelineStage
    public var message: String
    public var details: String?
    public var recoverable: Bool

    public init(
        code: String,
        stage: PipelineStage,
        message: String,
        details: String? = nil,
        recoverable: Bool = true
    ) {
        self.code = code
        self.stage = stage
        self.message = message
        self.details = details
        self.recoverable = recoverable
    }
}

public struct PipelineStageResult: Codable, Sendable, Equatable {
    public var stage: PipelineStage
    public var status: PipelineStageRunStatus
    public var message: String
    public var startedAt: String
    public var finishedAt: String
    public var artifacts: [PipelineArtifactRef]
    public var providerName: String?
    public var error: PipelineStageErrorInfo?

    public init(
        stage: PipelineStage,
        status: PipelineStageRunStatus,
        message: String,
        startedAt: String,
        finishedAt: String,
        artifacts: [PipelineArtifactRef] = [],
        providerName: String? = nil,
        error: PipelineStageErrorInfo? = nil
    ) {
        self.stage = stage
        self.status = status
        self.message = message
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.artifacts = artifacts
        self.providerName = providerName
        self.error = error
    }

    public var succeeded: Bool {
        status == .completed || status == .skipped
    }
}

public struct PipelineExecutionSummary: Codable, Sendable, Equatable {
    public var results: [PipelineStageResult]

    public init(results: [PipelineStageResult]) {
        self.results = results
    }

    public var succeeded: Bool {
        results.allSatisfy(\.succeeded)
    }

    public var failedStages: [PipelineStage] {
        results.compactMap { $0.status == .failed ? $0.stage : nil }
    }
}

public struct PipelineExecutionOptions: Sendable, Equatable {
    public var overwriteExisting: Bool
    public var continueOnFailure: Bool
    public var chunkTargetTokens: Int
    public var chunkMaxTokens: Int
    public var chunkOverlapTokens: Int
    public var maxOutputTokens: Int?

    public init(
        overwriteExisting: Bool = false,
        continueOnFailure: Bool = false,
        chunkTargetTokens: Int = ClinicalChunking.defaultTargetTokens,
        chunkMaxTokens: Int = 2400,
        chunkOverlapTokens: Int = 180,
        maxOutputTokens: Int? = nil
    ) {
        self.overwriteExisting = overwriteExisting
        self.continueOnFailure = continueOnFailure
        self.chunkTargetTokens = chunkTargetTokens
        self.chunkMaxTokens = chunkMaxTokens
        self.chunkOverlapTokens = chunkOverlapTokens
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct PipelineExecutionContext: Sendable {
    public let baseDir: URL
    public let patientId: String
    public let sessionId: String
    public let provider: (any LLMProvider)?
    public let transcriptionProvider: (any TranscriptionProvider)?
    public let options: PipelineExecutionOptions

    public init(
        baseDir: URL,
        patientId: String,
        sessionId: String,
        provider: (any LLMProvider)? = nil,
        transcriptionProvider: (any TranscriptionProvider)? = nil,
        options: PipelineExecutionOptions = PipelineExecutionOptions()
    ) {
        self.baseDir = baseDir
        self.patientId = patientId
        self.sessionId = sessionId
        self.provider = provider
        self.transcriptionProvider = transcriptionProvider
        self.options = options
    }

    public var session: PatientSessionWorkspace {
        PatientSessionWorkspace(
            patientId: patientId,
            sessionId: sessionId,
            patientsBaseDir: baseDir.appendingPathComponent("patients")
        )
    }
}

public protocol PipelineStageRunner: Sendable {
    var stage: PipelineStage { get }
    func run(context: PipelineExecutionContext) async -> PipelineStageResult
}

enum PipelineClock {
    static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

extension PipelineStageResult {
    static func completed(
        stage: PipelineStage,
        startedAt: String,
        message: String,
        artifacts: [PipelineArtifactRef] = [],
        providerName: String? = nil
    ) -> PipelineStageResult {
        PipelineStageResult(
            stage: stage,
            status: .completed,
            message: message,
            startedAt: startedAt,
            finishedAt: PipelineClock.now(),
            artifacts: artifacts,
            providerName: providerName
        )
    }

    static func skipped(
        stage: PipelineStage,
        startedAt: String,
        message: String,
        artifacts: [PipelineArtifactRef] = []
    ) -> PipelineStageResult {
        PipelineStageResult(
            stage: stage,
            status: .skipped,
            message: message,
            startedAt: startedAt,
            finishedAt: PipelineClock.now(),
            artifacts: artifacts
        )
    }

    static func failed(
        stage: PipelineStage,
        startedAt: String,
        error: PipelineStageErrorInfo,
        providerName: String? = nil
    ) -> PipelineStageResult {
        PipelineStageResult(
            stage: stage,
            status: .failed,
            message: error.message,
            startedAt: startedAt,
            finishedAt: PipelineClock.now(),
            providerName: providerName,
            error: error
        )
    }
}

extension PipelineStageErrorInfo {
    static func missingProvider(stage: PipelineStage, reason: String) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "missing_provider",
            stage: stage,
            message: "Stage \(stage.rawValue) requires an LLM provider.",
            details: reason,
            recoverable: true
        )
    }

    static func missingArtifact(stage: PipelineStage, path: URL, purpose: String) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "missing_artifact",
            stage: stage,
            message: "Required artifact is missing for stage \(stage.rawValue).",
            details: "\(purpose): \(path.path)",
            recoverable: true
        )
    }

    static func unsupported(stage: PipelineStage, details: String) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "unsupported_native_stage",
            stage: stage,
            message: "Stage \(stage.rawValue) is not implemented as a deterministic native runner.",
            details: details,
            recoverable: true
        )
    }

    static func missingSTTProvider(stage: PipelineStage, audioFiles: [URL]) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "missing_stt_provider",
            stage: stage,
            message: "Stage \(stage.rawValue) found session audio but no STT provider is configured.",
            details: "Audio aguardando STT: \(audioFiles.map(\.lastPathComponent).joined(separator: ", "))",
            recoverable: true
        )
    }

    static func validation(stage: PipelineStage, details: String) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "validation_failed",
            stage: stage,
            message: "Stage \(stage.rawValue) produced JSON that failed clinical contract validation.",
            details: details,
            recoverable: true
        )
    }

    static func io(stage: PipelineStage, error: Error) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "io_error",
            stage: stage,
            message: "Stage \(stage.rawValue) could not read or write its artifacts.",
            details: String(describing: error),
            recoverable: true
        )
    }

    static func llm(stage: PipelineStage, error: Error) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "llm_error",
            stage: stage,
            message: "Stage \(stage.rawValue) failed during LLM execution.",
            details: String(describing: error),
            recoverable: true
        )
    }

    static func transcription(stage: PipelineStage, error: Error) -> PipelineStageErrorInfo {
        PipelineStageErrorInfo(
            code: "stt_error",
            stage: stage,
            message: "Stage \(stage.rawValue) failed during native speech-to-text execution.",
            details: String(describing: error),
            recoverable: true
        )
    }
}
