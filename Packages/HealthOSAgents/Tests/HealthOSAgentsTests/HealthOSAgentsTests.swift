import XCTest
import HealthOSAgents
import HealthOSCore

final class HealthOSAgentsTests: XCTestCase {
    func testRegistryIncludesSystemAndHealthOSAgents() {
        let registry = AgentRegistry(baseDir: temporaryWorkspace())
        let definitions = registry.listAgentDefinitions(options: ListAgentDefinitionsOptions(
            includeScenario: true,
            includeCodex: false,
            includePrompts: false
        ))

        XCTAssertTrue(definitions.contains { $0.id == "conversation-agent" })
        XCTAssertTrue(definitions.contains { $0.id == "context-architect" })
        XCTAssertEqual(registry.resolveAgentDefinition("ASLAgent")?.id, "asl-agent")
    }

    func testLocalToolDescriptorsExposeTypedSchemas() {
        let workflowTool = healthOSTools.first { $0.name == "plan_agent_workflow" }

        XCTAssertNotNil(workflowTool)
        XCTAssertEqual(workflowTool?.transport, .localSwift)
        XCTAssertEqual(workflowTool?.parameters?.required, ["input"])
        XCTAssertNotNil(workflowTool?.parametersSchema)
        XCTAssertTrue(workflowTool?.parametersSchema?.contains("\"additionalProperties\" : false") ?? false)
    }

    func testWorkflowDetectionRoutesClinicalAndPipelineIntents() {
        let risk = detectAgentWorkflow("checa risco suicida deste caso", patientId: "PAT_TEST")
        XCTAssertEqual(risk.kind, .clinicalRiskCheck)
        XCTAssertEqual(risk.agentId, "risk-check-agent")
        XCTAssertTrue(risk.reviewRequired)
        XCTAssertTrue(risk.requiresPatient)

        let asl = detectAgentWorkflow("roda ASL da sessao atual", patientId: "PAT_TEST")
        XCTAssertEqual(asl.kind, .pipelineStage)
        XCTAssertEqual(asl.stage, .asl)
        XCTAssertEqual(asl.agentId, "asl-agent")
    }

    func testChatContextRendersPatientArtifacts() throws {
        let baseDir = try makeWorkspaceFixture()
        let manager = WorkspaceManager(baseDir: baseDir)
        let builder = ChatContextBuilder(manager: manager)

        let patientContext = try builder.renderPatientContext(activePatientId: "PAT_TEST")
        XCTAssertTrue(patientContext.contains("Paciente Teste"))
        XCTAssertTrue(patientContext.contains("transcription"))
        XCTAssertTrue(patientContext.contains("ASL"))

        let refs = builder.collectContextReferences(activePatientId: "PAT_TEST")
        XCTAssertTrue(refs.contains { $0.hasSuffix("patients/PAT_TEST/patient.json") })
        XCTAssertTrue(refs.contains { $0.hasSuffix("patients/PAT_TEST/sessions/C1/analysis/asl.json") })
    }

    func testOrchestratorReturnsStructuredNotConfiguredForClinicalRuntime() async {
        let orchestrator = ConversationOrchestrator(patientId: "PAT_TEST")

        let result = await orchestrator.processInputResult("prepara a proxima sessao deste paciente")

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.error, "Runtime/provider is not configured for agent session-prep-agent.")
        XCTAssertTrue(result.content?.contains("\"code\" : \"runtime_not_configured\"") ?? false)
        XCTAssertTrue(result.content?.contains("\"agentId\" : \"session-prep-agent\"") ?? false)
    }

    private func makeWorkspaceFixture() throws -> URL {
        let baseDir = temporaryWorkspace()
        let manager = WorkspaceManager(baseDir: baseDir)
        try FileManager.default.createDirectory(
            at: baseDir.appendingPathComponent("professionals"),
            withIntermediateDirectories: true
        )
        try manager.saveProfessionalConfig(ProfessionalConfig(
            id: "dr-test",
            nome: "Dra. Teste",
            registro: "CRM-TEST"
        ))

        let professionalWorkspace = ProfessionalWorkspace(id: "dr-test", baseDir: baseDir)
        try "Perfil de teste".write(to: professionalWorkspace.chatAgentPath, atomically: true, encoding: .utf8)
        try "- memoria explicita".write(to: professionalWorkspace.memoryPath, atomically: true, encoding: .utf8)

        let patientDir = baseDir.appendingPathComponent("patients").appendingPathComponent("PAT_TEST")
        let sessionSourceDir = patientDir
            .appendingPathComponent("sessions")
            .appendingPathComponent("C1")
            .appendingPathComponent("source")
        let sessionAnalysisDir = patientDir
            .appendingPathComponent("sessions")
            .appendingPathComponent("C1")
            .appendingPathComponent("analysis")
        try FileManager.default.createDirectory(at: sessionSourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionAnalysisDir, withIntermediateDirectories: true)

        try patientJSON.write(to: patientDir.appendingPathComponent("patient.json"), atomically: true, encoding: .utf8)
        try "Care agent de teste".write(to: patientDir.appendingPathComponent("care-agent.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: sessionSourceDir.appendingPathComponent("transcription.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: sessionAnalysisDir.appendingPathComponent("asl.json"), atomically: true, encoding: .utf8)

        return baseDir
    }

    private func temporaryWorkspace() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthOSAgentsTests")
            .appendingPathComponent(UUID().uuidString)
    }

    private var patientJSON: String {
        """
        {
          "schema_version": "1.0",
          "patient_id": "PAT_TEST",
          "patient_name": "Paciente Teste",
          "status": "active",
          "sessions": [
            {
              "session_id": "C1",
              "status": {
                "audio": true,
                "transcription": true,
                "patient_speech": false,
                "asl": true,
                "vdlp": false,
                "gem": false
              }
            }
          ],
          "privacy": {
            "contains_phi": true,
            "directory_policy": "pseudonymous_id",
            "memory_policy": "explicit_only"
          },
          "created_at": "2026-06-08T00:00:00Z",
          "last_updated": "2026-06-08T00:00:00Z"
        }
        """
    }
}
