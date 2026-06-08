import Foundation

public actor CodexRunner: LLMProvider {
    nonisolated public var name: String { "Codex Subprocess" }

    private let agent: String?
    private let workingDirectory: URL?
    private let sandbox: String

    public init(agent: String? = nil, workingDirectory: URL? = nil, sandbox: String = "workspace-write") {
        self.agent = agent
        self.workingDirectory = workingDirectory
        self.sandbox = sandbox
    }

    public func complete(request: LLMRequest) async throws -> LLMResponse {
        let startTime = Date()
        let prompt = buildPrompt(request: request)
        let result = try await runCodex(prompt: prompt, timeout: request.timeoutSeconds)
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
            runtime: String(format: "Codex %.2fs", runtime),
            model: request.model ?? "codex-cli"
        )
    }

    public func stream(request: LLMRequest) async throws -> AsyncStream<String> {
        let prompt = buildPrompt(request: request)
        return AsyncStream { continuation in
            let task = Task {
                do {
                    let result = try await runCodex(prompt: prompt, timeout: request.timeoutSeconds)
                    if !result.stdout.isEmpty {
                        continuation.yield(result.stdout)
                    }
                    if result.exitCode != 0, !result.stderr.isEmpty {
                        continuation.yield("\n\(result.stderr)")
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
        var sections: [String] = []

        if let system = request.systemPrompt, !system.isEmpty {
            sections.append("## Sistema\n\n\(system)")
        }

        sections.append("""
        ## Runtime

        Voce esta rodando como subprocesso Codex local dentro do HealthOS.
        Use a configuracao instalada em ~/.codex, incluindo login ChatGPT, MCPs, plugins, skills, regras e profiles disponiveis.
        Nao peca OPENAI_API_KEY para executar tarefas Codex locais.
        """)

        if let agent, !agent.isEmpty {
            sections.append("## Agente solicitado\n\n\(agent)")
        }

        sections.append("## Pedido atual\n\n\(request.userPrompt)")
        return sections.joined(separator: "\n\n")
    }

    private func runCodex(prompt: String, timeout: TimeInterval) async throws -> CodexProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", shellCommand()]
            process.currentDirectoryURL = resolvedWorkingDirectory()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            var environment = ProcessInfo.processInfo.environment
            if let workingDirectory = resolvedWorkingDirectory()?.path {
                environment["HEALTHOS_BASE"] = workingDirectory
            }
            environment["PATH"] = codexPath(environment["PATH"])
            process.environment = environment

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let result = CodexProcessResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: proc.terminationStatus
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
                if let data = prompt.data(using: .utf8) {
                    stdin.fileHandleForWriting.write(data)
                }
                try stdin.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func codexArguments() -> [String] {
        var args = [
            "codex",
            "--sandbox", sandbox,
            "-a", "never"
        ]

        if let workingDirectory = resolvedWorkingDirectory()?.path {
            args.append(contentsOf: ["--cd", workingDirectory])
        }

        if let profile = ProcessInfo.processInfo.environment["HEALTHOS_CODEX_PROFILE"], !profile.isEmpty {
            args.append(contentsOf: ["--profile", profile])
        }

        args.append(contentsOf: ["exec", "--skip-git-repo-check", "-"])
        return args
    }

    private func shellCommand() -> String {
        codexArguments().map(shellEscape).joined(separator: " ")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func codexPath(_ inheritedPath: String?) -> String {
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"
        ]
        return (defaults + [inheritedPath ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }

    private func resolvedWorkingDirectory() -> URL? {
        if let workingDirectory { return workingDirectory }
        if let base = ProcessInfo.processInfo.environment["HEALTHOS_BASE"], !base.isEmpty {
            return URL(fileURLWithPath: base)
        }
        return nil
    }
}

private struct CodexProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}
