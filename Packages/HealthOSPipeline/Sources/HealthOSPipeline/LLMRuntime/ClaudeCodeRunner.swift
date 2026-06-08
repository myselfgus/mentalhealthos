import Foundation

public actor ClaudeCodeRunner: LLMProvider {
    nonisolated public var name: String { "Claude Code CLI" }

    private let workingDirectory: URL?
    private let environment: [String: String]

    public init(
        workingDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    public func complete(request: LLMRequest) async throws -> LLMResponse {
        let startTime = Date()
        let result = try await runClaude(prompt: buildPrompt(request: request), timeout: request.timeoutSeconds)
        let runtime = Date().timeIntervalSince(startTime)

        guard result.exitCode == 0 else {
            throw LLMError.serverError(
                statusCode: Int(result.exitCode),
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        return LLMResponse(
            content: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            usage: nil,
            runtime: String(format: "Claude Code %.2fs", runtime),
            model: "claude-code-cli"
        )
    }

    public func stream(request: LLMRequest) async throws -> AsyncStream<String> {
        return AsyncStream { continuation in
            let task = Task {
                do {
                    let response = try await complete(request: request)
                    if !response.content.isEmpty {
                        continuation.yield(response.content)
                    }
                } catch {
                    continuation.yield(error.localizedDescription)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func buildPrompt(request: LLMRequest) -> String {
        guard let system = request.systemPrompt, !system.isEmpty else {
            return request.userPrompt
        }
        return "System: \(system)\n\nUser: \(request.userPrompt)"
    }

    private func runClaude(prompt: String, timeout: TimeInterval) async throws -> ClaudeCodeProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", shellCommand(prompt: prompt)]
            process.currentDirectoryURL = resolvedWorkingDirectory()
            process.standardOutput = stdout
            process.standardError = stderr

            var processEnvironment = environment
            processEnvironment["PATH"] = cliPath(processEnvironment["PATH"])
            if let workingDirectory = resolvedWorkingDirectory()?.path {
                processEnvironment["HEALTHOS_BASE"] = workingDirectory
            }
            process.environment = processEnvironment

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ClaudeCodeProcessResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: proc.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func shellCommand(prompt: String) -> String {
        ["claude", "-p", prompt].map(shellEscape).joined(separator: " ")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func cliPath(_ inheritedPath: String?) -> String {
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"
        ]
        return (defaults + [inheritedPath ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }

    private func resolvedWorkingDirectory() -> URL? {
        if let workingDirectory { return workingDirectory }
        if let base = environment["HEALTHOS_BASE"], !base.isEmpty {
            return URL(fileURLWithPath: base)
        }
        return nil
    }
}

private struct ClaudeCodeProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}
