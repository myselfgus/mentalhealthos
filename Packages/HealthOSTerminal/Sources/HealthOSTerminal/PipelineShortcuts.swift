import Foundation
import HealthOSCore

// MARK: - Pipeline Shortcuts

public enum PipelineShortcutInvocation: Sendable {
    case pipeline(PipelineStage)
    case nativeChat
    case nativeMenu
    case shell(String)

    public var displayCommand: String {
        switch self {
        case .pipeline(let stage):
            return "healthos:pipeline:\(stage.rawValue)"
        case .nativeChat:
            return "healthos:chat"
        case .nativeMenu:
            return "healthos:menu"
        case .shell(let command):
            return command
        }
    }
}

/// Quick-access shortcuts for common pipeline and CLI invocations.
public struct PipelineShortcut: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let detail: String
    public let invocation: PipelineShortcutInvocation
    public let systemImage: String

    public var command: String { invocation.displayCommand }
    public var commandLabel: String { "\(label): \(command)" }
    public var pipelineStage: PipelineStage? {
        if case .pipeline(let stage) = invocation {
            return stage
        }
        return nil
    }

    public init(id: String, label: String, detail: String = "", command: String, systemImage: String) {
        self.id = id
        self.label = label
        self.detail = detail
        self.invocation = .shell(command)
        self.systemImage = systemImage
    }

    public init(id: String, label: String, detail: String = "", invocation: PipelineShortcutInvocation, systemImage: String) {
        self.id = id
        self.label = label
        self.detail = detail
        self.invocation = invocation
        self.systemImage = systemImage
    }
}

public enum PipelineShortcuts {
    /// All available pipeline shortcuts in canonical order.
    public static let all: [PipelineShortcut] = [
        PipelineShortcut(
            id: "transcribe",
            label: "Transcrever",
            detail: "Audio canonico para source/transcription.json",
            invocation: .pipeline(.transcribe),
            systemImage: "waveform"
        ),
        PipelineShortcut(
            id: "process",
            label: "Processar",
            detail: "Transcricoes para workspace de pacientes",
            invocation: .pipeline(.process),
            systemImage: "doc.text.magnifyingglass"
        ),
        PipelineShortcut(
            id: "speech",
            label: "Fala Paciente",
            detail: "Extrai somente falas do paciente",
            invocation: .pipeline(.speech),
            systemImage: "person.wave.2"
        ),
        PipelineShortcut(
            id: "asl",
            label: "ASL",
            detail: "Gera analise ASL da sessao",
            invocation: .pipeline(.asl),
            systemImage: "text.magnifyingglass"
        ),
        PipelineShortcut(
            id: "vdlp",
            label: "VDLP",
            detail: "Gera leitura VDLP da sessao",
            invocation: .pipeline(.vdlp),
            systemImage: "chart.dots.scatter"
        ),
        PipelineShortcut(
            id: "gem",
            label: "GEM",
            detail: "Gera grafo emocional multicamadas",
            invocation: .pipeline(.gem),
            systemImage: "brain.head.profile"
        ),
        PipelineShortcut(
            id: "chat",
            label: "Chat CLI",
            detail: "Abre conversa nativa quando disponivel",
            invocation: .nativeChat,
            systemImage: "bubble.left.and.bubble.right"
        ),
        PipelineShortcut(
            id: "codex-status",
            label: "Codex Status",
            detail: "Verifica autenticacao local do Codex",
            command: "codex login status",
            systemImage: "checkmark.shield"
        ),
        PipelineShortcut(
            id: "menu",
            label: "Menu",
            detail: "Abre o menu terminal nativo",
            invocation: .nativeMenu,
            systemImage: "list.bullet"
        ),
    ]

    /// Find the display command for a given pipeline stage name.
    public static func command(for stage: String) -> String? {
        all.first { $0.id == stage }?.command
    }

    public static func pipelineStage(for stage: String) -> PipelineStage? {
        all.first { $0.id == stage }?.pipelineStage
    }

    public static func shortcut(for id: String) -> PipelineShortcut? {
        all.first { $0.id == id }
    }
}
