import Testing
import HealthOSCore
import HealthOSUI

@MainActor
@Test func healthOSUIViewsInstantiateForSwiftPackageSmokeTest() async throws {
    _ = PipelineView()
    _ = AgentListView()
    _ = ConsultationIntakeView()
    let viewModel = ConversationViewModel()
    #expect(viewModel.messages.isEmpty == false)
}

@MainActor
@Test func conversationViewModelShowsLocalFailureFeedbackWithoutWorkspace() async throws {
    let viewModel = ConversationViewModel()
    viewModel.inputText = "status do workspace"

    viewModel.sendMessage()

    try await waitForMessages(in: viewModel, count: 3)

    #expect(viewModel.isTyping == false)
    #expect(viewModel.activityState == .failed("Workspace indisponível"))
    #expect(viewModel.messages[1].status == .failed("Workspace indisponível"))
    #expect(viewModel.messages[2].status == .failed("Workspace indisponível"))
    #expect(viewModel.messages[2].metadata.isFallback == true)
    #expect(viewModel.messages[2].metadata.compactSummary?.contains("fallback local") == true)
}

@MainActor
private func waitForMessages(in viewModel: ConversationViewModel, count: Int) async throws {
    for _ in 0..<50 {
        if viewModel.messages.count >= count {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
