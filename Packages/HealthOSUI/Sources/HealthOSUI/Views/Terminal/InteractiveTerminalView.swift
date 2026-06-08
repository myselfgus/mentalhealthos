import SwiftUI

public struct InteractiveTerminalView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Terminal")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            HealthOSPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Integração terminal", subtitle: "O pacote HealthOSTerminal está vinculado ao app", systemImage: "terminal.fill")
                    Text("A ponte visual com SwiftTerm ainda não está montada nesta tela. Use o executável HealthOSCLI para operar o menu terminal enquanto a view nativa é integrada.")
                        .font(.healthCallout)
                        .foregroundStyle(.secondary)
                    Text("swift run HealthOSCLI")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.green)
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
