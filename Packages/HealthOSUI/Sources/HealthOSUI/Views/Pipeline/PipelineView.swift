import SwiftUI
import HealthOSCore
import HealthOSTerminal

public struct PipelineView: View {
    @Environment(WorkspaceManager.self) private var workspace
    @State private var runningStage: PipelineStage?
    @State private var runOutput = ""
    @State private var lastExitCode: Int32?

    private let runner = ProcessRunner()

    public init() {}

    private var sessions: [(PatientProfile, PatientSessionIndex)] {
        workspace.patients.flatMap { patient in
            patient.sessions.map { (patient, $0) }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                stageCards
                runLog
                sessionTable
            }
            .padding(28)
        }
        .navigationTitle("Pipeline")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pipeline clínico")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Acompanhe a cobertura por etapa e use os scripts TypeScript correspondentes quando precisar executar processamento.")
                .font(.healthCallout)
                .foregroundStyle(.secondary)
        }
    }

    private var stageCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(PipelineStage.allCases, id: \.self) { stage in
                let completed = sessions.filter { $0.1.status.isComplete(stage) }.count
                HealthOSPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: stage.systemImage)
                                .foregroundStyle(Color.healthPrimary)
                            Text(stage.displayName)
                                .font(.healthHeadline)
                            Spacer()
                            Text("\(completed)/\(sessions.count)")
                                .font(.healthCallout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: sessions.isEmpty ? 0 : Double(completed), total: Double(max(sessions.count, 1)))
                        Text(stage.npmScript)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Button {
                            run(stage)
                        } label: {
                            Label(runningStage == stage ? "Executando" : "Rodar com Codex", systemImage: runningStage == stage ? "hourglass" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(runningStage != nil)
                    }
                }
            }
        }
    }

    private var runLog: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(
                        title: "Execução Codex",
                        subtitle: "Scripts TypeScript com HEALTHOS_LLM_RUNTIME=Codex",
                        systemImage: "terminal.fill"
                    )
                    Spacer()
                    if let runningStage {
                        ProgressView()
                            .controlSize(.small)
                        Text(runningStage.displayName)
                            .font(.healthCaption)
                            .foregroundStyle(.secondary)
                    } else if let lastExitCode {
                        Text(lastExitCode == 0 ? "concluído" : "erro \(lastExitCode)")
                            .font(.healthCaption)
                            .foregroundStyle(lastExitCode == 0 ? Color.healthPositive : Color.healthDestructive)
                    }
                }

                ScrollView {
                    Text(runOutput.isEmpty ? "Nenhuma execução iniciada nesta sessão do app." : runOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(runOutput.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .padding(10)
                .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var sessionTable: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Sessões", subtitle: "Status granular por paciente", systemImage: "tablecells")

                if sessions.isEmpty {
                    EmptyStateView(title: "Nenhuma sessão", message: "As sessões aparecem aqui quando existirem em patient.json.", systemImage: "calendar.badge.exclamationmark")
                } else {
                    VStack(spacing: 10) {
                        ForEach(sessions, id: \.1.sessionId) { patient, session in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(patient.displayName)
                                        .font(.healthHeadline)
                                    Text("\(patient.patientId) · \(session.sessionId) · \(session.date?.healthOSDisplayDate ?? "sem data")")
                                        .font(.healthCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                PipelineProgressBar(status: session.status)
                                    .frame(width: 240)
                                Text("\(session.status.completedCount)/6")
                                    .font(.healthCallout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if session.sessionId != sessions.last?.1.sessionId {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func run(_ stage: PipelineStage) {
        runningStage = stage
        lastExitCode = nil
        runOutput = "$ \(stage.npmScript)\n\n"

        Task {
            var environment = ProcessInfo.processInfo.environment
            environment["HEALTHOS_BASE"] = workspace.baseDir.path
            environment["HEALTHOS_LLM_RUNTIME"] = "Codex"
            environment["HEALTHOS_CHAT_RUNTIME"] = "Codex"
            environment["HEALTHOS_CODEX_SANDBOX"] = environment["HEALTHOS_CODEX_SANDBOX"] ?? "workspace-write"
            if let professional = workspace.activeProfessional {
                environment["HEALTHOS_PROFESSIONAL_ID"] = professional.id
            }

            let dependenciesReady = await ensureNodeDependencies(environment: environment)
            guard dependenciesReady else {
                await MainActor.run {
                    runningStage = nil
                }
                return
            }

            let stream = await runner.run(
                command: "npm",
                arguments: ["run", npmScriptName(for: stage)],
                workingDirectory: workspace.baseDir,
                environment: environment
            )

            do {
                for try await output in stream {
                    await MainActor.run {
                        switch output {
                        case .stdout(let text), .stderr(let text):
                            runOutput += text
                        case .exit(let code):
                            lastExitCode = code
                            runningStage = nil
                            runOutput += "\n[exit \(code)]\n"
                            try? workspace.loadAllPatients()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    runOutput += "\nErro: \(error.localizedDescription)\n"
                    runningStage = nil
                }
            }
        }
    }

    private func ensureNodeDependencies(environment: [String: String]) async -> Bool {
        let tsxPath = workspace.baseDir
            .appendingPathComponent("node_modules")
            .appendingPathComponent(".bin")
            .appendingPathComponent("tsx")

        guard !FileManager.default.fileExists(atPath: tsxPath.path) else {
            return true
        }

        await MainActor.run {
            runOutput += "Dependências Node ausentes. Rodando npm install...\n\n"
        }

        let stream = await runner.run(
            command: "npm",
            arguments: ["install"],
            workingDirectory: workspace.baseDir,
            environment: environment
        )

        var exitCode: Int32 = -1
        do {
            for try await output in stream {
                await MainActor.run {
                    switch output {
                    case .stdout(let text), .stderr(let text):
                        runOutput += text
                    case .exit(let code):
                        exitCode = code
                        runOutput += "\n[npm install exit \(code)]\n\n"
                    }
                }
            }
        } catch {
            await MainActor.run {
                runOutput += "\nErro durante npm install: \(error.localizedDescription)\n"
            }
            return false
        }

        return exitCode == 0
    }

    private func npmScriptName(for stage: PipelineStage) -> String {
        switch stage {
        case .transcribe: "transcribe"
        case .process: "pipeline:process"
        case .speech: "pipeline:speech"
        case .asl: "pipeline:asl"
        case .vdlp: "pipeline:vdlp"
        case .gem: "pipeline:gem"
        }
    }
}
