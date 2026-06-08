import Foundation
import HealthOSCore
@testable import HealthOSPipeline
import Testing
#if os(macOS)
import Darwin
#endif

@Test func deterministicSpeechStageWritesPatientSpeechArtifacts() async throws {
    let base = try makeTemporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let session = try makeSession(base: base)
    try writeTranscription(
        session: session,
        text: "[Falante 1] Eu estou melhor hoje.\n\n[Falante 1] Consegui dormir.",
        patientName: "Paciente Teste"
    )

    let engine = PipelineEngine()
    let result = await engine.run(
        stage: .speech,
        baseDir: base,
        patientId: session.patientId,
        sessionId: session.id
    )

    #expect(result.status == .completed)
    #expect(FileManager.default.fileExists(atPath: session.patientSpeechTextPath.path))
    #expect(FileManager.default.fileExists(atPath: session.patientSpeechJsonPath.path))

    let data = try Data(contentsOf: session.patientSpeechJsonPath)
    let artifact = try PipelineJSON.decoder.decode(PatientSpeechArtifact.self, from: data)
    #expect(artifact.patientSpeaker == "Falante 1")
    #expect(artifact.patientSpeech.contains("Eu estou melhor hoje."))
    #expect(artifact.totalSpeakers == 1)
}

@Test func speechStageDoesNotGuessPatientSpeakerWithoutProvider() async throws {
    let base = try makeTemporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let session = try makeSession(base: base)
    try writeTranscription(
        session: session,
        text: "[Falante 1] Como voce esta?\n\n[Falante 2] Estou cansado.",
        patientName: "Paciente Teste"
    )

    let engine = PipelineEngine()
    let result = await engine.run(
        stage: .speech,
        baseDir: base,
        patientId: session.patientId,
        sessionId: session.id
    )

    #expect(result.status == .failed)
    #expect(result.error?.code == "missing_provider")
    #expect(!FileManager.default.fileExists(atPath: session.patientSpeechJsonPath.path))
}

@Test func aslStageCallsProviderAndWritesValidatedJSON() async throws {
    let base = try makeTemporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let session = try makeSession(base: base)
    try PipelineArtifactIO.ensureDirectory(session.analysisDir)
    try "Eu estou melhor hoje.".write(to: session.patientSpeechTextPath, atomically: true, encoding: .utf8)

    let provider = StubProvider(responses: [validASLJSON()])
    let engine = PipelineEngine()
    let result = await engine.run(
        stage: .asl,
        baseDir: base,
        patientId: session.patientId,
        sessionId: session.id,
        provider: provider,
        options: PipelineExecutionOptions(overwriteExisting: true)
    )

    #expect(result.status == .completed)
    #expect(result.providerName == "StubProvider")
    #expect(await provider.requestCount() == 1)
    #expect(FileManager.default.fileExists(atPath: session.aslPath.path))

    let data = try Data(contentsOf: session.aslPath)
    try ClinicalArtifactValidator.validateASL(data: data)
    let object = try PipelineJSON.object(from: data)
    #expect(object["contexto_identificado"] != nil)
}

@Test func aslStageRejectsMissingProviderWithStructuredError() async throws {
    let base = try makeTemporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let session = try makeSession(base: base)
    try PipelineArtifactIO.ensureDirectory(session.analysisDir)
    try "Eu estou melhor hoje.".write(to: session.patientSpeechTextPath, atomically: true, encoding: .utf8)

    let engine = PipelineEngine()
    let result = await engine.run(
        stage: .asl,
        baseDir: base,
        patientId: session.patientId,
        sessionId: session.id
    )

    #expect(result.status == .failed)
    #expect(result.error?.code == "missing_provider")
    #expect(!FileManager.default.fileExists(atPath: session.aslPath.path))
}

@Test func transcribeStageReportsStructuredPlaceholderWhenSTTProviderIsMissing() async throws {
    #if os(macOS)
    let previousKey = getenv("OPENAI_API_KEY").map { String(cString: $0) }
    setenv("OPENAI_API_KEY", "", 1)
    defer {
        if let previousKey {
            setenv("OPENAI_API_KEY", previousKey, 1)
        } else {
            unsetenv("OPENAI_API_KEY")
        }
    }
    #endif

    let base = try makeTemporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let session = try makeSession(base: base)
    let audioURL = session.audioDir.appendingPathComponent("consulta.m4a")
    try Data("fake-audio".utf8).write(to: audioURL)

    let engine = PipelineEngine()
    let result = await engine.run(
        stage: .transcribe,
        baseDir: base,
        patientId: session.patientId,
        sessionId: session.id
    )

    #expect(result.status == .failed)
    #expect(result.error?.code == "missing_stt_provider")
    #expect(result.artifacts.first?.kind == .audio)
    #expect(result.artifacts.first?.path.hasSuffix("/patients/PAT_TEST/sessions/SESSION_TEST/source/audio/consulta.m4a") == true)
}

@Test func transcribeStageUsesInjectedProviderAndWritesTranscription() async throws {
    let base = try makeTemporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let session = try makeSession(base: base)
    let audioURL = session.audioDir.appendingPathComponent("consulta.m4a")
    try Data("fake-audio".utf8).write(to: audioURL)

    let provider = StubTranscriptionProvider()
    let engine = PipelineEngine()
    let result = await engine.run(
        stage: .transcribe,
        baseDir: base,
        patientId: session.patientId,
        sessionId: session.id,
        transcriptionProvider: provider
    )

    #expect(result.status == .completed)
    #expect(result.providerName == "Stub STT")
    #expect(FileManager.default.fileExists(atPath: session.transcriptionPath.path))

    let artifact = try PipelineArtifactIO.loadTranscription(from: session.transcriptionPath)
    #expect(artifact.preferredText?.contains("[Falante 1]") == true)
}

@Test func runtimeProviderFactoryMapsRuntimeSelectionToConcreteProviders() throws {
    let base = URL(fileURLWithPath: "/tmp/healthos-runtime-provider-tests")
    let codex = try LLMRuntimeProviderFactory.makeProvider(
        for: .codex,
        baseDir: base,
        environment: ["HEALTHOS_CODEX_SANDBOX": "read-only"]
    )
    #expect(codex.name == "Codex Subprocess")

    let claudeCode = try LLMRuntimeProviderFactory.makeProvider(
        for: .claudeCode,
        baseDir: base,
        environment: [:]
    )
    #expect(claudeCode.name == "Claude Code CLI")

    do {
        let claudeAPI = try LLMRuntimeProviderFactory.makeProvider(
            for: .claudeAPI,
            baseDir: base,
            environment: [:]
        )
        #expect(claudeAPI.name == "Claude API")
    } catch LLMError.missingAPIKey(let provider) {
        #expect(provider == "Claude")
    }
}

private actor StubProvider: LLMProvider {
    nonisolated let name = "StubProvider"
    private var responses: [String]
    private var requests: [LLMRequest] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func complete(request: LLMRequest) async throws -> LLMResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw LLMError.invalidResponse(detail: "No stub response queued")
        }
        return LLMResponse(content: responses.removeFirst(), runtime: name, model: "stub")
    }

    func requestCount() -> Int {
        requests.count
    }
}

private actor StubTranscriptionProvider: TranscriptionProvider {
    nonisolated let name = "Stub STT"

    func transcribe(audioURL: URL, session: PatientSessionWorkspace) async throws -> PipelineArtifactRef {
        try PipelineArtifactIO.ensureDirectory(session.sourceDir)
        let payload: [String: Any] = [
            "source_file": audioURL.lastPathComponent,
            "processed_at": "2026-06-08T00:00:00Z",
            "transcription_original": "[Falante 1] Consulta de teste.",
            "transcription_corrected": "[Falante 1] Consulta de teste.",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: session.transcriptionPath)
        return PipelineArtifactIO.artifact(kind: .transcription, url: session.transcriptionPath, format: "json")
    }
}

private func makeTemporaryBase() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("HealthOSPipelineTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeSession(
    base: URL,
    patientId: String = "PAT_TEST",
    sessionId: String = "SESSION_TEST"
) throws -> PatientSessionWorkspace {
    let session = PatientSessionWorkspace(
        patientId: patientId,
        sessionId: sessionId,
        patientsBaseDir: base.appendingPathComponent("patients")
    )
    try PipelineArtifactIO.ensureDirectory(session.sourceDir)
    try PipelineArtifactIO.ensureDirectory(session.audioDir)
    try PipelineArtifactIO.ensureDirectory(session.analysisDir)
    return session
}

private func writeTranscription(
    session: PatientSessionWorkspace,
    text: String,
    patientName: String? = nil
) throws {
    let payload: [String: Any] = [
        "source_file": "fixture.wav",
        "processed_at": "2026-06-08T00:00:00Z",
        "transcription_original": text,
        "transcription_corrected": text,
        "metadata": [
            "patient_name": patientName as Any,
            "professional_name": "Dra. Teste",
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: session.transcriptionPath)
}

private func validASLJSON() -> String {
    let domain = """
    {
      "metricas_quantitativas": {"total": 1},
      "exemplos_textuais": ["Eu estou melhor hoje."],
      "analise_contextual": {
        "descricao_geral": "Fala breve e organizada.",
        "padroes_observados": ["relato direto"],
        "significado_observado": "Evidencia limitada a uma frase.",
        "comparacao_normativa": "Nao avaliada com base populacional.",
        "consideracoes_contextuais": "Amostra curta."
      }
    }
    """

    let domains = ASLDomainType.allCases
        .map { "\"\($0.rawValue)\": \(domain)" }
        .joined(separator: ",\n")

    return """
    {
      "contexto_identificado": {
        "tipo_interacao": "recorte clinico",
        "papeis_participantes": {"falante_alvo": "paciente"},
        "dominio_tematico": ["humor"],
        "dinamica_interacional": "fala isolada",
        "evidencias_contexto": ["Eu estou melhor hoje."]
      },
      \(domains),
      "sintese_interpretativa": {
        "perfil_linguistico_geral": "Amostra curta com organizacao preservada.",
        "achados_mais_salientes": ["relato de melhora"],
        "padroes_integrados": ["fala direta"],
        "consideracoes_finais": "Interpretacao limitada pela brevidade.",
        "limitacoes_analise": ["Amostra minima."]
      }
    }
    """
}
