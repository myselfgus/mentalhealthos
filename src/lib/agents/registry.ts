import { existsSync } from "fs";
import { HEALTHOS_AGENTS } from "../../agents/catalog.js";
import { listCodexAgents, readCodexAgent } from "../llm/codex-agents.js";
import { listPatientAgents } from "../../patients/agents.js";
import type { AgentDefinition } from "./types.js";

export const SYSTEM_AGENT_DEFINITIONS: AgentDefinition[] = [
  {
    id: "conversation-agent",
    title: "ConversationAgent",
    source: "system",
    category: "orchestration",
    purpose: "Receber a intencao do usuario, manter posse da resposta final e coordenar especialistas.",
    runtime_policy: "llm-runtime",
    tools: ["agent-router", "event-writer"],
  },
  {
    id: "context-agent",
    title: "ContextAgent",
    source: "system",
    category: "governance",
    purpose: "Montar contexto profissional, paciente, sessao e artefatos por referencia.",
    runtime_policy: "deterministic",
    tools: ["professional_context", "patient_context", "artifact_refs"],
  },
  {
    id: "tool-runner-agent",
    title: "ToolRunnerAgent",
    source: "system",
    category: "execution",
    purpose: "Executar subprocessos, pipeline stages e tools com timeout, sandbox e trace.",
    runtime_policy: "deterministic",
    tools: ["Bash", "run_pipeline", "run_codex_subagent"],
  },
  {
    id: "transcription-agent",
    title: "TranscriptionAgent",
    source: "system",
    category: "pipeline",
    purpose: "Executar ou revisar a etapa de transcricao de audio.",
    runtime_policy: "deterministic",
    tools: ["transcribe"],
  },
  {
    id: "session-structuring-agent",
    title: "SessionStructuringAgent",
    source: "system",
    category: "pipeline",
    purpose: "Estruturar transcricoes em sessoes e dossies canonicos.",
    runtime_policy: "llm-runtime",
    tools: ["pipeline:process"],
  },
  {
    id: "speech-attribution-agent",
    title: "SpeechAttributionAgent",
    source: "system",
    category: "pipeline",
    purpose: "Extrair e conferir falas do paciente.",
    runtime_policy: "llm-runtime",
    tools: ["pipeline:speech"],
  },
  {
    id: "asl-agent",
    title: "ASLAgent",
    source: "system",
    category: "pipeline",
    purpose: "Gerar ou revisar Analise Sistemica Linguistica.",
    runtime_policy: "llm-runtime",
    tools: ["pipeline:asl"],
  },
  {
    id: "vdlp-agent",
    title: "VDLPAgent",
    source: "system",
    category: "pipeline",
    purpose: "Gerar ou revisar vetores/dimensoes do espaco mental.",
    runtime_policy: "llm-runtime",
    tools: ["pipeline:vdlp"],
  },
  {
    id: "gem-agent",
    title: "GEMAgent",
    source: "system",
    category: "pipeline",
    purpose: "Gerar ou revisar o Grafo do Espaco-Campo Mental.",
    runtime_policy: "llm-runtime",
    tools: ["pipeline:gem"],
  },
  {
    id: "patient-care-agent",
    title: "PatientCareAgent",
    source: "system",
    category: "clinical",
    purpose: "Responder tarefas clinico-operacionais de um paciente usando seu dossie.",
    runtime_policy: "llm-runtime",
    tools: ["run_patient_agent"],
  },
  {
    id: "risk-check-agent",
    title: "RiskCheckAgent",
    source: "system",
    category: "clinical-safety",
    purpose: "Checar risco clinico com evidencia direta e incerteza explicita.",
    runtime_policy: "llm-runtime",
    tools: ["run_patient_agent:risk-check"],
  },
  {
    id: "session-prep-agent",
    title: "SessionPrepAgent",
    source: "system",
    category: "clinical",
    purpose: "Preparar proxima sessao com perguntas, lacunas e temas prioritarios.",
    runtime_policy: "llm-runtime",
    tools: ["run_patient_agent:session-prep"],
  },
  {
    id: "longitudinal-reviewer-agent",
    title: "LongitudinalReviewerAgent",
    source: "system",
    category: "clinical",
    purpose: "Cruzar sessoes, memoria e analises para revisao longitudinal.",
    runtime_policy: "llm-runtime",
    tools: ["run_patient_agent:longitudinal-reviewer"],
  },
  {
    id: "safety-review-agent",
    title: "SafetyReviewAgent",
    source: "system",
    category: "clinical-safety",
    purpose: "Revisar seguranca clinica, LGPD, overclaim e evidencias antes de responder.",
    runtime_policy: "llm-runtime",
    tools: ["doublecheck", "responsible-ai"],
  },
  {
    id: "memory-agent",
    title: "MemoryAgent",
    source: "system",
    category: "memory",
    purpose: "Propor ou gravar memoria somente quando houver pedido explicito.",
    runtime_policy: "deterministic",
    tools: ["memory_policy", "/remember"],
  },
  {
    id: "qa-agent",
    title: "QAAgent",
    source: "system",
    category: "qa",
    purpose: "Validar schemas, eventos, regressao CLI e outputs dos agentes.",
    runtime_policy: "deterministic",
    tools: ["typecheck", "smoke-validation"],
  },
];

export type ListAgentDefinitionsOptions = {
  includeScenario?: boolean;
  patientId?: string;
  includeCodex?: boolean;
};

export function listAgentDefinitions(options: ListAgentDefinitionsOptions = {}): AgentDefinition[] {
  return [
    ...SYSTEM_AGENT_DEFINITIONS,
    ...listHealthOSAgentDefinitions(options.includeScenario),
    ...(options.includeCodex === false ? [] : listCodexAgentDefinitions()),
    ...(options.patientId ? listPatientAgentDefinitions(options.patientId) : []),
  ].sort((a, b) => a.id.localeCompare(b.id));
}

export function resolveAgentDefinition(id: string, options: ListAgentDefinitionsOptions = {}): AgentDefinition | null {
  return listAgentDefinitions({ ...options, includeScenario: true })
    .find((agent) => agent.id === id || agent.title.toLowerCase() === id.toLowerCase()) ?? null;
}

export function pipelineAgentId(stage: string): string {
  const map: Record<string, string> = {
    transcribe: "transcription-agent",
    process: "session-structuring-agent",
    speech: "speech-attribution-agent",
    asl: "asl-agent",
    vdlp: "vdlp-agent",
    gem: "gem-agent",
  };
  return map[stage] ?? "tool-runner-agent";
}

function listHealthOSAgentDefinitions(includeScenario = false): AgentDefinition[] {
  return HEALTHOS_AGENTS
    .filter((agent) => includeScenario || agent.availability === "active")
    .map((agent) => ({
      id: agent.id,
      title: agent.title,
      source: "healthos" as const,
      category: agent.category,
      purpose: agent.purpose,
      runtime_policy: "llm-runtime" as const,
      tools: ["prompt-injection"],
      prompt: agent.prompt,
    }));
}

function listCodexAgentDefinitions(): AgentDefinition[] {
  return listCodexAgents().map((id) => ({
    id,
    title: id,
    source: "codex" as const,
    category: "codex-subagent",
    purpose: "Subagente Codex instalado localmente em ~/.codex/agents.",
    runtime_policy: "codex-local" as const,
    tools: ["codex exec"],
    path: `~/.codex/agents/${id}.toml`,
    prompt: readCodexAgent(id) ?? undefined,
  }));
}

function listPatientAgentDefinitions(patientId: string): AgentDefinition[] {
  try {
    return listPatientAgents(patientId)
      .filter((agent) => existsSync(agent.path))
      .map((agent) => ({
        id: agent.id,
        title: agent.title,
        source: "patient" as const,
        category: agent.source,
        purpose: `Agente declarativo do paciente ${agent.patient_id}.`,
        runtime_policy: "llm-runtime" as const,
        tools: ["run_patient_agent"],
        path: agent.path,
        patient_id: agent.patient_id,
      }));
  } catch {
    return [];
  }
}
