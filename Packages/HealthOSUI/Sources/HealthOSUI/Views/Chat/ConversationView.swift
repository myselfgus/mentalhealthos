import SwiftUI
import HealthOSCore

public struct ConversationView: View {
    @Environment(WorkspaceManager.self) private var workspace
    @StateObject private var viewModel = ConversationViewModel()

    public init() {}

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
            viewModel.configure(workspace: workspace)
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
                Text("\(workspace.patients.count) pacientes · \(workspace.activeProfessional?.nome ?? "profissional não configurado")")
                    .font(.healthCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(text: message.text, isCurrentUser: message.isCurrentUser)
                            .id(message.id)
                    }

                    if viewModel.isTyping {
                        HStack {
                            TypingIndicatorView()
                            Spacer()
                        }
                        .id("typingIndicator")
                    }
                }
                .padding(18)
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isTyping) { isTyping in
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

            Button(action: viewModel.sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(viewModel.inputText.isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.isEmpty)
        }
        .padding(16)
        .background(.bar)
    }
}
