import Foundation
import Combine
import HealthOSCore
import HealthOSPipeline

public enum ChatMessageRole: Sendable {
    case user
    case assistant
    case system
}

public enum ChatMessageStatus: Equatable, Sendable {
    case queued
    case sending
    case sent
    case succeeded
    case failed(String)
}

public enum ChatActivityState: Equatable, Sendable {
    case idle
    case sending
    case succeeded
    case failed(String)
}

public struct ChatRuntimeMetadata: Equatable, Sendable {
    public var provider: String?
    public var runtime: String?
    public var model: String?
    public var usageSummary: String?
    public var startedAt: Date?
    public var completedAt: Date?
    public var isFallback: Bool
    public var detail: String?

    public init(
        provider: String? = nil,
        runtime: String? = nil,
        model: String? = nil,
        usageSummary: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        isFallback: Bool = false,
        detail: String? = nil
    ) {
        self.provider = provider
        self.runtime = runtime
        self.model = model
        self.usageSummary = usageSummary
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isFallback = isFallback
        self.detail = detail
    }

    public var elapsedSeconds: TimeInterval? {
        guard let startedAt, let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    public var compactSummary: String? {
        var items: [String] = []
        if let runtime, !runtime.isEmpty { items.append(runtime) }
        if let model, !model.isEmpty { items.append(model) }
        if let usageSummary, !usageSummary.isEmpty { items.append(usageSummary) }
        if isFallback { items.append("fallback local") }
        if let elapsedSeconds { items.append(String(format: "%.1fs", elapsedSeconds)) }
        return items.isEmpty ? nil : items.joined(separator: " · ")
    }
}

public struct ChatMessage: Identifiable {
    public let id: UUID
    public var text: String
    public var role: ChatMessageRole
    public var status: ChatMessageStatus
    public var metadata: ChatRuntimeMetadata

    public init(
        id: UUID = UUID(),
        text: String,
        role: ChatMessageRole,
        status: ChatMessageStatus = .succeeded,
        metadata: ChatRuntimeMetadata = ChatRuntimeMetadata()
    ) {
        self.id = id
        self.text = text
        self.role = role
        self.status = status
        self.metadata = metadata
    }

    public init(text: String, isCurrentUser: Bool) {
        self.init(text: text, role: isCurrentUser ? .user : .assistant)
    }

    public var isCurrentUser: Bool {
        role == .user
    }
}

@MainActor
public class ConversationViewModel: ObservableObject {
    @Published public var messages: [ChatMessage] = []
    @Published public var isTyping = false
    @Published public var inputText = ""
    @Published public private(set) var activityState: ChatActivityState = .idle
    @Published public private(set) var lastRuntimeSummary: String?

    private weak var workspace: WorkspaceManager?
    private var runtime: LLMRuntimeType = .defaultRuntime

    public init() {
        let now = Date()
        messages = [
            ChatMessage(
                text: "Pronto para consultar o workspace clínico via Codex local. Posso resumir pacientes, sessões, pendências do pipeline e artefatos carregados.",
                role: .assistant,
                status: .succeeded,
                metadata: ChatRuntimeMetadata(provider: "HealthOS UI", runtime: "local", completedAt: now)
            )
        ]
    }

    public func configure(workspace: WorkspaceManager, runtime: LLMRuntimeType = .defaultRuntime) {
        self.workspace = workspace
        self.runtime = runtime
    }

    public var isSendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTyping
    }

    public func sendMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isTyping else { return }

        let requestID = UUID()
        let startedAt = Date()
        messages.append(
            ChatMessage(
                id: requestID,
                text: prompt,
                role: .user,
                status: .sending,
                metadata: ChatRuntimeMetadata(provider: "HealthOS Chat", startedAt: startedAt)
            )
        )
        inputText = ""
        isTyping = true
        activityState = .sending

        Task { @MainActor in
            let outcome = await runtimeResponse(for: prompt, startedAt: startedAt)
            isTyping = false
            activityState = outcome.activityState
            lastRuntimeSummary = outcome.metadata.compactSummary
            updateMessage(id: requestID, status: outcome.userStatus, completedAt: outcome.metadata.completedAt ?? Date(), detail: outcome.userDetail)
            messages.append(
                ChatMessage(
                    text: outcome.text,
                    role: .assistant,
                    status: outcome.assistantStatus,
                    metadata: outcome.metadata
                )
            )
        }
    }

    private func runtimeResponse(for prompt: String, startedAt: Date) async -> ChatCompletionOutcome {
        guard let workspace else {
            let completedAt = Date()
            let metadata = ChatRuntimeMetadata(
                provider: "HealthOS UI",
                runtime: "local",
                startedAt: startedAt,
                completedAt: completedAt,
                isFallback: true,
                detail: "Workspace indisponível"
            )
            return ChatCompletionOutcome(
                text: "Workspace ainda não está disponível nesta conversa.",
                userStatus: .failed("Workspace indisponível"),
                assistantStatus: .failed("Workspace indisponível"),
                activityState: .failed("Workspace indisponível"),
                metadata: metadata,
                userDetail: "Workspace indisponível"
            )
        }

        let request = LLMRequest(
            userPrompt: prompt,
            systemPrompt: buildSystemPrompt(workspace: workspace),
            temperature: 0.2,
            timeoutSeconds: 600,
            useCache: false,
            model: runtime.cliName
        )

        do {
            let runner = try LLMRuntimeProviderFactory.makeProvider(for: runtime, baseDir: workspace.baseDir)
            let response = try await runner.complete(request: request)
            let completedAt = Date()
            var metadata = ChatRuntimeMetadata(
                provider: runner.name,
                runtime: response.runtime,
                model: response.model,
                usageSummary: response.usage?.compactSummary,
                startedAt: startedAt,
                completedAt: completedAt,
                isFallback: false
            )
            if response.content.isEmpty {
                metadata.isFallback = true
                metadata.detail = "Resposta vazia do Codex; fallback local aplicado"
                return ChatCompletionOutcome(
                    text: localResponse(for: prompt, workspace: workspace),
                    userStatus: .sent,
                    assistantStatus: .succeeded,
                    activityState: .succeeded,
                    metadata: metadata,
                    userDetail: nil
                )
            }
            return ChatCompletionOutcome(
                text: response.content,
                userStatus: .sent,
                assistantStatus: .succeeded,
                activityState: .succeeded,
                metadata: metadata,
                userDetail: nil
            )
        } catch {
            let detail = error.localizedDescription
            let completedAt = Date()
            let shortReason = missingLocalRuntime(detail)
                ? "\(runtime.displayName) não encontrado"
                : "\(runtime.displayName) não respondeu"
            let metadata = ChatRuntimeMetadata(
                provider: runtime.displayName,
                runtime: runtime.isLocalCLI ? "local" : "api",
                model: request.model,
                startedAt: startedAt,
                completedAt: completedAt,
                isFallback: true,
                detail: detail
            )
            if missingLocalRuntime(detail) {
                return ChatCompletionOutcome(
                    text: """
                \(runtime.displayName) não foi encontrado pelo app.

                Verifique se o comando `\(runtime.cliName)` funciona no Terminal e reinicie o app pelo Xcode. O app herda o PATH do processo e procura em caminhos locais comuns de CLIs.

                Erro: \(detail)
                """,
                    userStatus: .sent,
                    assistantStatus: .failed(shortReason),
                    activityState: .failed(shortReason),
                    metadata: metadata,
                    userDetail: nil
                )
            }
            return ChatCompletionOutcome(
                text: "\(runtime.displayName) não respondeu: \(detail)\n\n" + localResponse(for: prompt, workspace: workspace),
                userStatus: .sent,
                assistantStatus: .failed(shortReason),
                activityState: .failed(shortReason),
                metadata: metadata,
                userDetail: nil
            )
        }
    }

    private func missingLocalRuntime(_ detail: String) -> Bool {
        runtime.isLocalCLI && (
            detail.localizedCaseInsensitiveContains(runtime.cliName)
            || detail.localizedCaseInsensitiveContains("No such file")
            || detail.localizedCaseInsensitiveContains("not found")
        )
    }

    private func updateMessage(id: UUID, status: ChatMessageStatus, completedAt: Date, detail: String?) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var message = messages[index]
        message.status = status
        message.metadata.completedAt = completedAt
        if let detail {
            message.metadata.detail = detail
        }
        messages[index] = message
    }

    private func buildSystemPrompt(workspace: WorkspaceManager) -> String {
        let stats = workspace.computeStats()
        let patients = workspace.patients.prefix(12).map { patient in
            "- \(patient.patientId): \(patient.displayName), status \(patient.status.displayName), \(patient.sessions.count) sessões"
        }.joined(separator: "\n")

        return """
        Você é o chat clínico-operacional do HealthOS.
        Responda em português brasileiro, de forma objetiva e útil para o Dr. Gustavo.
        Use o contexto abaixo como fonte primária. Não invente dados clínicos ausentes.

        Workspace: \(workspace.baseDir.path)
        Profissional ativo: \(workspace.activeProfessional?.nome ?? "não configurado")
        Pacientes: \(workspace.patients.count)
        Sessões: \(stats.totalSessions)
        Análises completas: \(stats.completedAnalyses)
        Etapas pendentes: \(stats.pendingStages)

        Pacientes carregados:
        \(patients.isEmpty ? "Nenhum paciente carregado." : patients)
        """
    }

    private func localResponse(for prompt: String, workspace: WorkspaceManager) -> String {
        let lower = prompt.lowercased()
        let stats = workspace.computeStats()

        if lower.contains("paciente") || lower.contains("patients") {
            let patients = workspace.patients.prefix(5).map { patient in
                "- \(patient.displayName) (\(patient.patientId)): \(patient.sessions.count) sessões, status \(patient.status.displayName.lowercased())"
            }
            return patients.isEmpty ? "Nenhum paciente carregado no workspace atual." : "Pacientes carregados:\n" + patients.joined(separator: "\n")
        }

        if lower.contains("pipeline") || lower.contains("pend") || lower.contains("status") {
            return "Pipeline: \(stats.totalSessions) sessões, \(stats.completedAnalyses) completas e \(stats.pendingStages) etapas pendentes. Abra a aba Pipeline para ver a cobertura por estágio."
        }

        if lower.contains("workspace") || lower.contains("base") {
            return "Workspace ativo:\n\(workspace.baseDir.path)\nPacientes: \(workspace.patientsDir.path)"
        }

        if lower.contains("profissional") || lower.contains("doutor") {
            if let prof = workspace.activeProfessional {
                return "Profissional ativo: \(prof.nome), registro \(prof.registro)."
            }
            return "Nenhum profissional ativo foi carregado. Verifique professionals/active-professional.json."
        }

        return "Resumo atual: \(workspace.patients.count) pacientes, \(stats.totalSessions) sessões, \(stats.completedAnalyses) análises completas e \(stats.pendingStages) etapas pendentes."
    }
}

private struct ChatCompletionOutcome {
    let text: String
    let userStatus: ChatMessageStatus
    let assistantStatus: ChatMessageStatus
    let activityState: ChatActivityState
    let metadata: ChatRuntimeMetadata
    let userDetail: String?
}

private extension LLMUsage {
    var compactSummary: String {
        var parts = ["\(totalTokens) tokens"]
        if let cacheReadTokens, cacheReadTokens > 0 {
            parts.append("\(cacheReadTokens) cache read")
        }
        if let cacheWriteTokens, cacheWriteTokens > 0 {
            parts.append("\(cacheWriteTokens) cache write")
        }
        return parts.joined(separator: " · ")
    }
}
