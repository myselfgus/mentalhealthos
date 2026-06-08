import Foundation
import HealthOSCore

public enum LLMRuntimeProviderFactory {
    public static func makeProvider(
        for runtime: LLMRuntimeType,
        baseDir: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> any LLMProvider {
        switch runtime {
        case .codex:
            return CodexRunner(
                workingDirectory: baseDir,
                sandbox: environment["HEALTHOS_CODEX_SANDBOX"] ?? "workspace-write"
            )
        case .claudeCode:
            return ClaudeCodeRunner(
                workingDirectory: baseDir,
                environment: environment
            )
        case .claudeAPI:
            return try ClaudeProvider(apiKey: environment["ANTHROPIC_API_KEY"])
        }
    }

    public static func makeProvider(
        from preference: LLMRuntimePreference.Type = LLMRuntimePreference.self,
        baseDir: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> any LLMProvider {
        let runtime = preference.resolve(environment: environment)
        return try makeProvider(for: runtime, baseDir: baseDir, environment: environment)
    }
}
