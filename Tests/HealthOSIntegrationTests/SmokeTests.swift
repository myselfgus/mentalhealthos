import Testing
import HealthOSAgents
import HealthOSCore
import HealthOSPipeline
import HealthOSTerminal
import HealthOSUI

@Test func rootPackageWiresSwiftNativeHealthOSModules() async throws {
    #expect(PipelineStage.allCases.map(\.nativeIdentifier) == [
        "transcribe",
        "process",
        "speech",
        "asl",
        "vdlp",
        "gem",
    ])
    #expect(PipelineShortcuts.pipelineStage(for: "gem") == .gem)
    #expect(AgentRegistry.shared.listAgentDefinitions().isEmpty == false)
    #expect(PipelineEngine.defaultRunners().count == PipelineStage.allCases.count)
}
