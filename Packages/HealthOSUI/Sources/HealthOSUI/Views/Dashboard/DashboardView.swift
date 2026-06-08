import SwiftUI
import HealthOSCore

public struct DashboardView: View {
    @Environment(WorkspaceManager.self) private var workspace

    public init() {}

    private var allSessions: [PatientSessionIndex] {
        workspace.patients.flatMap(\.sessions)
    }

    private var activePatients: Int {
        workspace.patients.filter { $0.status == .active }.count
    }

    private var stats: WorkspaceManager.ProjectStats {
        workspace.computeStats()
    }

    private var recentPatients: [PatientProfile] {
        Array(workspace.patients.prefix(6))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsGrid

                HStack(alignment: .top, spacing: 16) {
                    SessionsChartCard(sessions: allSessions)
                    workspacePanel
                        .frame(width: 360)
                }

                patientOverview
            }
            .padding(28)
        }
        .navigationTitle("Dashboard")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HealthOS Clinical Workspace")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("\(workspace.activeProfessional?.nome ?? "Profissional não configurado") · \(workspace.baseDir.path)")
                .font(.healthCallout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            StatCard(title: "Pacientes", value: "\(workspace.patients.count)", icon: "person.2.fill", color: .healthPrimary, caption: "\(activePatients) ativos")
            StatCard(title: "Sessões", value: "\(stats.totalSessions)", icon: "calendar.day.timeline.left", color: .blue, caption: "indexadas")
            StatCard(title: "Análises", value: "\(stats.completedAnalyses)", icon: "checkmark.seal.fill", color: .healthPositive, caption: "sessões completas")
            StatCard(title: "Pendências", value: "\(stats.pendingStages)", icon: "exclamationmark.triangle.fill", color: .healthWarning, caption: "etapas abertas")
        }
    }

    private var workspacePanel: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Workspace", subtitle: "Arquivos e contexto ativo", systemImage: "folder.fill")
                MetricRow(title: "Profissional", value: workspace.activeProfessional?.registro ?? "n/a", systemImage: "stethoscope", color: .healthPrimary)
                MetricRow(title: "Pacientes", value: workspace.patientsDir.lastPathComponent, systemImage: "person.crop.rectangle.stack", color: .blue)
                MetricRow(title: "Áudio", value: workspace.audioDir.lastPathComponent, systemImage: "waveform", color: .orange)
                Divider()
                Text(workspace.baseDir.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    private var patientOverview: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Pacientes recentes", subtitle: "Status e cobertura do pipeline", systemImage: "list.bullet.rectangle")

                if recentPatients.isEmpty {
                    EmptyStateView(
                        title: "Nenhum paciente carregado",
                        message: "Confira se o diretório patients existe no workspace detectado.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(recentPatients) { patient in
                            HStack(spacing: 12) {
                                Text(patient.initials)
                                    .font(.healthHeadline)
                                    .foregroundStyle(Color.healthPrimary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.healthPrimary.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(patient.displayName)
                                            .font(.healthHeadline)
                                        Text(patient.status.displayName)
                                            .font(.healthCaption)
                                            .foregroundStyle(patient.status.color)
                                    }
                                    Text("\(patient.patientId) · \(patient.sessions.count) sessões")
                                        .font(.healthCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(patient.sessions.reduce(0) { $0 + $1.status.completedCount })/\(max(patient.sessions.count * 6, 1))")
                                    .font(.healthCallout)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            if patient.id != recentPatients.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}
