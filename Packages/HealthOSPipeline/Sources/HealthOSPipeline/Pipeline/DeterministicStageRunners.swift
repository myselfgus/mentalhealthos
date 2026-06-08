import Foundation
import HealthOSCore

public struct TranscriptionStageRunner: PipelineStageRunner {
    public let stage: PipelineStage = .transcribe

    public init() {}

    public func run(context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        let session = context.session

        if FileManager.default.fileExists(atPath: session.transcriptionPath.path) {
            return .skipped(
                stage: stage,
                startedAt: startedAt,
                message: "Existing transcription artifact preserved.",
                artifacts: [
                    PipelineArtifactIO.artifact(
                        kind: .transcription,
                        url: session.transcriptionPath,
                        format: "json"
                    )
                ]
            )
        }

        do {
            let audioFiles = try Self.audioFiles(in: session.audioDir)
            guard let audioURL = audioFiles.first else {
                return .failed(
                    stage: stage,
                    startedAt: startedAt,
                    error: .missingArtifact(
                        stage: stage,
                        path: session.audioDir,
                        purpose: "Source audio for native transcription"
                    )
                )
            }

            guard let provider = context.transcriptionProvider ?? (try? OpenAITranscriptionProvider()) else {
                return PipelineStageResult(
                    stage: stage,
                    status: .failed,
                    message: "Audio ready for transcription, but no STT provider is configured.",
                    startedAt: startedAt,
                    finishedAt: PipelineClock.now(),
                    artifacts: audioFiles.map {
                        PipelineArtifactIO.artifact(kind: .audio, url: $0, format: $0.pathExtension.lowercased())
                    },
                    error: .missingSTTProvider(
                        stage: stage,
                        audioFiles: audioFiles
                    )
                )
            }

            let artifact = try await provider.transcribe(audioURL: audioURL, session: session)
            try? WorkspaceManager(baseDir: context.baseDir).markSessionTranscription(
                patientId: context.patientId,
                sessionId: context.sessionId,
                transcriptionURL: URL(fileURLWithPath: artifact.path),
                source: provider.name
            )
            return .completed(
                stage: stage,
                startedAt: startedAt,
                message: "Audio transcribed by the Swift-native STT pipeline.",
                artifacts: [artifact],
                providerName: provider.name
            )
        } catch let error as LLMError {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .llm(stage: stage, error: error)
            )
        } catch {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .transcription(stage: stage, error: error)
            )
        }
    }

    private static func audioFiles(in dir: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let supported = Set(["m4a", "mp3", "wav", "aac", "mp4", "caf"])
        return try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { supported.contains($0.pathExtension.lowercased()) }
        .sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
    }
}

public struct ProcessStageRunner: PipelineStageRunner {
    public let stage: PipelineStage = .process

    public init() {}

    public func run(context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        let session = context.session

        guard FileManager.default.fileExists(atPath: session.transcriptionPath.path) else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingArtifact(
                    stage: stage,
                    path: session.transcriptionPath,
                    purpose: "Processed transcription JSON"
                )
            )
        }

        do {
            let transcription = try PipelineArtifactIO.loadTranscription(from: session.transcriptionPath)
            guard transcription.preferredText != nil else {
                return .failed(
                    stage: stage,
                    startedAt: startedAt,
                    error: .validation(stage: stage, details: "Transcription JSON has no recognized text field.")
                )
            }

            return .completed(
                stage: stage,
                startedAt: startedAt,
                message: "Transcription artifact is readable by the native pipeline.",
                artifacts: [
                    PipelineArtifactIO.artifact(
                        kind: .transcription,
                        url: session.transcriptionPath,
                        format: "json"
                    )
                ]
            )
        } catch {
            return .failed(stage: stage, startedAt: startedAt, error: .io(stage: stage, error: error))
        }
    }
}

public struct PatientSpeechStageRunner: PipelineStageRunner {
    public let stage: PipelineStage = .speech

    public init() {}

    public func run(context: PipelineExecutionContext) async -> PipelineStageResult {
        let startedAt = PipelineClock.now()
        let session = context.session

        if !context.options.overwriteExisting,
           let existing = PipelineArtifactIO.existingArtifact(
                kind: .patientSpeech,
                url: session.patientSpeechJsonPath,
                format: "json",
                stage: stage,
                startedAt: startedAt
           ) {
            return existing
        }

        guard FileManager.default.fileExists(atPath: session.transcriptionPath.path) else {
            return .failed(
                stage: stage,
                startedAt: startedAt,
                error: .missingArtifact(
                    stage: stage,
                    path: session.transcriptionPath,
                    purpose: "Source transcription"
                )
            )
        }

        do {
            let transcription = try PipelineArtifactIO.loadTranscription(from: session.transcriptionPath)
            guard let text = transcription.preferredText else {
                return .failed(
                    stage: stage,
                    startedAt: startedAt,
                    error: .validation(stage: stage, details: "Transcription text is empty.")
                )
            }

            let speakers = SpeakerTurnExtractor.speakers(in: text)
            guard !speakers.isEmpty else {
                return .failed(
                    stage: stage,
                    startedAt: startedAt,
                    error: .validation(
                        stage: stage,
                        details: "No speaker labels were found in the expected [Falante N] format."
                    )
                )
            }

            let patientSpeaker: String
            if speakers.count == 1 {
                patientSpeaker = speakers[0]
            } else {
                guard let provider = context.provider else {
                    return .failed(
                        stage: stage,
                        startedAt: startedAt,
                        error: .missingProvider(
                            stage: stage,
                            reason: "Multiple speakers require LLM-backed patient-speaker identification. The native runner does not guess a patient speaker."
                        )
                    )
                }

                let identification = try await identifyPatientSpeaker(
                    text: text,
                    speakers: speakers,
                    patientName: transcription.metadata?.patientName,
                    provider: provider
                )
                guard speakers.contains(identification.patientSpeaker) else {
                    return .failed(
                        stage: stage,
                        startedAt: startedAt,
                        error: .validation(
                            stage: stage,
                            details: "Provider returned \(identification.patientSpeaker), which is not in \(speakers.joined(separator: ", "))."
                        ),
                        providerName: provider.name
                    )
                }
                patientSpeaker = identification.patientSpeaker
            }

            let patientSpeech = SpeakerTurnExtractor.extractSpeakerLines(text, speakerLabel: patientSpeaker)
            guard !patientSpeech.isEmpty else {
                return .failed(
                    stage: stage,
                    startedAt: startedAt,
                    error: .validation(stage: stage, details: "No speech was found for \(patientSpeaker).")
                )
            }

            let artifact = PatientSpeechArtifact(
                sourceFile: transcription.sourceFile ?? session.transcriptionPath.lastPathComponent,
                extractedAt: PipelineClock.now(),
                patientSpeaker: patientSpeaker,
                patientName: transcription.metadata?.patientName,
                totalSpeakers: speakers.count,
                speakersFound: speakers,
                patientSpeech: patientSpeech,
                wordCount: patientSpeech.split(whereSeparator: \.isWhitespace).count,
                charCount: patientSpeech.count
            )

            try PipelineArtifactIO.writePatientSpeech(artifact, session: session)

            return .completed(
                stage: stage,
                startedAt: startedAt,
                message: "Patient speech extracted by the Swift-native pipeline.",
                artifacts: [
                    PipelineArtifactIO.artifact(kind: .patientSpeech, url: session.patientSpeechTextPath, format: "text"),
                    PipelineArtifactIO.artifact(kind: .patientSpeech, url: session.patientSpeechJsonPath, format: "json"),
                ],
                providerName: speakers.count > 1 ? context.provider?.name : nil
            )
        } catch let error as LLMError {
            return .failed(stage: stage, startedAt: startedAt, error: .llm(stage: stage, error: error), providerName: context.provider?.name)
        } catch {
            return .failed(stage: stage, startedAt: startedAt, error: .io(stage: stage, error: error), providerName: context.provider?.name)
        }
    }

    private func identifyPatientSpeaker(
        text: String,
        speakers: [String],
        patientName: String?,
        provider: any LLMProvider
    ) async throws -> SpeakerIdentification {
        let sample = String(text.prefix(4_000))
        let systemPrompt = """
        You are a clinical dialogue analyst. Identify which speaker label is the patient.
        Return only JSON matching this schema:
        {"patient_speaker":"Falante N","confidence":"high|medium|low","reasoning":"string"}
        Do not invent a speaker label. Choose one of: \(speakers.joined(separator: ", ")).
        """

        let userPrompt = """
        <transcription_sample>
        \(sample)
        </transcription_sample>

        \(patientName.map { "<patient_name>\($0)</patient_name>" } ?? "")

        Identify the patient speaker using dialogue roles and explicit identity cues.
        """

        let response = try await provider.complete(
            request: LLMRequest(
                userPrompt: userPrompt,
                systemPrompt: systemPrompt,
                temperature: 0.1,
                timeoutSeconds: HealthOSDefaults.Timeouts.medium,
                useCache: true,
                responseFormat: .json
            )
        )
        let data = try PipelineJSON.extractObjectData(from: response.content)
        return try PipelineJSON.decoder.decode(SpeakerIdentification.self, from: data)
    }
}

enum SpeakerTurnExtractor {
    static func speakers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\[Falante\\s+(\\d+)\\]", options: [.caseInsensitive]) else {
            return []
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        var seen: Set<String> = []
        var speakers: [String] = []

        for match in matches where match.numberOfRanges > 1 {
            let label = "Falante \(nsString.substring(with: match.range(at: 1)))"
            if !seen.contains(label) {
                seen.insert(label)
                speakers.append(label)
            }
        }

        return speakers.sorted { lhs, rhs in
            speakerNumber(lhs) < speakerNumber(rhs)
        }
    }

    static func extractSpeakerLines(_ text: String, speakerLabel: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: speakerLabel)
        let pattern = "\\[\(escaped)\\]\\s*([\\s\\S]*?)(?=\\[Falante\\s+\\d+\\]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ""
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let line = nsString.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        .joined(separator: "\n\n")
    }

    private static func speakerNumber(_ label: String) -> Int {
        Int(label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? Int.max
    }
}
