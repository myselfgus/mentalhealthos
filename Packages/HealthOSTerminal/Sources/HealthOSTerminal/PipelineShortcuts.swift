import Foundation

// MARK: - Pipeline Shortcuts

/// Quick-access shortcuts for common pipeline and CLI commands.
public struct PipelineShortcut: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let command: String
    public let systemImage: String

    public init(id: String, label: String, command: String, systemImage: String) {
        self.id = id
        self.label = label
        self.command = command
        self.systemImage = systemImage
    }
}

public enum PipelineShortcuts {
    /// All available pipeline shortcuts in canonical order.
    public static let all: [PipelineShortcut] = [
        PipelineShortcut(
            id: "transcribe",
            label: "Transcrever",
            command: "npm run transcribe",
            systemImage: "waveform"
        ),
        PipelineShortcut(
            id: "process",
            label: "Processar",
            command: "npm run pipeline:process",
            systemImage: "doc.text.magnifyingglass"
        ),
        PipelineShortcut(
            id: "speech",
            label: "Fala Paciente",
            command: "npm run pipeline:speech",
            systemImage: "person.wave.2"
        ),
        PipelineShortcut(
            id: "asl",
            label: "ASL",
            command: "npm run pipeline:asl",
            systemImage: "text.magnifyingglass"
        ),
        PipelineShortcut(
            id: "vdlp",
            label: "VDLP",
            command: "npm run pipeline:vdlp",
            systemImage: "chart.dots.scatter"
        ),
        PipelineShortcut(
            id: "gem",
            label: "GEM",
            command: "npm run pipeline:gem",
            systemImage: "brain.head.profile"
        ),
        PipelineShortcut(
            id: "chat",
            label: "Chat CLI",
            command: "npm run chat-cli -- --runtime codex",
            systemImage: "bubble.left.and.bubble.right"
        ),
        PipelineShortcut(
            id: "codex-status",
            label: "Codex Status",
            command: "codex login status",
            systemImage: "checkmark.shield"
        ),
        PipelineShortcut(
            id: "menu",
            label: "Menu",
            command: "npm run menu",
            systemImage: "list.bullet"
        ),
    ]

    /// Find the command for a given pipeline stage name.
    public static func command(for stage: String) -> String? {
        all.first { $0.id == stage }?.command
    }
}
