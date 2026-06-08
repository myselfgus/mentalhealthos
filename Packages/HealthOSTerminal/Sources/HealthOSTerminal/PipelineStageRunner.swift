import Foundation
import HealthOSCore
import HealthOSPipeline

// MARK: - Pipeline Stage Runner

public struct TerminalPipelineExecutionContext: Sendable {
    public let workspaceManager: WorkspaceManager
    public let runtime: LLMRuntimeType
    public let environment: [String: String]

    public init(
        workspaceManager: WorkspaceManager,
        runtime: LLMRuntimeType,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.workspaceManager = workspaceManager
        self.runtime = runtime
        self.environment = environment
    }
}

public struct PipelineExecutionResult: Sendable {
    public let stage: PipelineStage
    public let message: String
    public let outputRefs: [String]

    public init(stage: PipelineStage, message: String, outputRefs: [String] = []) {
        self.stage = stage
        self.message = message
        self.outputRefs = outputRefs
    }
}

public protocol PipelineStageRunning: Sendable {
    func run(stage: PipelineStage, context: TerminalPipelineExecutionContext) async throws -> PipelineExecutionResult
}

public enum PipelineStageRunnerError: Error, LocalizedError, Sendable {
    case nativeEngineUnavailable(stage: PipelineStage)
    case noSessions(stage: PipelineStage)

    public var errorDescription: String? {
        switch self {
        case .nativeEngineUnavailable(let stage):
            return "Etapa \(stage.displayName) ainda nao possui runner Swift nativo conectado. Conecte uma implementacao de PipelineStageRunning ao PipelineEngine quando ele estiver disponivel."
        case .noSessions(let stage):
            return "Etapa \(stage.displayName) nao encontrou sessoes no workspace atual."
        }
    }
}

public actor NativePipelineEngineRunner: PipelineStageRunning {
    private let engine: PipelineEngine

    public init(engine: PipelineEngine = PipelineEngine()) {
        self.engine = engine
    }

    public func run(stage: PipelineStage, context: TerminalPipelineExecutionContext) async throws -> PipelineExecutionResult {
        let provider = try? LLMRuntimeProviderFactory.makeProvider(
            for: context.runtime,
            baseDir: context.workspaceManager.baseDir,
            environment: context.environment
        )
        let transcriptionProvider = try? OpenAITranscriptionProvider(apiKey: context.environment["OPENAI_API_KEY"])
        let targets = context.workspaceManager.patients.flatMap { patient in
            patient.sessions
                .filter { !$0.status.isComplete(stage) }
                .map { (patient.patientId, $0.sessionId) }
        }

        guard !targets.isEmpty else {
            throw PipelineStageRunnerError.noSessions(stage: stage)
        }

        var outputRefs: [String] = []
        var failures: [String] = []
        var completed = 0
        var skipped = 0

        for (patientId, sessionId) in targets {
            let result = await engine.run(
                stage: stage,
                baseDir: context.workspaceManager.baseDir,
                patientId: patientId,
                sessionId: sessionId,
                provider: provider,
                transcriptionProvider: transcriptionProvider
            )

            outputRefs.append(contentsOf: result.artifacts.map(\.path))
            switch result.status {
            case .completed:
                completed += 1
            case .skipped:
                skipped += 1
            case .failed:
                failures.append("\(patientId)/\(sessionId): \(result.message)")
            }
        }

        try? context.workspaceManager.loadAllPatients()

        let summary = [
            "\(completed) concluidas",
            "\(skipped) puladas",
            "\(failures.count) falhas"
        ].joined(separator: ", ")

        if failures.isEmpty {
            return PipelineExecutionResult(
                stage: stage,
                message: "\(stage.displayName): \(summary).",
                outputRefs: outputRefs
            )
        }

        return PipelineExecutionResult(
            stage: stage,
            message: "\(stage.displayName): \(summary).\n" + failures.joined(separator: "\n"),
            outputRefs: outputRefs
        )
    }
}

@available(*, deprecated, renamed: "NativePipelineEngineRunner")
public actor PendingPipelineEngineRunner: PipelineStageRunning {
    public init() {}

    public func run(stage: PipelineStage, context: TerminalPipelineExecutionContext) async throws -> PipelineExecutionResult {
        throw PipelineStageRunnerError.nativeEngineUnavailable(stage: stage)
    }
}
