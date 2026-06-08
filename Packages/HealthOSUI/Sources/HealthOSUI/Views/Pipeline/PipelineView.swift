import SwiftUI
import HealthOSCore
import HealthOSPipeline

public struct PipelineView: View {
    @Environment(WorkspaceManager.self) private var workspace
    @State private var runningStage: PipelineStage?
    @State private var runOutput = ""

    private let engine = PipelineEngine()

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
            Text("Acompanhe a cobertura por etapa e execute o processamento clínico nativo em Swift.")
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
                        Text(stage.nativeCommand.shellString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Button {
                            run(stage)
                        } label: {
                            Label(runningStage == stage ? "Executando" : "Rodar", systemImage: runningStage == stage ? "hourglass" : "play.fill")
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
                        title: "Execução nativa",
                        subtitle: "Executor Swift HealthOSPipeline",
                        systemImage: "terminal.fill"
                    )
                    Spacer()
                    if let runningStage {
                        ProgressView()
                            .controlSize(.small)
                        Text(runningStage.displayName)
                            .font(.healthCaption)
                            .foregroundStyle(.secondary)
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
        let pendingSessions = sessions
            .filter { !$0.1.status.isComplete(stage) }
            .map { (patient: $0.0, session: $0.1) }

        runningStage = stage
        runOutput = """
        $ \(stage.nativeCommand.shellString)
        Workspace: \(workspace.baseDir.path)
        Etapa: \(stage.displayName)
        Sessoes pendentes: \(pendingSessions.count)

        """

        guard !pendingSessions.isEmpty else {
            runOutput += "Nenhuma sessao pendente para \(stage.displayName).\n"
            runningStage = nil
            return
        }

        let baseDir = workspace.baseDir
        Task {
            for target in pendingSessions {
                let result = await engine.run(
                    stage: stage,
                    baseDir: baseDir,
                    patientId: target.patient.patientId,
                    sessionId: target.session.sessionId
                )

                await MainActor.run {
                    runOutput += format(result, patientId: target.patient.patientId, sessionId: target.session.sessionId)
                }
            }

            await MainActor.run {
                try? workspace.loadAllPatients()
                runningStage = nil
                runOutput += "\n[finalizado]\n"
            }
        }
    }

    private func format(_ result: PipelineStageResult, patientId: String, sessionId: String) -> String {
        let artifacts = result.artifacts.map(\.path)
        let artifactLine = artifacts.isEmpty ? "" : "\n  outputs: \(artifacts.joined(separator: ", "))"
        let errorLine = result.error.map { "\n  erro: \($0.code) - \($0.details ?? $0.message)" } ?? ""
        return "[\(result.status.rawValue)] \(patientId)/\(sessionId): \(result.message)\(artifactLine)\(errorLine)\n"
    }
}
