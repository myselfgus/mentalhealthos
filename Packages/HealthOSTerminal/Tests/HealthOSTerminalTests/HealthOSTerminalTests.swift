import Foundation
import HealthOSCore
import Testing
@testable import HealthOSTerminal

@Test func pipelineShortcutsUseNativeInvocations() {
    let stages = PipelineShortcuts.all.compactMap(\.pipelineStage)

    #expect(stages == PipelineStage.allCases)
    #expect(PipelineShortcuts.command(for: "transcribe") == "healthos:pipeline:transcribe")
    #expect(PipelineShortcuts.command(for: "gem") == "healthos:pipeline:gem")
    #expect(PipelineShortcuts.pipelineStage(for: "speech") == .speech)
    #expect(PipelineShortcuts.shortcut(for: "transcribe")?.detail.isEmpty == false)
    #expect(PipelineShortcuts.shortcut(for: "transcribe")?.commandLabel == "Transcrever: healthos:pipeline:transcribe")
    #expect(PipelineShortcuts.all.allSatisfy { !$0.detail.isEmpty })
}

@Test func terminalSessionDefaultsToHighContrastTheme() {
    let session = TerminalSession(
        workingDirectory: URL(fileURLWithPath: "/tmp/healthos-terminal-theme-tests"),
        environment: ["HEALTHOS_LLM_RUNTIME": "ClaudeCode"]
    )

    #expect(session.theme.identifier == .highContrast)
    #expect(session.theme.ansi16.count == 16)
    #expect(session.environment["HEALTHOS_TERMINAL_THEME"] == "high-contrast")
    #expect(session.environment["COLORTERM"] == "truecolor")
    #expect(session.environment["TERM"] == "xterm-256color")
    #expect(session.runtimeStatus.label == "ClaudeCode | pronto")
}

@Test func terminalThemeCanBeConfiguredFromEnvironment() {
    let theme = TerminalTheme.resolve(from: ["HEALTHOS_TERMINAL_THEME": "standard"])
    let contrastAlias = TerminalTheme.resolve(from: ["HEALTHOS_TERMINAL_CONTRAST": "high"])

    #expect(theme.identifier == .standardDark)
    #expect(contrastAlias.identifier == .highContrast)
}

@Test func menuCLIPublishesRuntimeStatusAndClearShortcutDetails() {
    let workspace = WorkspaceManager(baseDir: URL(fileURLWithPath: "/tmp/healthos-terminal-menu-tests"))
    let cli = MenuCLI(
        workspaceManager: workspace,
        selectedRuntime: .claudeCode,
        terminalTheme: .highContrast
    )
    let actions = cli.buildActions()

    #expect(cli.runtimeStatusLabel == "Claude Code | pronto | claude")
    #expect(cli.terminalTheme.identifier == .highContrast)
    #expect(actions.first?.detail.contains("healthos:pipeline:transcribe") == true)
    #expect(actions.first { $0.key == "C" }?.detail.contains("healthos:chat") == true)
    #expect(actions.first { $0.key == "R" }?.detail == "atual: Claude Code")
}

@Test func nativePipelineEngineRunnerReportsNoSessionsForEmptyWorkspace() async {
    let runner = NativePipelineEngineRunner()
    let workspace = WorkspaceManager(baseDir: URL(fileURLWithPath: "/tmp/healthos-terminal-tests"))
    let context = TerminalPipelineExecutionContext(workspaceManager: workspace, runtime: .codex, environment: [:])

    do {
        _ = try await runner.run(stage: .asl, context: context)
        Issue.record("Native runner should report no sessions for an empty workspace.")
    } catch PipelineStageRunnerError.noSessions(let stage) {
        #expect(stage == .asl)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func menuPipelineExecutionPropagatesSelectedRuntimeToContextAndEnvironment() async throws {
    let runner = CapturingPipelineRunner()
    let workspace = WorkspaceManager(baseDir: URL(fileURLWithPath: "/tmp/healthos-terminal-runtime-tests"))
    let menu = MenuCLI(
        workspaceManager: workspace,
        pipelineRunner: runner,
        selectedRuntime: .claudeCode
    )

    try await menu.executePipelineStage(.asl, description: "Runtime capture")

    let captured = await runner.captured()
    #expect(captured?.runtime == .claudeCode)
    #expect(captured?.environment[LLMRuntimePreference.environmentKey] == "ClaudeCode")
    #expect(captured?.environment[LLMRuntimePreference.chatEnvironmentKey] == "ClaudeCode")
}

private struct CapturedPipelineContext: Sendable {
    let runtime: LLMRuntimeType
    let environment: [String: String]
}

private actor CapturingPipelineRunner: PipelineStageRunning {
    private var lastContext: CapturedPipelineContext?

    func run(stage: PipelineStage, context: TerminalPipelineExecutionContext) async throws -> PipelineExecutionResult {
        lastContext = CapturedPipelineContext(
            runtime: context.runtime,
            environment: context.environment
        )
        return PipelineExecutionResult(stage: stage, message: "captured")
    }

    func captured() -> CapturedPipelineContext? {
        lastContext
    }
}
