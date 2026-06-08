import Foundation

// MARK: - Process Runner

/// Async subprocess execution with streaming output.
public actor ProcessRunner {

    public init() {}

    /// Run a command and stream output in real-time.
    public func run(
        command: String,
        arguments: [String] = [],
        workingDirectory: URL,
        environment: [String: String] = [:]
    ) -> AsyncThrowingStream<ProcessOutput, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", ([command] + arguments).joined(separator: " ")]
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Merge caller environment with process environment
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            let inheritedPath = env["PATH"] ?? defaultPath
            env["PATH"] = inheritedPath.isEmpty ? defaultPath : "\(inheritedPath):\(defaultPath)"
            process.environment = env

            // Stream stdout
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    continuation.yield(.stdout(text))
                }
            }

            // Stream stderr
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    continuation.yield(.stderr(text))
                }
            }

            // Handle termination
            process.terminationHandler = { proc in
                // Clean up handlers
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.yield(.exit(proc.terminationStatus))
                continuation.finish()
            }

            // Handle cancellation
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Run a command and capture all output at once.
    public func runAndCapture(
        command: String,
        arguments: [String] = [],
        workingDirectory: URL,
        environment: [String: String] = [:]
    ) async throws -> ProcessResult {
        var stdout = ""
        var stderr = ""
        var exitCode: Int32 = -1

        for try await output in run(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        ) {
            switch output {
            case .stdout(let text): stdout += text
            case .stderr(let text): stderr += text
            case .exit(let code): exitCode = code
            }
        }

        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

// MARK: - Output Types

/// Individual output event from a running process.
public enum ProcessOutput: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

/// Captured result from a completed process.
public struct ProcessResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var success: Bool { exitCode == 0 }

    /// Combined output (stdout + stderr).
    public var combinedOutput: String {
        var result = stdout
        if !stderr.isEmpty {
            if !result.isEmpty { result += "\n" }
            result += stderr
        }
        return result
    }
}
