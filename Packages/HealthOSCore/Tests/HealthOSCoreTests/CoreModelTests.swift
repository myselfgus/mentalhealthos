import Testing
@testable import HealthOSCore

@Test func patientProfileDecoding() async throws {
    let json = """
    {
        "patient_id": "PAT_000001",
        "patient_name": "João Silva",
        "patient_initials": "JS",
        "status": "active",
        "sessions": [],
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
    #expect(profile.status == .active)
    #expect(profile.sessions.isEmpty)
    #expect(profile.privacy.containsPHI == true)
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

@Test func pipelineStageProperties() async throws {
    #expect(PipelineStage.allCases.count == 6)
    #expect(PipelineStage.gem.npmScript == "npm run pipeline:gem")
    #expect(PipelineStage.transcribe.index == 0)
    #expect(PipelineStage.gem.index == 5)
}

@Test func gemLayerTypes() async throws {
    #expect(GEMLayerType.allCases.count == 4)
    #expect(GEMLayerType.aje.displayName.contains("aje"))
    #expect(GEMLayerType.epe.displayName.contains("epe"))
}
