import Foundation
import Combine
import HealthOSCore
import HealthOSPipeline

public struct ChatMessage: Identifiable {
    public let id = UUID()
    public let text: String
    public let isCurrentUser: Bool
}

@MainActor
public class ConversationViewModel: ObservableObject {
    @Published public var messages: [ChatMessage] = []
    @Published public var isTyping = false
    @Published public var inputText = ""

    private weak var workspace: WorkspaceManager?

    public init() {
        messages = [
            ChatMessage(text: "Pronto para consultar o workspace clínico via Codex local. Posso resumir pacientes, sessões, pendências do pipeline e artefatos carregados.", isCurrentUser: false)
        ]
    }

    public func configure(workspace: WorkspaceManager) {
        self.workspace = workspace
    }

    public func sendMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        messages.append(ChatMessage(text: prompt, isCurrentUser: true))
        inputText = ""
        isTyping = true

        Task { @MainActor in
            let reply = await codexResponse(for: prompt)
            isTyping = false
            messages.append(ChatMessage(text: reply, isCurrentUser: false))
        }
    }

    private func codexResponse(for prompt: String) async -> String {
        guard let workspace else {
            return "Workspace ainda não está disponível nesta conversa."
        }

        let request = LLMRequest(
            userPrompt: prompt,
            systemPrompt: buildSystemPrompt(workspace: workspace),
            temperature: 0.2,
            timeoutSeconds: 600,
            useCache: false,
            model: "codex-cli"
        )

        do {
            let runner = CodexRunner(workingDirectory: workspace.baseDir)
            let response = try await runner.complete(request: request)
            if response.content.isEmpty {
                return localResponse(for: prompt, workspace: workspace)
            }
            return response.content
        } catch {
            let detail = error.localizedDescription
            if detail.contains("codex") || detail.contains("No such file") {
                return """
                Codex local não foi encontrado pelo app.

                Verifique se o comando `codex` funciona no Terminal e reinicie o app pelo Xcode. O app agora procura em `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin` e `~/.local/bin`.

                Erro: \(detail)
                """
            }
            return "Codex local não respondeu: \(detail)\n\n" + localResponse(for: prompt, workspace: workspace)
        }
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
