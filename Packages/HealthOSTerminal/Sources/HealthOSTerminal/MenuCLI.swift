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
    public var selectedRuntime = "Codex"

    public init(workspaceManager: WorkspaceManager) {
        self.workspaceManager = workspaceManager
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
            print("\u{001B}[36m\u{001B}[1mHealthOS Psy\u{001B}[0m")
            print("\u{001B}[2m----------------------------------------\u{001B}[0m")
            print("\u{001B}[2mworkspace\u{001B}[0m \(workspaceManager.baseDir.path)")
            print("\u{001B}[2mruntime  \u{001B}[0m \u{001B}[35m[\(selectedRuntime)]\u{001B}[0m")
            print("")
            print("\u{001B}[36m\(frame(progress))\u{001B}[0m \(Int(round(progress * 100)))%")
            print("\u{001B}[2m\(label)\u{001B}[0m")
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
    }

    public func renderMenu(actions: [MenuAction]) {
        print("\n\u{001B}[1mPipeline\u{001B}[0m")
        for action in actions.prefix(6) {
            print("\u{001B}[36m[\(action.key)]\u{001B}[0m \u{001B}[1m\(action.label)\u{001B}[0m \u{001B}[2m\(action.detail)\u{001B}[0m")
        }

        print("\n\u{001B}[1mOperacao\u{001B}[0m")
        for action in actions.dropFirst(6) {
            print("\u{001B}[35m[\(action.key)]\u{001B}[0m \u{001B}[1m\(action.label)\u{001B}[0m \u{001B}[2m\(action.detail)\u{001B}[0m")
        }

        print("")
        print("\u{001B}[31m[0]\u{001B}[0m Sair")
        print("")
    }

    public func executeScript(command: String, args: [String], description: String) async throws {
        print("\n\u{001B}[36mExecutando: \(description)\u{001B}[0m")
        var env = ProcessInfo.processInfo.environment
        env["HEALTHOS_BASE"] = workspaceManager.baseDir.path
        env["HEALTHOS_LLM_RUNTIME"] = selectedRuntimeName
        env["HEALTHOS_CHAT_RUNTIME"] = selectedRuntimeName
        env["HEALTHOS_CODEX_SANDBOX"] = env["HEALTHOS_CODEX_SANDBOX"] ?? "workspace-write"
        if let prof = workspaceManager.activeProfessional {
            env["HEALTHOS_PROFESSIONAL_ID"] = prof.id
        }

        if command == "npm" {
            try await ensureNodeDependencies(environment: env)
        }

        let stream = await runner.run(command: command, arguments: args, workingDirectory: workspaceManager.baseDir, environment: env)
        for try await output in stream {
            switch output {
            case .stdout(let text):
                print(text, terminator: "")
            case .stderr(let text):
                print(text, terminator: "")
            case .exit(let code):
                if code == 0 {
                    print("\n\u{001B}[32m\(description) concluido.\u{001B}[0m")
                } else {
                    print("\n\u{001B}[31m\(description) terminou com codigo \(code).\u{001B}[0m")
                }
            }
        }
    }

    private func ensureNodeDependencies(environment: [String: String]) async throws {
        let tsxPath = workspaceManager.baseDir
            .appendingPathComponent("node_modules")
            .appendingPathComponent(".bin")
            .appendingPathComponent("tsx")

        guard !FileManager.default.fileExists(atPath: tsxPath.path) else {
            return
        }

        print("\u{001B}[33mDependências Node ausentes. Rodando npm install...\u{001B}[0m")
        let stream = await runner.run(
            command: "npm",
            arguments: ["install"],
            workingDirectory: workspaceManager.baseDir,
            environment: environment
        )

        var exitCode: Int32 = -1
        for try await output in stream {
            switch output {
            case .stdout(let text), .stderr(let text):
                print(text, terminator: "")
            case .exit(let code):
                exitCode = code
            }
        }

        guard exitCode == 0 else {
            throw NSError(
                domain: "HealthOSTerminal",
                code: Int(exitCode),
                userInfo: [NSLocalizedDescriptionKey: "npm install terminou com codigo \(exitCode)."]
            )
        }
    }

    public func buildActions() -> [MenuAction] {
        return [
            MenuAction(key: "1", label: "Transcrever audios", detail: "sessions/*/source/audio -> source/transcription.json") {
                try await self.executeScript(command: "npm", args: ["run", "transcribe"], description: "Transcrever audios")
            },
            MenuAction(key: "2", label: "Processar transcricoes", detail: "legado: audio/transcriptions -> patients/PAT_000001") {
                try await self.executeScript(command: "npm", args: ["run", "pipeline:process"], description: "Processar transcricoes")
            },
            MenuAction(key: "3", label: "Extrair fala do paciente", detail: "sessions/source -> sessions/analysis/patient-speech") {
                try await self.executeScript(command: "npm", args: ["run", "pipeline:speech"], description: "Extrair fala do paciente")
            },
            MenuAction(key: "4", label: "Gerar ASL", detail: "sessions/analysis/asl.json") {
                try await self.executeScript(command: "npm", args: ["run", "pipeline:asl"], description: "Gerar ASL")
            },
            MenuAction(key: "5", label: "Gerar VDLP", detail: "sessions/analysis/vdlp.json") {
                try await self.executeScript(command: "npm", args: ["run", "pipeline:vdlp"], description: "Gerar VDLP")
            },
            MenuAction(key: "6", label: "Gerar GEM", detail: "sessions/analysis/gem.json") {
                try await self.executeScript(command: "npm", args: ["run", "pipeline:gem"], description: "Gerar GEM")
            },
            MenuAction(key: "C", label: "Chat CLI", detail: "chat com Codex local") {
                let runtimeFlag = self.selectedRuntimeName == "Codex" ? "codex" : "claude"
                try await self.executeScript(command: "npm", args: ["run", "chat-cli", "--", "--runtime", runtimeFlag], description: "HealthOS Chat CLI")
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
            MenuAction(key: "R", label: "Runtime LLM", detail: "atual: \(self.selectedRuntime)") {
                self.selectedRuntime = self.selectedRuntimeName == "Codex" ? "ClaudeCode" : "Codex"
                print("Runtime selecionado: \(self.selectedRuntimeName)")
            },
            MenuAction(key: "O", label: "Profissional", detail: "gerenciar workspace profissional") {
                print("Profissional ativo: \(self.workspaceManager.activeProfessional?.id ?? "Nenhum")")
            },
            MenuAction(key: "K", label: "Limpar outputs", detail: "remove dossies em patients/") {
                print("Limpeza via CLI nativo (cuidado)")
            }
        ]
    }

    private var selectedRuntimeName: String {
        switch selectedRuntime.lowercased() {
        case "codex":
            return "Codex"
        case "claudecode", "claude-code", "claude_code", "claude":
            return "ClaudeCode"
        default:
            return "ClaudeAPI"
        }
    }
}
