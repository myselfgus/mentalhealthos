import Foundation
import Testing
@testable import HealthOSCore

@Test func patientSessionContractDecodesAndEncodesCanonicalJSON() async throws {
    let json = """
    {
        "schema_version": "healthos.patient.v1",
        "patient_id": "PAT_000001",
        "identity": {
            "full_name": "João Silva",
            "initials": "JS"
        },
        "status": "active",
        "sessions": [
            {
                "session_id": "SESSION_2026_06_08",
                "session_number": 1,
                "date": "2026-06-08",
                "source_file": "consulta.m4a",
                "source_slug": "consulta",
                "path": "patients/PAT_000001/sessions/SESSION_2026_06_08",
                "processed_at": "2026-06-08T12:00:00Z",
                "status": {
                    "audio": true,
                    "transcription": true,
                    "patient_speech": true,
                    "asl": false,
                    "vdlp": false,
                    "gem": false
                },
                "artifacts": [
                    {
                        "artifact_id": "ART_TRANSCRIPTION",
                        "kind": "transcription",
                        "session_id": "SESSION_2026_06_08",
                        "path": "sessions/SESSION_2026_06_08/source/transcription.json",
                        "format": "json",
                        "source": "native",
                        "created_at": "2026-06-08T12:01:00Z"
                    }
                ]
            }
        ],
        "privacy": {
            "contains_phi": true,
            "directory_policy": "pseudonymous_id",
            "memory_policy": "explicit_only"
        },
        "created_at": "2025-01-01T00:00:00Z",
        "last_updated": "2025-06-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(PatientProfile.self, from: json)
    #expect(profile.patientId == "PAT_000001")
    #expect(profile.displayName == "João Silva")
    #expect(profile.initials == "JS")
    #expect(profile.status == PatientStatus.active)
    #expect(profile.sessions.count == 1)
    #expect(profile.privacy.containsPHI == true)

    let session = profile.sessions[0]
    #expect(session.sessionId == "SESSION_2026_06_08")
    #expect(session.status.completedCount == 3)
    #expect(session.status.progress == 0.5)
    #expect(session.artifacts?.first?.kind == PatientArtifactKind.transcription)

    let encoded = try JSONEncoder().encode(profile)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let sessions = try #require(object["sessions"] as? [[String: Any]])
    let encodedStatus = try #require(sessions.first?["status"] as? [String: Any])

    #expect(object["patient_id"] as? String == "PAT_000001")
    #expect(encodedStatus["patient_speech"] as? Bool == true)
}

@Test func sessionPipelineStatusProgress() async throws {
    var status = SessionPipelineStatus()
    #expect(status.completedCount == 0)
    #expect(status.progress == 0.0)

    status.audio = true
    status.transcription = true
    status.asl = true
    #expect(status.completedCount == 3)
    #expect(status.progress == 0.5)
}

@Test func vdlpDimensionMetaGroups() async throws {
    let affective = VDLPMetaDimension.affective.dimensions
    #expect(affective.count == 4)
    #expect(affective.contains(.v1_valenciaEmocional))

    let cognitive = VDLPMetaDimension.cognitive.dimensions
    #expect(cognitive.count == 5)

    let linguistic = VDLPMetaDimension.linguistic.dimensions
    #expect(linguistic.count == 6)

    // All 15 dimensions covered
    #expect(affective.count + cognitive.count + linguistic.count == 15)
}

@Test func pipelineStageOrderAndDisplayContract() async throws {
    let stages = PipelineStage.allCases

    #expect(stages.map(\.nativeIdentifier) == [
        "transcribe",
        "process",
        "speech",
        "asl",
        "vdlp",
        "gem",
    ])
    #expect(stages.map(\.index) == [0, 1, 2, 3, 4, 5])
    #expect(stages.map(\.displayName) == [
        "Transcrição",
        "Processamento",
        "Fala do Paciente",
        "ASL",
        "VDLP",
        "GEM",
    ])
}

@Test func pipelineStageNativeCommandMetadataAndLegacyCompatibility() async throws {
    #expect(PipelineStage.transcribe.nativeCommand == PipelineStageCommand(
        executable: "swift",
        arguments: ["run", "HealthOSCLI", "pipeline", "transcribe"]
    ))
    #expect(PipelineStage.gem.nativeCommand.shellString == "swift run HealthOSCLI pipeline gem")

    let encoded = try JSONEncoder().encode(PipelineStage.speech)
    let decoded = try JSONDecoder().decode(PipelineStage.self, from: encoded)
    #expect(decoded == PipelineStage.speech)
}

@Test func llmRuntimePreferenceParsesCliAliasesAndResolvesEnvironment() async throws {
    #expect(LLMRuntimeType(preferenceValue: "codex") == .codex)
    #expect(LLMRuntimeType(preferenceValue: "claude") == .claudeCode)
    #expect(LLMRuntimeType(preferenceValue: "claude-api") == .claudeAPI)
    #expect(LLMRuntimeType(preferenceValue: "unknown") == nil)

    let suiteName = "HealthOSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(LLMRuntimePreference.resolve(environment: [:], userDefaults: defaults) == .codex)

    LLMRuntimePreference.persist(.claudeCode, userDefaults: defaults)
    #expect(LLMRuntimePreference.resolve(environment: [:], userDefaults: defaults) == .claudeCode)

    let envRuntime = LLMRuntimePreference.resolve(
        environment: [LLMRuntimePreference.environmentKey: "ClaudeAPI"],
        userDefaults: defaults
    )
    #expect(envRuntime == .claudeAPI)

    let chatRuntime = LLMRuntimePreference.resolveChat(
        environment: [LLMRuntimePreference.chatEnvironmentKey: "claude"],
        userDefaults: defaults
    )
    #expect(chatRuntime == .claudeCode)

    let exported = LLMRuntimePreference.environment(from: [:], runtime: .claudeCode)
    #expect(exported[LLMRuntimePreference.environmentKey] == "ClaudeCode")
    #expect(exported[LLMRuntimePreference.chatEnvironmentKey] == "ClaudeCode")
}

@Test func consultationIntakeCreatesSessionWorkspaceAndImportsAudio() async throws {
    let base = try makeTemporaryCoreBase()
    defer { try? FileManager.default.removeItem(at: base) }

    let manager = WorkspaceManager(baseDir: base)
    let date = try #require(ISO8601DateFormatter().date(from: "2026-06-08T12:30:00Z"))
    let intake = try manager.createConsultationIntake(
        patientName: "Maria Souza",
        sessionDate: date,
        now: date
    )

    #expect(intake.patientId == "PAT_000001")
    #expect(intake.sessionId.hasPrefix("SESSION_"))
    #expect(FileManager.default.fileExists(atPath: intake.workspace.audioDir.path))
    #expect(FileManager.default.fileExists(atPath: intake.workspace.sessionPath.path))
    #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("patients/PAT_000001/patient.json").path))

    let sourceAudio = base.appendingPathComponent("consulta-fixture.wav")
    try Data("fake-audio".utf8).write(to: sourceAudio)
    let imported = try manager.importAudioForSession(
        from: sourceAudio,
        patientId: intake.patientId,
        sessionId: intake.sessionId,
        recordedAt: date
    )

    #expect(imported.didCopy == true)
    #expect(imported.destinationURL.deletingLastPathComponent().path == intake.workspace.audioDir.path)
    #expect(FileManager.default.fileExists(atPath: imported.destinationURL.path))

    let profile = try #require(manager.patients.first { $0.patientId == intake.patientId })
    let session = try #require(profile.sessions.first { $0.sessionId == intake.sessionId })
    #expect(session.status.audio == true)
    #expect(session.sourceFile == imported.destinationURL.lastPathComponent)
    #expect(session.artifacts?.first?.kind == .audio)
}

@Test func gemLayerTypes() async throws {
    #expect(GEMLayerType.allCases.count == 4)
    #expect(GEMLayerType.aje.displayName.contains("aje"))
    #expect(GEMLayerType.epe.displayName.contains("epe"))
}

private func makeTemporaryCoreBase() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("HealthOSCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
