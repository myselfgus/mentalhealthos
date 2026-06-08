import SwiftUI
import HealthOSCore

public struct ConversationView: View {
    @Environment(WorkspaceManager.self) private var workspace
    @StateObject private var viewModel = ConversationViewModel()
    private let runtime: LLMRuntimeType

    public init(runtime: LLMRuntimeType = .defaultRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            Divider()
            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.configure(workspace: workspace, runtime: runtime)
        }
        .onChange(of: runtime) { _, newValue in
            viewModel.configure(workspace: workspace, runtime: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(Color.healthPrimary)
                .frame(width: 34, height: 34)
                .background(Color.healthPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Conversa clínica")
                    .font(.healthHeadline)
                Text("\(workspace.patients.count) pacientes · \(runtime.displayName) · \(workspace.activeProfessional?.nome ?? "profissional não configurado")")
                    .font(.healthCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ChatSystemStatusView(state: viewModel.activityState, runtimeSummary: viewModel.lastRuntimeSummary)
        }
        .padding(16)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isTyping {
                        HStack {
                            TypingIndicatorView(title: "Consultando \(runtime.displayName)", detail: "Aguardando resposta do runtime")
                            Spacer()
                        }
                        .id("typingIndicator")
                    }
                }
                .padding(18)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isTyping) { _, isTyping in
                if isTyping {
                    withAnimation { proxy.scrollTo("typingIndicator", anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Pergunte sobre pacientes, sessões, pipeline ou artefatos...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit { viewModel.sendMessage() }
                .disabled(viewModel.isTyping)

            Button(action: viewModel.sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(viewModel.isSendDisabled ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSendDisabled)
            .help(viewModel.isTyping ? "Aguardando resposta" : "Enviar mensagem")
        }
        .padding(16)
        .background(.bar)
    }
}

private struct ChatSystemStatusView: View {
    let state: ChatActivityState
    let runtimeSummary: String?

    var body: some View {
        HStack(spacing: 7) {
            symbol
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.healthCaption)
                    .fontWeight(.semibold)
                if let runtimeSummary, state != .sending {
                    Text(runtimeSummary)
                        .font(.healthCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
        .frame(maxWidth: 260, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var symbol: some View {
        switch state {
        case .sending:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
        case .idle:
            Image(systemName: "circle")
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var title: String {
        switch state {
        case .idle:
            "Pronto"
        case .sending:
            "Enviando"
        case .succeeded:
            "Concluído"
        case .failed(let reason):
            reason
        }
    }

    private var color: Color {
        switch state {
        case .idle:
            .secondary
        case .sending:
            .healthPrimary
        case .succeeded:
            .healthPositive
        case .failed:
            .healthDestructive
        }
    }
}
