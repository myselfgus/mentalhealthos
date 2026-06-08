import Foundation
import HealthOSCore

public actor PipelineEngine {
    private let runners: [PipelineStage: any PipelineStageRunner]

    public init(runners: [any PipelineStageRunner] = PipelineEngine.defaultRunners()) {
        var indexed: [PipelineStage: any PipelineStageRunner] = [:]
        for runner in runners {
            indexed[runner.stage] = runner
        }
        self.runners = indexed
    }

    public static func defaultRunners() -> [any PipelineStageRunner] {
        [
            TranscriptionStageRunner(),
            ProcessStageRunner(),
            PatientSpeechStageRunner(),
            ASLStageRunner(),
            VDLPStageRunner(),
            GEMStageRunner(),
        ]
    }

    public func run(
        stage: PipelineStage,
        baseDir: URL,
        patientId: String,
        sessionId: String,
        provider: (any LLMProvider)? = nil,
        transcriptionProvider: (any TranscriptionProvider)? = nil,
        options: PipelineExecutionOptions = PipelineExecutionOptions()
    ) async -> PipelineStageResult {
        let context = PipelineExecutionContext(
            baseDir: baseDir,
            patientId: patientId,
            sessionId: sessionId,
            provider: provider,
            transcriptionProvider: transcriptionProvider,
            options: options
        )
        return await run(stage: stage, context: context)
    }

    public func run(
        stages: [PipelineStage],
        baseDir: URL,
        patientId: String,
        sessionId: String,
        provider: (any LLMProvider)? = nil,
        transcriptionProvider: (any TranscriptionProvider)? = nil,
        options: PipelineExecutionOptions = PipelineExecutionOptions()
    ) async -> PipelineExecutionSummary {
        let context = PipelineExecutionContext(
            baseDir: baseDir,
            patientId: patientId,
            sessionId: sessionId,
            provider: provider,
            transcriptionProvider: transcriptionProvider,
            options: options
        )

        var results: [PipelineStageResult] = []
        for stage in stages {
            let result = await run(stage: stage, context: context)
            results.append(result)
            if result.status == .failed && !options.continueOnFailure {
                break
            }
        }
        return PipelineExecutionSummary(results: results)
    }

    private func run(stage: PipelineStage, context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        guard let runner = runners[stage] else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .unsupported(stage: stage, details: "No PipelineStageRunner is registered for this stage.")
            )
        }

        return await runner.run(context: context)
    }
}
