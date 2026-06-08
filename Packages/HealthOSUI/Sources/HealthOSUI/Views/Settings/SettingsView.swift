import SwiftUI
import HealthOSCore

public struct SettingsView: View {
    @Environment(WorkspaceManager.self) private var workspace
    @AppStorage(LLMRuntimePreference.userDefaultsKey) private var runtimeRawValue = LLMRuntimeType.defaultRuntime.rawValue

    public init() {}

    public var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Base", value: workspace.baseDir.path)
                LabeledContent("Pacientes", value: workspace.patientsDir.path)
                LabeledContent("Profissionais", value: workspace.professionalsDir.path)
            }

            Section("Profissional ativo") {
                if let professional = workspace.activeProfessional {
                    LabeledContent("Nome", value: professional.nome)
                    LabeledContent("Registro", value: professional.registro)
                    if let context = professional.disambiguationContext {
                        LabeledContent("Contexto", value: context)
                    }
                } else {
                    Text("Nenhum profissional ativo configurado.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Runtime LLM") {
                Picker("Runtime", selection: selectedRuntime) {
                    ForEach(LLMRuntimeType.allCases) { runtime in
                        Text(runtime.displayName).tag(runtime)
                    }
                }

                let runtime = selectedRuntime.wrappedValue
                LabeledContent("CLI", value: runtime.cliName)
                Text(runtime.selectionHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configurações")
    }

    private var selectedRuntime: Binding<LLMRuntimeType> {
        Binding {
            LLMRuntimeType(preferenceValue: runtimeRawValue) ?? .defaultRuntime
        } set: { runtime in
            runtimeRawValue = runtime.rawValue
        }
    }
}
