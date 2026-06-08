import SwiftUI
import HealthOSCore
import HealthOSUI

/// Root view with NavigationSplitView and LiquidGlass sidebar.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            sidebar
                .navigationTitle("HealthOS")
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Bindable(appState).selectedSection) {
            Section("Principal") {
                sidebarItem(.dashboard)
                sidebarItem(.chat)
            }

            Section("Clínica") {
                sidebarItem(.consultation)
                sidebarItem(.patients)
                sidebarItem(.pipeline)
            }

            Section("Ferramentas") {
                sidebarItem(.terminal)
                sidebarItem(.agents)
            }

            Section("Sistema") {
                sidebarItem(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            professionalBadge
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private func sidebarItem(_ section: SidebarSection) -> some View {
        Label(section.displayName, systemImage: section.systemImage)
            .tag(section)
    }

    // MARK: - Professional Badge

    private var professionalBadge: some View {
        Group {
            if let prof = appState.workspaceManager.activeProfessional {
                HStack(spacing: 8) {
                    Image(systemName: "stethoscope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(prof.nome)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(prof.registro)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if appState.isLoading {
            ProgressView("Carregando workspace...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appState.selectedSection {
            case .dashboard:
                DashboardView()
            case .chat:
                ConversationView()
            case .consultation:
                ConsultationIntakeView()
            case .patients:
                PatientListView()
            case .pipeline:
                PipelineView()
            case .terminal:
                InteractiveTerminalView()
            case .agents:
                AgentListView()
            case .settings:
                SettingsView()
            }
        }
    }
}
