import Foundation

// MARK: - Terminal Theme

public struct TerminalRGB: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var ansiForeground: String {
        "\u{001B}[38;2;\(red);\(green);\(blue)m"
    }

    public var ansiBackground: String {
        "\u{001B}[48;2;\(red);\(green);\(blue)m"
    }
}

public enum TerminalThemeIdentifier: String, CaseIterable, Sendable {
    case highContrast = "high-contrast"
    case standardDark = "standard-dark"
}

public struct TerminalTheme: Equatable, Sendable {
    public let identifier: TerminalThemeIdentifier
    public let displayName: String
    public let foreground: TerminalRGB
    public let background: TerminalRGB
    public let accent: TerminalRGB
    public let success: TerminalRGB
    public let warning: TerminalRGB
    public let error: TerminalRGB
    public let muted: TerminalRGB
    public let selection: TerminalRGB
    public let caret: TerminalRGB
    public let ansi16: [TerminalRGB]

    public init(
        identifier: TerminalThemeIdentifier,
        displayName: String,
        foreground: TerminalRGB,
        background: TerminalRGB,
        accent: TerminalRGB,
        success: TerminalRGB,
        warning: TerminalRGB,
        error: TerminalRGB,
        muted: TerminalRGB,
        selection: TerminalRGB,
        caret: TerminalRGB,
        ansi16: [TerminalRGB]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.foreground = foreground
        self.background = background
        self.accent = accent
        self.success = success
        self.warning = warning
        self.error = error
        self.muted = muted
        self.selection = selection
        self.caret = caret
        self.ansi16 = ansi16
    }

    public var environmentDefaults: [String: String] {
        [
            "HEALTHOS_TERMINAL_THEME": identifier.rawValue,
            "CLICOLOR": "1",
            "COLORTERM": "truecolor",
            "TERM": "xterm-256color"
        ]
    }

    public static let highContrast = TerminalTheme(
        identifier: .highContrast,
        displayName: "Alto contraste",
        foreground: TerminalRGB(red: 246, green: 248, blue: 255),
        background: TerminalRGB(red: 2, green: 6, blue: 23),
        accent: TerminalRGB(red: 34, green: 211, blue: 238),
        success: TerminalRGB(red: 74, green: 222, blue: 128),
        warning: TerminalRGB(red: 250, green: 204, blue: 21),
        error: TerminalRGB(red: 248, green: 113, blue: 113),
        muted: TerminalRGB(red: 203, green: 213, blue: 225),
        selection: TerminalRGB(red: 14, green: 116, blue: 144),
        caret: TerminalRGB(red: 253, green: 224, blue: 71),
        ansi16: [
            TerminalRGB(red: 2, green: 6, blue: 23),
            TerminalRGB(red: 248, green: 113, blue: 113),
            TerminalRGB(red: 74, green: 222, blue: 128),
            TerminalRGB(red: 250, green: 204, blue: 21),
            TerminalRGB(red: 96, green: 165, blue: 250),
            TerminalRGB(red: 216, green: 180, blue: 254),
            TerminalRGB(red: 34, green: 211, blue: 238),
            TerminalRGB(red: 226, green: 232, blue: 240),
            TerminalRGB(red: 100, green: 116, blue: 139),
            TerminalRGB(red: 252, green: 165, blue: 165),
            TerminalRGB(red: 134, green: 239, blue: 172),
            TerminalRGB(red: 253, green: 224, blue: 71),
            TerminalRGB(red: 147, green: 197, blue: 253),
            TerminalRGB(red: 233, green: 213, blue: 255),
            TerminalRGB(red: 103, green: 232, blue: 249),
            TerminalRGB(red: 255, green: 255, blue: 255)
        ]
    )

    public static let standardDark = TerminalTheme(
        identifier: .standardDark,
        displayName: "Escuro padrao",
        foreground: TerminalRGB(red: 229, green: 231, blue: 235),
        background: TerminalRGB(red: 17, green: 24, blue: 39),
        accent: TerminalRGB(red: 125, green: 211, blue: 252),
        success: TerminalRGB(red: 34, green: 197, blue: 94),
        warning: TerminalRGB(red: 234, green: 179, blue: 8),
        error: TerminalRGB(red: 239, green: 68, blue: 68),
        muted: TerminalRGB(red: 156, green: 163, blue: 175),
        selection: TerminalRGB(red: 37, green: 99, blue: 235),
        caret: TerminalRGB(red: 229, green: 231, blue: 235),
        ansi16: [
            TerminalRGB(red: 17, green: 24, blue: 39),
            TerminalRGB(red: 220, green: 38, blue: 38),
            TerminalRGB(red: 22, green: 163, blue: 74),
            TerminalRGB(red: 202, green: 138, blue: 4),
            TerminalRGB(red: 37, green: 99, blue: 235),
            TerminalRGB(red: 147, green: 51, blue: 234),
            TerminalRGB(red: 8, green: 145, blue: 178),
            TerminalRGB(red: 209, green: 213, blue: 219),
            TerminalRGB(red: 75, green: 85, blue: 99),
            TerminalRGB(red: 248, green: 113, blue: 113),
            TerminalRGB(red: 74, green: 222, blue: 128),
            TerminalRGB(red: 250, green: 204, blue: 21),
            TerminalRGB(red: 96, green: 165, blue: 250),
            TerminalRGB(red: 192, green: 132, blue: 252),
            TerminalRGB(red: 34, green: 211, blue: 238),
            TerminalRGB(red: 243, green: 244, blue: 246)
        ]
    )

    public static func resolve(from environment: [String: String]) -> TerminalTheme {
        let rawValue = environment["HEALTHOS_TERMINAL_THEME"]
            ?? environment["HEALTHOS_TERMINAL_CONTRAST"]
            ?? ""
        let normalized = rawValue.lowercased().replacingOccurrences(of: "_", with: "-")

        switch normalized {
        case "standard", "standard-dark", "dark", "default", "normal":
            return .standardDark
        default:
            return .highContrast
        }
    }
}

// MARK: - Runtime Status

public enum TerminalRuntimeState: String, Sendable {
    case ready
    case running
    case stopped
    case unavailable

    public var displayName: String {
        switch self {
        case .ready:
            return "pronto"
        case .running:
            return "rodando"
        case .stopped:
            return "parado"
        case .unavailable:
            return "indisponivel"
        }
    }
}

public struct TerminalRuntimeStatus: Equatable, Sendable {
    public let runtimeName: String
    public let state: TerminalRuntimeState
    public let detail: String?

    public init(runtimeName: String, state: TerminalRuntimeState = .ready, detail: String? = nil) {
        self.runtimeName = runtimeName
        self.state = state
        self.detail = detail
    }

    public var label: String {
        if let detail, !detail.isEmpty {
            return "\(runtimeName) | \(state.displayName) | \(detail)"
        }
        return "\(runtimeName) | \(state.displayName)"
    }

    public func updating(state: TerminalRuntimeState, detail: String? = nil) -> TerminalRuntimeStatus {
        TerminalRuntimeStatus(runtimeName: runtimeName, state: state, detail: detail)
    }

    public static func resolve(from environment: [String: String]) -> TerminalRuntimeStatus {
        let runtimeName = environment["HEALTHOS_LLM_RUNTIME"]
            ?? environment["HEALTHOS_CHAT_RUNTIME"]
            ?? "Codex"
        return TerminalRuntimeStatus(runtimeName: runtimeName)
    }
}

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
    public var theme: TerminalTheme
    public var runtimeStatus: TerminalRuntimeStatus

    public init(
        title: String = "Terminal",
        workingDirectory: URL,
        environment: [String: String] = [:],
        theme: TerminalTheme? = nil,
        runtimeStatus: TerminalRuntimeStatus? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.workingDirectory = workingDirectory
        self.isRunning = false
        self.commandHistory = []

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        let resolvedTheme = theme ?? TerminalTheme.resolve(from: env)
        for (key, value) in resolvedTheme.environmentDefaults where env[key] == nil {
            env[key] = value
        }
        env["HEALTHOS_TERMINAL_THEME"] = resolvedTheme.identifier.rawValue

        self.theme = resolvedTheme
        self.runtimeStatus = runtimeStatus ?? TerminalRuntimeStatus.resolve(from: env)
        self.environment = env
    }

    /// Add a command to history.
    public func recordCommand(_ command: String) {
        commandHistory.append(command)
    }
}
