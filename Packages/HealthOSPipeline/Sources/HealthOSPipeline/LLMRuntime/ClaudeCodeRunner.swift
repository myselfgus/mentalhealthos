import Foundation

public actor ClaudeCodeRunner: LLMProvider {
    nonisolated public var name: String { "Claude Code CLI" }

    public init() {}

    public func complete(request: LLMRequest) async throws -> LLMResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        
        // Pass system prompt if needed, though claude CLI might only take a generic prompt via -p
        var prompt = request.userPrompt
        if let system = request.systemPrompt {
            prompt = "System: \(system)\n\nUser: \(prompt)"
        }
        
        // Using `npx -y @anthropic-ai/claude-code` or just `claude` if installed.
        // npx is safer for general availability if node is installed.
        process.arguments = ["npx", "-y", "@anthropic-ai/claude-code", "-p", prompt]
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        let startTime = Date()
        try process.run()
        process.waitUntilExit()
        
        let runtime = Date().timeIntervalSince(startTime)
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        
        if process.terminationStatus != 0 {
            let errString = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(statusCode: Int(process.terminationStatus), message: errString)
        }
        
        let outString = String(data: outData, encoding: .utf8) ?? ""
        
        return LLMResponse(
            content: outString,
            usage: nil,
            runtime: String(format: "%.2fs", runtime),
            model: "claude-code-cli"
        )
    }

    public func stream(request: LLMRequest) async throws -> AsyncStream<String> {
        return AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            
            var prompt = request.userPrompt
            if let system = request.systemPrompt {
                prompt = "System: \(system)\n\nUser: \(prompt)"
            }
            process.arguments = ["npx", "-y", "@anthropic-ai/claude-code", "-p", prompt]
            
            let outPipe = Pipe()
            process.standardOutput = outPipe
            
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                    continuation.yield(string)
                }
            }
            
            process.terminationHandler = { _ in
                outPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }
            
            do {
                try process.run()
            } catch {
                continuation.finish()
            }
        }
    }
}
