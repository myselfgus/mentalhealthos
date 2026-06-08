export type HealthOSAgentAvailability = "active" | "scenario";

export type HealthOSAgent = {
  id: string;
  title: string;
  category: string;
  availability: HealthOSAgentAvailability;
  purpose: string;
  useWhen: string[];
  avoidWhen?: string[];
  prompt: string;
};

export const HEALTHOS_AGENTS: HealthOSAgent[] = [
  {
    id: "context-architect",
    title: "Context Architect",
    category: "governance",
    availability: "active",
    purpose: "Mapear contexto profissional, paciente, sessão e artefatos antes de acionar análise ou execução.",
    useWhen: [
      "A tarefa precisa reunir referências de paciente, sessão, memória, prompts ou outputs de pipeline.",
      "O usuário pede planejamento, auditoria de contexto ou preparação de uma execução clínica.",
    ],
    avoidWhen: [
      "A solicitação é uma pergunta simples que pode ser respondida diretamente pelo chat.",
    ],
    prompt: "Organize o contexto em referências verificáveis, explicite lacunas e recomende o próximo agente ou estágio do pipeline. Não invente dados ausentes.",
  },
  {
    id: "pipeline-operator",
    title: "Pipeline Operator",
    category: "pipeline",
    availability: "active",
    purpose: "Executar e revisar etapas transcribe, process, speech, ASL, VDLP e GEM com rastreabilidade.",
    useWhen: [
      "O usuário pede para rodar, reparar ou conferir um estágio do pipeline.",
      "Há falha em script, output ausente ou inconsistência entre patient.json e artefatos da sessão.",
    ],
    prompt: "Atue como operador técnico do pipeline HealthOS. Preserve arquivos existentes, relate comandos, entradas, saídas e erros. Use Codex local quando a tarefa exigir subprocesso ou edição.",
  },
  {
    id: "clinical-synthesizer",
    title: "Clinical Synthesizer",
    category: "clinical",
    availability: "active",
    purpose: "Sintetizar achados clínicos a partir de dossiê, ASL, VDLP, GEM, memória e histórico longitudinal.",
    useWhen: [
      "O usuário pede resumo clínico, preparação de sessão, hipóteses ou integração de análises.",
      "Há múltiplos artefatos clínicos que precisam ser conectados em linguagem operacional.",
    ],
    avoidWhen: [
      "A tarefa pede diagnóstico definitivo sem evidências suficientes.",
    ],
    prompt: "Produza sínteses clínicas com evidência explícita, incerteza proporcional e linguagem útil para o profissional. Não extrapole para além dos dados carregados.",
  },
  {
    id: "risk-safety-reviewer",
    title: "Risk Safety Reviewer",
    category: "clinical-safety",
    availability: "active",
    purpose: "Revisar risco clínico, privacidade, LGPD, overclaim e segurança da resposta.",
    useWhen: [
      "A resposta envolve risco, ideação suicida, automutilação, medicação, diagnóstico ou conduta clínica.",
      "Antes de entregar sínteses clínicas sensíveis ou recomendações operacionais.",
    ],
    prompt: "Revise a resposta com foco em segurança clínica, limites de evidência, privacidade e conduta responsável. Aponte lacunas e reformule quando necessário.",
  },
  {
    id: "patient-agent-builder",
    title: "Patient Agent Builder",
    category: "patient-agents",
    availability: "scenario",
    purpose: "Criar ou revisar agentes declarativos específicos de paciente em care-agent.md e patients/<PAT_ID>/agents.",
    useWhen: [
      "O usuário pede um agente para um caso/paciente específico.",
      "É necessário transformar o dossiê em instruções operacionais persistentes.",
    ],
    prompt: "Construa agentes de paciente com escopo estreito, instruções clínicas prudentes, referências ao dossiê e regras de privacidade. Evite memória implícita.",
  },
  {
    id: "qa-validator",
    title: "QA Validator",
    category: "qa",
    availability: "active",
    purpose: "Validar schemas, outputs, CLI, app Swift e regressões depois de mudanças.",
    useWhen: [
      "Depois de alterar código Swift ou TypeScript.",
      "Quando scripts, builds, schemas ou imports falham.",
    ],
    prompt: "Priorize falhas reproduzíveis, erros de build, imports quebrados, schemas inválidos e regressões de UX. Sugira correções pequenas e verificáveis.",
  },
];

export function getHealthOSAgent(id: string): HealthOSAgent | undefined {
  const normalized = id.trim().toLowerCase();
  return HEALTHOS_AGENTS.find((agent) =>
    agent.id.toLowerCase() === normalized ||
    agent.title.toLowerCase() === normalized
  );
}
