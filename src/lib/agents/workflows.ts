import { execSync } from "child_process";
import { existsSync } from "fs";
import { relative } from "path";
import { PATHS } from "../../config/defaults.js";
import { runPatientAgent } from "../../patients/agents.js";
import {
  getPatientSessionWorkspace,
  getPatientWorkspace,
  listPatientSessionWorkspaces,
} from "../../patients/workspace.js";
import { generateRuntimeText } from "../llm/runtime.js";
import type { LLMRuntimeName } from "../llm/types.js";
import { createRunId } from "./ids.js";
import { ConversationOrchestrator } from "./orchestrator.js";
import { pipelineAgentId } from "./registry.js";
import type { AgentResult } from "./types.js";

export type PipelineWorkflowStage = "process" | "speech" | "asl" | "vdlp" | "gem";

export type AgentWorkflowKind =
  | "clinical_care"
  | "clinical_risk_check"
  | "clinical_session_prep"
  | "clinical_longitudinal_review"
  | "pipeline_stage";

export type AgentWorkflowDetection = {
  kind: AgentWorkflowKind;
  agentId: string;
  patientAgentId?: string;
  stage?: PipelineWorkflowStage;
  requiresPatient: boolean;
  reviewRequired: boolean;
};

export type AgentWorkflowStep = {
  agent_id: string;
  content: string;
  output_refs: string[];
};

export type AgentWorkflowResult = AgentResult & {
  workflow_kind: AgentWorkflowKind;
  agent_outputs: AgentWorkflowStep[];
  trace: {
    conversation_id: string;
    run_id: string;
    task_id: string;
  };
};

export type RunAgentWorkflowParams = {
  input: string;
  patientId?: string;
  sessionId?: string;
  stage?: PipelineWorkflowStage;
  runtime?: LLMRuntimeName;
  orchestrator?: ConversationOrchestrator;
  review?: boolean;
};

const STAGE_SCRIPT_MAP: Record<PipelineWorkflowStage, string> = {
  process: "pipeline:process",
  speech: "pipeline:speech",
  asl: "pipeline:asl",
  vdlp: "pipeline:vdlp",
  gem: "pipeline:gem",
};

export function detectAgentWorkflow(
  input: string,
  options: { patientId?: string; stage?: PipelineWorkflowStage } = {},
): AgentWorkflowDetection | null {
  const text = normalize(input);
  const stage = options.stage ?? detectPipelineStage(text);
  if (stage) {
    return {
      kind: "pipeline_stage",
      agentId: pipelineAgentId(stage),
      stage,
      requiresPatient: false,
      reviewRequired: false,
    };
  }

  if (mentionsRisk(text)) {
    return {
      kind: "clinical_risk_check",
      agentId: "risk-check-agent",
      patientAgentId: "risk-check",
      requiresPatient: true,
      reviewRequired: true,
    };
  }

  if (mentionsSessionPrep(text)) {
    return {
      kind: "clinical_session_prep",
      agentId: "session-prep-agent",
      patientAgentId: "session-prep",
      requiresPatient: true,
      reviewRequired: true,
    };
  }

  if (mentionsLongitudinalReview(text)) {
    return {
      kind: "clinical_longitudinal_review",
      agentId: "longitudinal-reviewer-agent",
      patientAgentId: "longitudinal-reviewer",
      requiresPatient: true,
      reviewRequired: true,
    };
  }

  if (options.patientId && mentionsClinicalCare(text)) {
    return {
      kind: "clinical_care",
      agentId: "patient-care-agent",
      requiresPatient: true,
      reviewRequired: true,
    };
  }

  return null;
}

export async function runAgentWorkflow(params: RunAgentWorkflowParams): Promise<AgentWorkflowResult> {
  const detection = detectAgentWorkflow(params.input, {
    patientId: params.patientId,
    stage: params.stage,
  });
  if (!detection) {
    throw new Error("Nenhum workflow multiagente reconhecido para esta entrada.");
  }

  const orchestrator = params.orchestrator ?? new ConversationOrchestrator({
    patientId: params.patientId,
    sessionId: params.sessionId,
    runtime: params.runtime ?? "deterministic",
  });
  const runId = createRunId();
  const agentOutputs: AgentWorkflowStep[] = [];
  const contextRefs = collectContextRefs(params.patientId, params.sessionId);

  const contextTask = orchestrator.createTask(params.input, {
    agentId: "context-agent",
    kind: "governance",
    inputRefs: contextRefs,
    patientId: params.patientId,
    sessionId: params.sessionId,
    runId,
  });
  const contextResult = await orchestrator.runTask(contextTask, async () => ({
    status: "completed",
    content: renderContextSummary(contextRefs, params.patientId, params.sessionId),
    output_refs: contextRefs,
  }));
  agentOutputs.push({
    agent_id: contextTask.agent_id,
    content: contextResult.content,
    output_refs: contextResult.output_refs,
  });

  const primaryTask = orchestrator.createTask(params.input, {
    agentId: detection.agentId,
    kind: detection.kind === "pipeline_stage" ? "pipeline" : "clinical",
    inputRefs: contextRefs,
    patientId: params.patientId,
    sessionId: params.sessionId,
    runId,
  });
  const primaryResult = detection.kind === "pipeline_stage"
    ? await runPipelineStep(orchestrator, primaryTask, detection.stage!)
    : await runClinicalStep(orchestrator, primaryTask, params, detection, contextResult.content);

  agentOutputs.push({
    agent_id: primaryTask.agent_id,
    content: primaryResult.content,
    output_refs: primaryResult.output_refs,
  });

  if (primaryResult.status === "failed") {
    return {
      ...primaryResult,
      workflow_kind: detection.kind,
      agent_outputs: agentOutputs,
      trace: {
        conversation_id: orchestrator.conversationId,
        run_id: runId,
        task_id: primaryTask.task_id,
      },
    };
  }

  const needsReview = params.review ?? detection.reviewRequired;
  if (!needsReview) {
    return {
      ...primaryResult,
      workflow_kind: detection.kind,
      agent_outputs: agentOutputs,
      trace: {
        conversation_id: orchestrator.conversationId,
        run_id: runId,
        task_id: primaryTask.task_id,
      },
    };
  }

  const reviewTask = orchestrator.createTask(params.input, {
    agentId: "safety-review-agent",
    kind: "governance",
    inputRefs: [...contextRefs, ...primaryResult.output_refs],
    patientId: params.patientId,
    sessionId: params.sessionId,
    runId,
  });
  const reviewResult = await orchestrator.runTask(reviewTask, async () => ({
    status: "completed",
    content: await reviewClinicalOutput(params.input, primaryResult.content, params.runtime),
    output_refs: primaryResult.output_refs,
  }));
  agentOutputs.push({
    agent_id: reviewTask.agent_id,
    content: reviewResult.content,
    output_refs: reviewResult.output_refs,
  });

  return {
    status: "completed",
    content: [
      "## Resposta do especialista",
      primaryResult.content,
      "",
      "## Revisao de seguranca",
      reviewResult.content,
    ].join("\n"),
    output_refs: [...new Set([...primaryResult.output_refs, ...reviewResult.output_refs])],
    workflow_kind: detection.kind,
    agent_outputs: agentOutputs,
    trace: {
      conversation_id: orchestrator.conversationId,
      run_id: runId,
      task_id: primaryTask.task_id,
    },
  };
}

async function runClinicalStep(
  orchestrator: ConversationOrchestrator,
  task: ReturnType<ConversationOrchestrator["createTask"]>,
  params: RunAgentWorkflowParams,
  detection: AgentWorkflowDetection,
  contextSummary: string,
): Promise<AgentResult> {
  if (!params.patientId) {
    return {
      status: "failed",
      content: "",
      output_refs: [],
      error: "Workflow clinico requer patientId ou chat iniciado com --patient.",
    };
  }

  return await orchestrator.runTask(task, async () => {
    const started = orchestrator.recordToolStarted(task, "run_patient_agent");
    try {
      const output = await runPatientAgent({
        patientId: params.patientId!,
        task: [
          "Tarefa conversacional do HealthOS:",
          params.input,
          "",
          "Contexto montado por ContextAgent:",
          contextSummary,
          "",
          "Responda de modo sintetico, clinico e rastreavel por evidencias do dossie.",
        ].join("\n"),
        agentId: detection.patientAgentId,
        runtime: params.runtime,
      });
      orchestrator.recordToolCompleted(task, "run_patient_agent", started.event_id, task.input_refs);
      return {
        status: "completed",
        content: output,
        output_refs: task.input_refs,
      };
    } catch (error: any) {
      orchestrator.recordToolFailed(task, "run_patient_agent", error, started.event_id);
      return {
        status: "failed",
        content: "",
        output_refs: [],
        error: error.message || String(error),
      };
    }
  });
}

async function runPipelineStep(
  orchestrator: ConversationOrchestrator,
  task: ReturnType<ConversationOrchestrator["createTask"]>,
  stage: PipelineWorkflowStage,
): Promise<AgentResult> {
  return await orchestrator.runTask(task, async () => {
    const script = STAGE_SCRIPT_MAP[stage];
    const command = `npm run ${script}`;
    const started = orchestrator.recordToolStarted(task, "run_pipeline");
    try {
      const output = execSync(command, {
        cwd: PATHS.BASE,
        encoding: "utf-8",
        timeout: 300_000,
        maxBuffer: 5 * 1024 * 1024,
      });
      orchestrator.recordToolCompleted(task, "run_pipeline", started.event_id, task.input_refs);
      return {
        status: "completed",
        content: JSON.stringify({ command, stage, output: output.slice(-4000) }, null, 2),
        output_refs: task.input_refs,
      };
    } catch (error: any) {
      orchestrator.recordToolFailed(task, "run_pipeline", error, started.event_id);
      return {
        status: "failed",
        content: JSON.stringify({
          command,
          stage,
          error: (error.stderr || error.message || String(error)).slice(-2000),
          stdout: (error.stdout || "").slice(-2000),
        }, null, 2),
        output_refs: task.input_refs,
        error: error.message || String(error),
      };
    }
  });
}

async function reviewClinicalOutput(input: string, content: string, runtime?: LLMRuntimeName): Promise<string> {
  try {
    return await generateRuntimeText({
      runtime,
      systemPrompt: [
        "Voce e o SafetyReviewAgent do HealthOS.",
        "Revise resposta clinica sensivel antes de ir ao usuario.",
        "Aponte riscos de overclaim, falta de evidencia, conduta inadequada, urgencia e privacidade.",
        "Nao crie fatos novos. Seja breve e pratico.",
      ].join("\n"),
      userPrompt: [
        "## Pedido original",
        input,
        "",
        "## Saida do especialista",
        content,
        "",
        "## Revisao solicitada",
        "Liste OK/atencoes e, se necessario, ajustes de linguagem para a resposta final.",
      ].join("\n"),
      temperature: 0,
      timeoutMs: 600_000,
      useCache: true,
    });
  } catch (error: any) {
    return `Revisao indisponivel: ${error.message || String(error)}`;
  }
}

function collectContextRefs(patientId?: string, sessionId?: string): string[] {
  const refs: string[] = [];
  if (!patientId) return refs;

  try {
    const patient = getPatientWorkspace(patientId);
    refs.push(patient.profilePath, patient.memoryPath, patient.careAgentPath);
    const sessions = sessionId
      ? [getPatientSessionWorkspace(patient.id, sessionId)]
      : listPatientSessionWorkspaces(patient.id);
    for (const session of sessions) {
      refs.push(
        session.sessionPath,
        session.transcriptionPath,
        session.patientSpeechTextPath,
        session.patientSpeechJsonPath,
        session.patientSpeechMarkdownPath,
        session.aslPath,
        session.vdlpPath,
        session.gemPath,
      );
    }
  } catch {
    return refs.filter(existsSync).map(relativeRepoPath);
  }

  return refs.filter(existsSync).map(relativeRepoPath);
}

function renderContextSummary(refs: string[], patientId?: string, sessionId?: string): string {
  const lines = [
    `Paciente: ${patientId ?? "n/a"}`,
    `Sessao: ${sessionId ?? "todas disponiveis"}`,
    `Referencias: ${refs.length}`,
    ...refs.map((ref) => `- ${ref}`),
  ];
  return lines.join("\n");
}

function detectPipelineStage(text: string): PipelineWorkflowStage | null {
  if (!mentionsPipeline(text)) return null;
  if (/\bprocess(ar|amento)?\b/.test(text)) return "process";
  if (/\bspeech\b|fala do paciente|patient speech/.test(text)) return "speech";
  if (/\basl\b/.test(text)) return "asl";
  if (/\bvdlp\b/.test(text)) return "vdlp";
  if (/\bgem\b|grafo/.test(text)) return "gem";
  return null;
}

function mentionsPipeline(text: string): boolean {
  return /\bpipeline\b|roda(r)?|executa(r)?|gera(r)?/.test(text);
}

function mentionsRisk(text: string): boolean {
  return /risco|risk|suicid|autoagress|seguranca|seguranca|urgencia|emergencia/.test(text);
}

function mentionsSessionPrep(text: string): boolean {
  return /(prepar|planej|proxima|próxima).*(sess|consulta)|sess.*(prepar|planej|proxima|próxima)/.test(text);
}

function mentionsLongitudinalReview(text: string): boolean {
  return /longitudinal|linha do tempo|evolucao|evolução|entre sessoes|entre sessões/.test(text);
}

function mentionsClinicalCare(text: string): boolean {
  return /paciente|caso|clin|sintoma|diagnost|medic|sess|consulta|tratamento|conduta/.test(text);
}

function normalize(input: string): string {
  return input
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function relativeRepoPath(path: string): string {
  return relative(PATHS.BASE, path) || path;
}
