import Foundation
import HealthOSCore

public struct ASLStageRunner: PipelineStageRunner {
    public let stage: PipelineStage = .asl

    public init() {}

    public func run(context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        let session = context.session

        if !context.options.overwriteExisting,
           let existing = PipelineArtifactIO.existingArtifact(
                kind: .asl,
                url: session.aslPath,
                format: "json",
                stage: stage,
                startedAt: startedAt
           ) {
            return existing
        }

        guard let provider = context.provider else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingProvider(
                    stage: stage,
                    reason: "ASL is a clinical linguistic analysis stage and cannot be generated deterministically."
                )
            )
        }

        do {
            let patientSpeech = try PipelineArtifactIO.loadPatientSpeech(from: session)
            let output = try await ClinicalLLMStageExecutor(provider: provider, context: context)
                .runASL(patientSpeech: patientSpeech)
            try ClinicalArtifactValidator.validateASL(data: output)
            try PipelineJSON.writePrettyObjectData(output, to: session.aslPath)

            return .completed(
                stage: stage,
                startedAt: startedAt,
                message: "ASL analysis generated through LLMProvider and validated against HealthOSCore.",
                artifacts: [
                    PipelineArtifactIO.artifact(kind: .asl, url: session.aslPath, format: "json")
                ],
                providerName: provider.name
            )
        } catch let error as ClinicalValidationError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: error.localizedDescription), providerName: provider.name)
        } catch let error as PipelineJSONError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: error.localizedDescription), providerName: provider.name)
        } catch let error as DecodingError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: String(describing: error)), providerName: provider.name)
        } catch let error as LLMError {
            return .failed(stage: stage, startedAt: startedAt, error: .llm(stage: stage, error: error), providerName: provider.name)
        } catch PipelineArtifactError.emptyPatientSpeech {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingArtifact(stage: stage, path: session.patientSpeechJsonPath, purpose: "Patient speech")
            )
        } catch {
            return .failed(stage: stage, startedAt: startedAt, error: .io(stage: stage, error: error), providerName: provider.name)
        }
    }
}

public struct VDLPStageRunner: PipelineStageRunner {
    public let stage: PipelineStage = .vdlp

    public init() {}

    public func run(context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        let session = context.session

        if !context.options.overwriteExisting,
           let existing = PipelineArtifactIO.existingArtifact(
                kind: .vdlp,
                url: session.vdlpPath,
                format: "json",
                stage: stage,
                startedAt: startedAt
           ) {
            return existing
        }

        guard let provider = context.provider else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingProvider(
                    stage: stage,
                    reason: "VDLP derives clinical dimensions from ASL and patient speech and requires an LLM provider."
                )
            )
        }

        guard FileManager.default.fileExists(atPath: session.aslPath.path) else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingArtifact(stage: stage, path: session.aslPath, purpose: "ASL analysis")
            )
        }

        do {
            let asl = try Data(contentsOf: session.aslPath)
            try ClinicalArtifactValidator.validateASL(data: asl)
            let patientSpeech = try PipelineArtifactIO.loadPatientSpeech(from: session)
            let output = try await ClinicalLLMStageExecutor(provider: provider, context: context)
                .runVDLP(asl: asl, patientSpeech: patientSpeech)
            try ClinicalArtifactValidator.validateVDLP(data: output)
            try PipelineJSON.writePrettyObjectData(output, to: session.vdlpPath)

            return .completed(
                stage: stage,
                startedAt: startedAt,
                message: "VDLP dimensions generated through LLMProvider and validated against HealthOSCore.",
                artifacts: [
                    PipelineArtifactIO.artifact(kind: .vdlp, url: session.vdlpPath, format: "json")
                ],
                providerName: provider.name
            )
        } catch let error as ClinicalValidationError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: error.localizedDescription), providerName: provider.name)
        } catch let error as PipelineJSONError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: error.localizedDescription), providerName: provider.name)
        } catch let error as DecodingError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: String(describing: error)), providerName: provider.name)
        } catch let error as LLMError {
            return .failed(stage: stage, startedAt: startedAt, error: .llm(stage: stage, error: error), providerName: provider.name)
        } catch PipelineArtifactError.emptyPatientSpeech {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingArtifact(stage: stage, path: session.patientSpeechJsonPath, purpose: "Patient speech")
            )
        } catch {
            return .failed(stage: stage, startedAt: startedAt, error: .io(stage: stage, error: error), providerName: provider.name)
        }
    }
}

public struct GEMStageRunner: PipelineStageRunner {
    public let stage: PipelineStage = .gem

    public init() {}

    public func run(context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        let session = context.session

        if !context.options.overwriteExisting,
           let existing = PipelineArtifactIO.existingArtifact(
                kind: .gem,
                url: session.gemPath,
                format: "json",
                stage: stage,
                startedAt: startedAt
           ) {
            return existing
        }

        guard let provider = context.provider else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingProvider(
                    stage: stage,
                    reason: "GEM is a clinical graph synthesis stage and requires an LLM provider."
                )
            )
        }

        for required in [
            (session.transcriptionPath, "Source transcription"),
            (session.aslPath, "ASL analysis"),
            (session.vdlpPath, "VDLP analysis"),
        ] where !FileManager.default.fileExists(atPath: required.0.path) {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingArtifact(stage: stage, path: required.0, purpose: required.1)
            )
        }

        do {
            let transcription = try PipelineArtifactIO.loadTranscription(from: session.transcriptionPath)
            guard let transcriptionText = transcription.preferredText else {
                return .failed(
                    stage: stage,
                    startedAt: startedAt,
                    error: .validation(stage: stage, details: "Transcription text is empty.")
                )
            }

            let asl = try Data(contentsOf: session.aslPath)
            let vdlp = try Data(contentsOf: session.vdlpPath)
            try ClinicalArtifactValidator.validateASL(data: asl)
            try ClinicalArtifactValidator.validateVDLP(data: vdlp)

            let output = try await ClinicalLLMStageExecutor(provider: provider, context: context)
                .runGEM(transcription: transcriptionText, asl: asl, vdlp: vdlp)
            try ClinicalArtifactValidator.validateGEM(data: output)
            try PipelineJSON.writePrettyObjectData(output, to: session.gemPath)

            return .completed(
                stage: stage,
                startedAt: startedAt,
                message: "GEM graph generated through LLMProvider and validated against HealthOSCore.",
                artifacts: [
                    PipelineArtifactIO.artifact(kind: .gem, url: session.gemPath, format: "json")
                ],
                providerName: provider.name
            )
        } catch let error as ClinicalValidationError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: error.localizedDescription), providerName: provider.name)
        } catch let error as PipelineJSONError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: error.localizedDescription), providerName: provider.name)
        } catch let error as DecodingError {
            return .failed(stage: stage, startedAt: startedAt, error: .validation(stage: stage, details: String(describing: error)), providerName: provider.name)
        } catch let error as LLMError {
            return .failed(stage: stage, startedAt: startedAt, error: .llm(stage: stage, error: error), providerName: provider.name)
        } catch {
            return .failed(stage: stage, startedAt: startedAt, error: .io(stage: stage, error: error), providerName: provider.name)
        }
    }
}

struct ClinicalLLMStageExecutor {
    let provider: any LLMProvider
    let context: PipelineExecutionContext

    func runASL(patientSpeech: String) async throws -> Data {
        let chunks = chunks(for: patientSpeech, label: "patient_speech", mode: .clinicalTranscript)
        if chunks.count <= 1 {
            return try await requestJSON(
                stage: .asl,
                system: ClinicalStagePrompts.aslSystem(),
                user: ClinicalStagePrompts.aslUser(patientId: context.patientId, patientSpeech: chunks.first?.text ?? patientSpeech),
                temperature: 0
            )
        }

        var partials: [String] = []
        for chunk in chunks {
            let data = try await requestJSON(
                stage: .asl,
                system: ClinicalStagePrompts.aslSystem(),
                user: ClinicalStagePrompts.aslChunkUser(
                    patientId: context.patientId,
                    chunkIndex: chunk.index + 1,
                    chunkTotal: chunk.total,
                    patientSpeech: chunk.text
                ),
                temperature: 0
            )
            try ClinicalArtifactValidator.validateASL(data: data)
            partials.append(prettyString(data))
        }

        return try await requestJSON(
            stage: .asl,
            system: ClinicalStagePrompts.aslSystem(),
            user: ClinicalStagePrompts.aslConsolidationUser(patientId: context.patientId, partials: partials),
            temperature: 0
        )
    }

    func runVDLP(asl: Data, patientSpeech: String) async throws -> Data {
        let compactSpeech = chunkSummary(for: patientSpeech, label: "patient_speech")
        return try await requestJSON(
            stage: .vdlp,
            system: ClinicalStagePrompts.vdlpSystem(),
            user: ClinicalStagePrompts.vdlpUser(
                patientId: context.patientId,
                aslJSON: prettyString(asl),
                patientSpeech: compactSpeech
            ),
            temperature: 0
        )
    }

    func runGEM(transcription: String, asl: Data, vdlp: Data) async throws -> Data {
        let compactTranscription = chunkSummary(for: transcription, label: "transcription")
        return try await requestJSON(
            stage: .gem,
            system: ClinicalStagePrompts.gemSystem(),
            user: ClinicalStagePrompts.gemUser(
                patientId: context.patientId,
                transcription: compactTranscription,
                aslJSON: prettyString(asl),
                vdlpJSON: prettyString(vdlp)
            ),
            temperature: 0.2
        )
    }

    private func requestJSON(
        stage: PipelineStage,
        system: String,
        user: String,
        temperature: Double
    ) async throws -> Data {
        let response = try await provider.complete(
            request: LLMRequest(
                userPrompt: user,
                systemPrompt: system,
                temperature: temperature,
                timeoutSeconds: HealthOSDefaults.Timeouts.forOperation(stage),
                useCache: true,
                maxOutputTokens: context.options.maxOutputTokens,
                responseFormat: .json
            )
        )
        return try PipelineJSON.extractObjectData(from: response.content)
    }

    private func chunks(
        for text: String,
        label: String,
        mode: ClinicalChunking.ChunkingMode
    ) -> [ClinicalChunking.ClinicalChunk] {
        ClinicalChunking.chunkClinicalText(
            text,
            options: ClinicalChunking.ChunkingOptions(
                targetTokens: context.options.chunkTargetTokens,
                maxTokensPerChunk: context.options.chunkMaxTokens,
                overlapTokens: context.options.chunkOverlapTokens,
                includeMetadataHeader: true,
                mode: mode,
                sourceLabel: label
            )
        )
    }

    private func chunkSummary(for text: String, label: String) -> String {
        let chunks = chunks(for: text, label: label, mode: .clinicalTranscript)
        if chunks.count <= 1 {
            return chunks.first?.text ?? text
        }

        return chunks.map { chunk in
            """
            <chunk index="\(chunk.index + 1)" total="\(chunk.total)" chars="\(chunk.charStart)-\(chunk.charEnd)" tokens="\(chunk.tokenEstimate)">
            \(chunk.text)
            </chunk>
            """
        }
        .joined(separator: "\n\n")
    }

    private func prettyString(_ data: Data) -> String {
        if let pretty = try? PipelineJSON.prettyData(from: data),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
