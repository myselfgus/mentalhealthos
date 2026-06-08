import Foundation

// MARK: - Terminal Session

/// Model representing an active terminal session.
@Observable
public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL
    public var environment: [String: String]
    public var isRunning: Bool
    public var commandHistory: [String]

    public init(
        title: String = "Terminal",
        workingDirectory: URL,
        environment: [String: String] = [:]
    ) {
        self.id = UUID()
        self.title = title
        self.workingDirectory = workingDirectory
        self.isRunning = false
        self.commandHistory = []

        // Build environment with defaults
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        self.environment = env
    }

    /// Add a command to history.
    public func recordCommand(_ command: String) {
        commandHistory.append(command)
    }
}
