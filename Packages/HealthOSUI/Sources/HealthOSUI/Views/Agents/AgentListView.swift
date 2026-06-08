import SwiftUI
import HealthOSCore
import HealthOSAgents

public struct AgentListView: View {
    public init() {}

    private var tools: [LocalToolDescriptor] { healthOSTools }
    private var definitions: [AgentDefinition] { AgentRegistry.shared.listAgentDefinitions() }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agentes e ferramentas")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Catálogo operacional exposto pelo pacote HealthOSAgents.")
                        .font(.healthCallout)
                        .foregroundStyle(.secondary)
                }

                HealthOSPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Ferramentas locais", subtitle: "Operações clínicas disponíveis para o runtime Swift", systemImage: "wrench.and.screwdriver.fill")
                        ForEach(tools, id: \.name) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.name)
                                    .font(.healthHeadline.monospaced())
                                Text(tool.description)
                                    .font(.healthCallout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            if tool.name != tools.last?.name { Divider() }
                        }
                    }
                }

                HealthOSPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Registry", subtitle: "Definições multiagente carregadas", systemImage: "cpu.fill")
                        if definitions.isEmpty {
                            EmptyStateView(title: "Registry vazio", message: "AgentRegistry ainda não possui definições carregadas neste pacote Swift.", systemImage: "tray")
                        } else {
                            ForEach(definitions, id: \.id) { agent in
                                Text(agent.id)
                                    .font(.healthHeadline)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Agentes")
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
