import Foundation
import HealthOSCore

public protocol TranscriptionProvider: Sendable {
    var name: String { get }
    func transcribe(audioURL: URL, session: PatientSessionWorkspace) async throws -> PipelineArtifactRef
}

public actor OpenAITranscriptionProvider: TranscriptionProvider {
    public nonisolated let name: String = "OpenAI STT"

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let language: String?
    private let session: URLSession

    public init(
        apiKey: String? = nil,
        model: String = ProcessInfo.processInfo.environment["HEALTHOS_OPENAI_STT_MODEL"] ?? "gpt-4o-transcribe-diarize",
        baseURL: URL = URL(string: "https://api.openai.com")!,
        language: String? = "pt"
    ) throws {
        if let apiKey, !apiKey.isEmpty {
            self.apiKey = apiKey
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
        } else {
            throw LLMError.missingAPIKey(provider: "OpenAI STT")
        }
        self.model = model
        self.baseURL = baseURL
        self.language = language
        self.session = URLSession(configuration: .default)
    }

    public func transcribe(audioURL: URL, session: PatientSessionWorkspace) async throws -> PipelineArtifactRef {
        try FileManager.default.createDirectory(at: session.sourceDir, withIntermediateDirectories: true)
        let responseData = try await requestTranscription(audioURL: audioURL)
        let normalized = try normalize(responseData: responseData, sourceFile: audioURL.lastPathComponent)
        try normalized.write(to: session.transcriptionPath)
        return PipelineArtifactIO.artifact(kind: .transcription, url: session.transcriptionPath, format: "json")
    }

    private func requestTranscription(audioURL: URL) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = HealthOSDefaults.Timeouts.extraLong
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try multipartBody(audioURL: audioURL, boundary: boundary)
        let (data, response) = try await session.upload(for: request, from: body)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown OpenAI STT error"
            throw LLMError.serverError(statusCode: statusCode, message: message)
        }
        return data
    }

    private func multipartBody(audioURL: URL, boundary: String) throws -> Data {
        var body = Data()
        appendField("model", value: model, to: &body, boundary: boundary)
        appendField("response_format", value: "diarized_json", to: &body, boundary: boundary)
        appendField("chunking_strategy", value: "auto", to: &body, boundary: boundary)
        if let language {
            appendField("language", value: language, to: &body, boundary: boundary)
        }

        let filename = audioURL.lastPathComponent
        let mimeType = Self.mimeType(for: audioURL)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func appendField(_ name: String, value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    private func normalize(responseData: Data, sourceFile: String) throws -> Data {
        let response = try JSONDecoder().decode(OpenAIDiarizedTranscriptionResponse.self, from: responseData)
        let diarizedText = response.normalizedDiarizedText
        let fallbackText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = diarizedText.isEmpty ? (fallbackText ?? "") : diarizedText
        guard !text.isEmpty else {
            throw PipelineArtifactError.emptyTranscription
        }

        var payload: [String: Any] = [
            "source_file": sourceFile,
            "processed_at": ISO8601DateFormatter().string(from: Date()),
            "provider": name,
            "model": model,
            "response_format": "diarized_json",
            "transcription_original": text,
            "transcription_corrected": text,
            "text": fallbackText ?? text,
        ]
        if let duration = response.duration {
            payload["duration"] = duration
        }
        if let language = response.language {
            payload["language"] = language
        }
        if let segments = response.segments, !segments.isEmpty {
            payload["segments"] = segments.map(\.jsonObject)
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp4": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "aac": "audio/aac"
        case "caf": "audio/x-caf"
        default: "application/octet-stream"
        }
    }
}

private struct OpenAIDiarizedTranscriptionResponse: Decodable {
    var text: String?
    var duration: Double?
    var language: String?
    var segments: [OpenAIDiarizedSegment]?

    var normalizedDiarizedText: String {
        guard let segments else { return "" }
        return segments.compactMap { segment in
            let text = segment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return "[\(segment.normalizedSpeaker)] \(text)"
        }.joined(separator: "\n\n")
    }
}

private struct OpenAIDiarizedSegment: Decodable {
    var speaker: String?
    var text: String?
    var start: Double?
    var end: Double?

    var normalizedSpeaker: String {
        guard let speaker, !speaker.isEmpty else { return "Falante 1" }
        if speaker.localizedCaseInsensitiveContains("falante") {
            return speaker
        }
        let digits = speaker.filter(\.isNumber)
        if let rawIndex = Int(digits) {
            let oneBased = speaker.contains("0") && rawIndex == 0 ? 1 : rawIndex
            return "Falante \(oneBased)"
        }
        return speaker
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "speaker": normalizedSpeaker,
            "text": text ?? "",
        ]
        if let start { object["start"] = start }
        if let end { object["end"] = end }
        return object
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
