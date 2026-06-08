import Foundation

/// Single source of truth for selecting the LLM runtime across CLI, pipeline, and UI.
public enum LLMRuntimePreference {
    public static let userDefaultsKey = "healthos.llmRuntime"
    public static let environmentKey = "HEALTHOS_LLM_RUNTIME"
    public static let chatEnvironmentKey = "HEALTHOS_CHAT_RUNTIME"

    public static let environmentKeys = [
        environmentKey,
        chatEnvironmentKey,
    ]

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = .standard
    ) -> LLMRuntimeType {
        for key in environmentKeys {
            if let runtime = LLMRuntimeType(preferenceValue: environment[key]) {
                return runtime
            }
        }

        if let stored = userDefaults?.string(forKey: userDefaultsKey),
           let runtime = LLMRuntimeType(preferenceValue: stored) {
            return runtime
        }

        return .defaultRuntime
    }

    public static func resolveChat(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = .standard
    ) -> LLMRuntimeType {
        if let runtime = LLMRuntimeType(preferenceValue: environment[chatEnvironmentKey]) {
            return runtime
        }
        return resolve(environment: environment, userDefaults: userDefaults)
    }

    public static func persist(_ runtime: LLMRuntimeType, userDefaults: UserDefaults = .standard) {
        userDefaults.set(runtime.rawValue, forKey: userDefaultsKey)
    }

    public static func environment(
        from base: [String: String],
        runtime: LLMRuntimeType
    ) -> [String: String] {
        var environment = base
        environment[environmentKey] = runtime.rawValue
        environment[chatEnvironmentKey] = runtime.rawValue
        return environment
    }
}
