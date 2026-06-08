import Foundation
import HealthOSCore

// MARK: - Menu Action
public struct MenuAction {
    public let key: String
    public let label: String
    public let detail: String
    public let run: () async throws -> Void

    public init(key: String, label: String, detail: String, run: @escaping () async throws -> Void) {
        self.key = key
        self.label = label
        self.detail = detail
        self.run = run
    }
}

// MARK: - Project Counts
public struct ProjectCounts {
    public var patients: Int = 0
    public var patientsWithTranscriptions: Int = 0
    public var audio: Int = 0
    public var transcripts: Int = 0
    public var speech: Int = 0
    public var asl: Int = 0
    public var vdlp: Int = 0
    public var gem: Int = 0
    
    public init() {}
}

// MARK: - Menu CLI
public final class MenuCLI {
    public let workspaceManager: WorkspaceManager
    public let runner = ProcessRunner()
    public let pipelineRunner: any PipelineStageRunning
    public var selectedRuntime: LLMRuntimeType
    public var terminalTheme: TerminalTheme

    public init(
        workspaceManager: WorkspaceManager,
        pipelineRunner: any PipelineStageRunning = NativePipelineEngineRunner(),
        selectedRuntime: LLMRuntimeType? = nil,
        terminalTheme: TerminalTheme? = nil
    ) {
        self.workspaceManager = workspaceManager
        self.pipelineRunner = pipelineRunner
        self.selectedRuntime = selectedRuntime ?? LLMRuntimePreference.resolve()
        self.terminalTheme = terminalTheme ?? TerminalTheme.resolve(from: ProcessInfo.processInfo.environment)
    }

    public func collectCounts() -> ProjectCounts {
        var counts = ProjectCounts()
        counts.patients = workspaceManager.patients.count
        let fileManager = FileManager.default
        
        for patient in workspaceManager.patients {
            var hasTranscription = false
            for session in patient.sessions {
                let ws = workspaceManager.sessionWorkspace(patientId: patient.patientId, sessionId: session.sessionId)
                
                // Audio
                if let items = try? fileManager.contentsOfDirectory(atPath: ws.audioDir.path) {
                    counts.audio += items.count
                }
                
                // Transcripts
                if fileManager.fileExists(atPath: ws.transcriptionPath.path) {
                    counts.transcripts += 1
                    hasTranscription = true
                }
                
                // Speech
                if fileManager.fileExists(atPath: ws.patientSpeechTextPath.path) ||
                   fileManager.fileExists(atPath: ws.patientSpeechJsonPath.path) ||
                   fileManager.fileExists(atPath: ws.patientSpeechMarkdownPath.path) {
                    counts.speech += 1
                }
                
                // Analysis
                if fileManager.fileExists(atPath: ws.aslPath.path) { counts.asl += 1 }
                if fileManager.fileExists(atPath: ws.vdlpPath.path) { counts.vdlp += 1 }
                if fileManager.fileExists(atPath: ws.gemPath.path) { counts.gem += 1 }
            }
            if hasTranscription {
                counts.patientsWithTranscriptions += 1
            }
        }
        return counts
    }

    public func frame(_ progress: Double) -> String {
        let width = 26
        let filled = max(0, min(width, Int(round(Double(width) * progress))))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    public var runtimeStatusLabel: String {
        TerminalRuntimeStatus(
            runtimeName: selectedRuntime.displayName,
            state: .ready,
            detail: selectedRuntime.cliName
        ).label
    }

    private var ansiEnabled: Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }

    private func styled(
        _ text: String,
        color: TerminalRGB? = nil,
        background: TerminalRGB? = nil,
        bold: Bool = false
    ) -> String {
        guard ansiEnabled else { return text }

        var prefix = ""
        if bold { prefix += "\u{001B}[1m" }
        if let color { prefix += color.ansiForeground }
        if let background { prefix += background.ansiBackground }
        return "\(prefix)\(text)\u{001B}[0m"
    }

    private func badge(_ text: String, color: TerminalRGB) -> String {
        styled("[\(text)]", color: color, bold: true)
    }

    private func shortcutDetail(_ id: String, fallback: String) -> String {
        guard let shortcut = PipelineShortcuts.shortcut(for: id) else {
            return fallback
        }
        return "\(shortcut.command) | \(shortcut.detail)"
    }

    public func intro() async {
        let steps: [(String, Double)] = [
            ("boot", 0.12),
            ("config", 0.28),
            ("patients", 0.46),
            ("runtime", 0.68),
            ("pipeline", 0.86),
            ("ready", 1.0)
        ]

        for (label, progress) in steps {
            print("\u{001B}[2J\u{001B}[H", terminator: "") // Clear screen
            print("")
            print(styled("HealthOS Psy", color: terminalTheme.accent, bold: true))
            print(styled("----------------------------------------", color: terminalTheme.muted))
            print("\(styled("workspace", color: terminalTheme.muted, bold: true)) \(workspaceManager.baseDir.path)")
            print("\(styled("runtime ", color: terminalTheme.muted, bold: true)) \(badge(runtimeStatusLabel, color: terminalTheme.accent))")
            print("\(styled("tema    ", color: terminalTheme.muted, bold: true)) \(badge(terminalTheme.displayName, color: terminalTheme.success))")
            print("")
            print("\(styled(frame(progress), color: terminalTheme.accent, bold: true)) \(Int(round(progress * 100)))%")
            print(styled(label, color: terminalTheme.muted, bold: true))
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
    }

    public func renderMenu(actions: [MenuAction]) {
        print("\n\(styled("Pipeline", color: terminalTheme.foreground, bold: true))")
        for action in actions.prefix(6) {
            print("\(badge(action.key, color: terminalTheme.accent)) \(styled(action.label, color: terminalTheme.foreground, bold: true)) \(styled(renderedDetail(for: action), color: terminalTheme.muted))")
        }

        print("\n\(styled("Operacao", color: terminalTheme.foreground, bold: true))")
        for action in actions.dropFirst(6) {
            print("\(badge(action.key, color: terminalTheme.warning)) \(styled(action.label, color: terminalTheme.foreground, bold: true)) \(styled(renderedDetail(for: action), color: terminalTheme.muted))")
        }

        print("")
        print("\(badge("0", color: terminalTheme.error)) Sair")
        print("")
    }

    private func renderedDetail(for action: MenuAction) -> String {
        if action.key.uppercased() == "R" {
            return runtimeStatusLabel
        }
        return action.detail
    }

    private func operationEnvironment() -> [String: String] {
        var env = LLMRuntimePreference.environment(
            from: ProcessInfo.processInfo.environment,
            runtime: selectedRuntime
        )
        env["HEALTHOS_BASE"] = workspaceManager.baseDir.path
        env["HEALTHOS_CODEX_SANDBOX"] = env["HEALTHOS_CODEX_SANDBOX"] ?? "workspace-write"
        for (key, value) in terminalTheme.environmentDefaults where env[key] == nil {
            env[key] = value
        }
        env["HEALTHOS_TERMINAL_THEME"] = terminalTheme.identifier.rawValue
        if let prof = workspaceManager.activeProfessional {
            env["HEALTHOS_PROFESSIONAL_ID"] = prof.id
        }
        return env
    }

    public func executeScript(command: String, args: [String], description: String) async throws {
        print("\n\(styled("Executando: \(description)", color: terminalTheme.accent, bold: true))")
        let env = operationEnvironment()

        let stream = await runner.run(command: command, arguments: args, workingDirectory: workspaceManager.baseDir, environment: env)
        for try await output in stream {
            switch output {
            case .stdout(let text):
                print(text, terminator: "")
            case .stderr(let text):
                print(text, terminator: "")
            case .exit(let code):
                if code == 0 {
                    print("\n\(styled("\(description) concluido.", color: terminalTheme.success, bold: true))")
                } else {
                    print("\n\(styled("\(description) terminou com codigo \(code).", color: terminalTheme.error, bold: true))")
                }
            }
        }
    }

    public func executePipelineStage(_ stage: PipelineStage, description: String) async throws {
        print("\n\(styled("Executando etapa Swift: \(description)", color: terminalTheme.accent, bold: true))")
        let context = TerminalPipelineExecutionContext(
            workspaceManager: workspaceManager,
            runtime: selectedRuntime,
            environment: operationEnvironment()
        )
        let result = try await pipelineRunner.run(stage: stage, context: context)
        print(styled(result.message, color: terminalTheme.success, bold: true))
        if !result.outputRefs.isEmpty {
            print(styled("Outputs: \(result.outputRefs.joined(separator: ", "))", color: terminalTheme.muted))
        }
    }

    public func buildActions() -> [MenuAction] {
        return [
            MenuAction(key: "1", label: "Transcrever audios", detail: self.shortcutDetail("transcribe", fallback: "sessions/*/source/audio -> source/transcription.json")) {
                try await self.executePipelineStage(.transcribe, description: "Transcrever audios")
            },
            MenuAction(key: "2", label: "Processar transcricoes", detail: self.shortcutDetail("process", fallback: "legado: audio/transcriptions -> patients/PAT_000001")) {
                try await self.executePipelineStage(.process, description: "Processar transcricoes")
            },
            MenuAction(key: "3", label: "Extrair fala do paciente", detail: self.shortcutDetail("speech", fallback: "sessions/source -> sessions/analysis/patient-speech")) {
                try await self.executePipelineStage(.speech, description: "Extrair fala do paciente")
            },
            MenuAction(key: "4", label: "Gerar ASL", detail: self.shortcutDetail("asl", fallback: "sessions/analysis/asl.json")) {
                try await self.executePipelineStage(.asl, description: "Gerar ASL")
            },
            MenuAction(key: "5", label: "Gerar VDLP", detail: self.shortcutDetail("vdlp", fallback: "sessions/analysis/vdlp.json")) {
                try await self.executePipelineStage(.vdlp, description: "Gerar VDLP")
            },
            MenuAction(key: "6", label: "Gerar GEM", detail: self.shortcutDetail("gem", fallback: "sessions/analysis/gem.json")) {
                try await self.executePipelineStage(.gem, description: "Gerar GEM")
            },
            MenuAction(key: "C", label: "Chat CLI", detail: self.shortcutDetail("chat", fallback: "healthos:chat | aguardando runner Swift nativo")) {
                print("Chat CLI nativo ainda nao conectado. Use o terminal livre para comandos explicitos se precisar do legado.")
            },
            MenuAction(key: "T", label: "Chat do paciente", detail: "abrir chat-agent com contexto de um paciente") {
                print("Selecione um paciente (funcionalidade CLI nativa ainda não completa)")
            },
            MenuAction(key: "P", label: "Explorar pacientes", detail: "abrir dossies e arquivos") {
                print("Explorar pacientes (funcionalidade CLI nativa ainda não completa)")
            },
            MenuAction(key: "S", label: "Status do projeto", detail: "pastas, arquivos e outputs") {
                let counts = self.collectCounts()
                print("Status: \(counts.patients) pacientes, \(counts.audio) audios, \(counts.transcripts) transcricoes")
            },
            MenuAction(key: "R", label: "Runtime LLM", detail: "atual: \(self.selectedRuntime.displayName)") {
                self.selectedRuntime = self.nextRuntime(after: self.selectedRuntime)
                LLMRuntimePreference.persist(self.selectedRuntime)
                print("Runtime selecionado: \(self.selectedRuntime.displayName) (\(self.selectedRuntime.rawValue))")
            },
            MenuAction(key: "O", label: "Profissional", detail: "gerenciar workspace profissional") {
                print("Profissional ativo: \(self.workspaceManager.activeProfessional?.id ?? "Nenhum")")
            },
            MenuAction(key: "K", label: "Limpar outputs", detail: "remove dossies em patients/") {
                print("Limpeza via CLI nativo (cuidado)")
            }
        ]
    }

    private func nextRuntime(after runtime: LLMRuntimeType) -> LLMRuntimeType {
        let runtimes = LLMRuntimeType.allCases
        guard let index = runtimes.firstIndex(of: runtime) else {
            return .defaultRuntime
        }
        return runtimes[(index + 1) % runtimes.count]
    }
}
