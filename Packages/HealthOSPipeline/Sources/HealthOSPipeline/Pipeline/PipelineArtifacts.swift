import Foundation
import HealthOSCore

struct TranscriptionArtifact: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        var patientName: String?
        var professionalName: String?

        enum CodingKeys: String, CodingKey {
            case patientName = "patient_name"
            case professionalName = "professional_name"
        }
    }

    var sourceFile: String?
    var processedAt: String?
    var transcriptionOriginal: String?
    var transcriptionCorrected: String?
    var transcricao: String?
    var content: String?
    var text: String?
    var metadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case processedAt = "processed_at"
        case transcriptionOriginal = "transcription_original"
        case transcriptionCorrected = "transcription_corrected"
        case transcricao
        case content
        case text
        case metadata
    }

    var preferredText: String? {
        [
            transcriptionCorrected,
            transcricao,
            transcriptionOriginal,
            content,
            text,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }
}

struct PatientSpeechArtifact: Codable, Sendable {
    var sourceFile: String
    var extractedAt: String
    var patientSpeaker: String
    var patientName: String?
    var totalSpeakers: Int
    var speakersFound: [String]
    var patientSpeech: String
    var wordCount: Int
    var charCount: Int

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case extractedAt = "extracted_at"
        case patientSpeaker = "patient_speaker"
        case patientName = "patient_name"
        case totalSpeakers = "total_speakers"
        case speakersFound = "speakers_found"
        case patientSpeech = "patient_speech"
        case wordCount = "word_count"
        case charCount = "char_count"
    }
}

struct SpeakerIdentification: Decodable, Sendable {
    var patientSpeaker: String
    var confidence: String
    var reasoning: String

    enum CodingKeys: String, CodingKey {
        case patientSpeaker = "patient_speaker"
        case confidence
        case reasoning
    }
}

enum PipelineArtifactIO {
    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func artifact(kind: PatientArtifactKind, url: URL, format: String) -> PipelineArtifactRef {
        PipelineArtifactRef(kind: kind, path: url.path, format: format)
    }

    static func existingArtifact(
        kind: PatientArtifactKind,
        url: URL,
        format: String,
        stage: PipelineStage,
        startedAt: String
    ) -> PipelineStageResult? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return .skipped(
            stage: stage,
            startedAt: startedAt,
            message: "Existing \(kind.rawValue) artifact preserved.",
            artifacts: [artifact(kind: kind, url: url, format: format)]
        )
    }

    static func loadTranscription(from url: URL) throws -> TranscriptionArtifact {
        let data = try Data(contentsOf: url)
        if let artifact = try? PipelineJSON.decoder.decode(TranscriptionArtifact.self, from: data),
           artifact.preferredText != nil {
            return artifact
        }

        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            throw PipelineArtifactError.emptyTranscription
        }

        return TranscriptionArtifact(
            sourceFile: url.lastPathComponent,
            processedAt: nil,
            transcriptionOriginal: text,
            transcriptionCorrected: nil,
            transcricao: nil,
            content: nil,
            text: nil,
            metadata: nil
        )
    }

    static func loadPatientSpeech(from session: PatientSessionWorkspace) throws -> String {
        if FileManager.default.fileExists(atPath: session.patientSpeechJsonPath.path) {
            let data = try Data(contentsOf: session.patientSpeechJsonPath)
            let artifact = try PipelineJSON.decoder.decode(PatientSpeechArtifact.self, from: data)
            let text = artifact.patientSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        for url in [session.patientSpeechTextPath, session.patientSpeechMarkdownPath] {
            if FileManager.default.fileExists(atPath: url.path) {
                let text = try String(contentsOf: url, encoding: .utf8)
                    .components(separatedBy: "\n---\n")
                    .last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let text, !text.isEmpty {
                    return text
                }
            }
        }

        throw PipelineArtifactError.emptyPatientSpeech
    }

    static func writePatientSpeech(_ artifact: PatientSpeechArtifact, session: PatientSessionWorkspace) throws {
        try ensureDirectory(session.analysisDir)
        let header = """
        # Falas do Paciente
        # Fonte: \(artifact.sourceFile)
        # Processado: \(artifact.extractedAt)
        # Falante identificado: \(artifact.patientSpeaker)
        # Paciente: \(artifact.patientName ?? "N/A")

        ---

        """

        try (header + artifact.patientSpeech).write(
            to: session.patientSpeechTextPath,
            atomically: true,
            encoding: .utf8
        )
        try PipelineJSON.writeEncodable(artifact, to: session.patientSpeechJsonPath)
    }
}

enum PipelineArtifactError: Error, LocalizedError {
    case emptyTranscription
    case emptyPatientSpeech

    var errorDescription: String? {
        switch self {
        case .emptyTranscription:
            "Transcription artifact does not contain transcription text."
        case .emptyPatientSpeech:
            "Patient speech artifact does not contain extracted patient speech."
        }
    }
}
