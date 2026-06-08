#!/usr/bin/env node
/**
 * HealthOS Chat CLI — runtime Claude Code ou Codex
 *
 * Claude Code customizado pro HealthOS. Usa o Agent SDK V1 estável:
 * - Read, Write, Bash, Glob, Grep built-in
 * - Compaction automática de contexto
 * - Streaming de respostas
 *
 * Custom tools (via MCP server interno):
 * - list_patients: visão geral dos dossiês
 * - search_content: grep clínico nos dados
 * - run_pipeline: executa estágios ASL/VDLP/GEM
 *
 * @author Dr. Gustavo Mendes e Silva
 */

import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { createInterface } from "readline";
import {
  existsSync,
  readFileSync,
} from "fs";
import { basename, join } from "path";
import { execSync } from "child_process";
import { config } from "dotenv";
import { PATHS } from "../config/defaults.js";
import { CODEX_AGENTS_DIR, listCodexAgents } from "../lib/llm/runtime.js";
import { getCodexStatus, runCodexExec } from "../lib/llm/codex-exec.js";
import {
  findHealthOSAgentMention,
  listHealthOSAgentSummaries,
} from "../lib/llm/agents.js";
import { ConversationOrchestrator } from "../lib/agents/orchestrator.js";
import { listAgentDefinitions, pipelineAgentId } from "../lib/agents/registry.js";
import { HEALTHOS_ALLOWED_TOOLS } from "../lib/agents/tool-access.js";
import {
  detectAgentWorkflow,
  runAgentWorkflow,
} from "../lib/agents/workflows.js";
import {
  appendProfessionalSessionLog,
  appendProfessionalMemory,
  ensureActiveProfessionalWorkspace,
  getActiveProfessionalWorkspace,
  loadActiveProfessionalConfig,
  loadProfessionalChatAgent,
  loadProfessionalMemory,
} from "../professionals/workspace.js";
import { listPatientAgents, runPatientAgent } from "../patients/agents.js";
import {
  getPatientWorkspace,
  listPatientIds,
  listPatientSessionWorkspaces,
  loadPatientProfile,
} from "../patients/workspace.js";
import { getSelectedRuntime } from "../lib/llm/runtime.js";

config({ path: PATHS.ENV, override: false });

const PAT_DIR = PATHS.PAT;

type ChatRuntime = "claude" | "codex";

type TranscriptEntry = {
  role: "user" | "assistant";
  text: string;
};

function parseStringArg(name: string): string | null {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] || null : null;
}

function resolvePatientArg(value?: string | null): string | null {
  const input = (value || "").trim();
  if (!input) return null;

  if (/^PAT_\d{6}$/i.test(input)) {
    const id = input.toUpperCase();
    return loadPatientProfile(id) ? id : null;
  }

  const normalized = input
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();

  for (const id of listPatientIds()) {
    const profile = loadPatientProfile(id);
    const names = [
      profile?.identity?.full_name,
      profile?.identity?.preferred_name,
      profile?.patient_name,
      ...(profile?.identity?.aliases || []),
    ].filter(Boolean) as string[];

    if (names.some((name) => name
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim() === normalized)) {
      return id;
    }
  }

  return null;
}

const ACTIVE_PATIENT_ID = resolvePatientArg(parseStringArg("--patient") || process.env.HEALTHOS_PATIENT_ID);

// ============================================================================
// SYSTEM PROMPT
// ============================================================================

function buildProfessionalContext(): string {
  ensureActiveProfessionalWorkspace();
  const config = loadActiveProfessionalConfig();
  const workspace = getActiveProfessionalWorkspace();
  const memory = loadProfessionalMemory();
  const chatAgent = loadProfessionalChatAgent();

  if (!config && !workspace && !memory) {
    return "Nenhum profissional ativo configurado.";
  }

  return [
    "## Profissional ativo",
    config ? `- Nome: ${config.nome}` : "- Nome: n/a",
    config?.registro ? `- Registro: ${config.registro}` : "- Registro: n/a",
    workspace ? `- Workspace: ${workspace.dir}` : "- Workspace: n/a",
    config?.disambiguation_context ? `- Contexto de desambiguação: ${config.disambiguation_context}` : "",
    chatAgent ? `\n## Perfil conversacional do profissional\n\n${chatAgent}` : "",
    memory ? `\n## Memória do profissional\n\n${memory}` : "",
  ].filter(Boolean).join("\n");
}

function getPatientName(patientId: string): string {
  const profile = loadPatientProfile(patientId);
  return profile?.identity?.full_name || profile?.patient_name || patientId;
}

function buildActivePatientContext(): string {
  if (!ACTIVE_PATIENT_ID) return "Nenhum paciente fixado para este chat.";

  const workspace = getPatientWorkspace(ACTIVE_PATIENT_ID);
  const profile = loadPatientProfile(ACTIVE_PATIENT_ID);
  const sessions = listPatientSessionWorkspaces(ACTIVE_PATIENT_ID);
  const sessionRows = sessions.map((session) => {
    const flags = [
      existsSync(session.transcriptionPath) ? "transcription" : "",
      existsSync(session.patientSpeechTextPath) || existsSync(session.patientSpeechJsonPath) || existsSync(session.patientSpeechMarkdownPath) ? "patient-speech" : "",
      existsSync(session.aslPath) ? "ASL" : "",
      existsSync(session.vdlpPath) ? "VDLP" : "",
      existsSync(session.gemPath) ? "GEM" : "",
    ].filter(Boolean).join(", ") || "sem artefatos";
    return `- ${session.id}: ${flags}`;
  });

  const careAgent = existsSync(workspace.careAgentPath)
    ? readFileSync(workspace.careAgentPath, "utf-8").slice(0, 20_000)
    : "";

  return [
    `## Paciente ativo do chat`,
    `- Patient ID: ${ACTIVE_PATIENT_ID}`,
    `- Nome: ${getPatientName(ACTIVE_PATIENT_ID)}`,
    `- Workspace: ${workspace.dir}`,
    `- Sessoes: ${sessions.length}`,
    sessionRows.length ? `\n## Sessoes do paciente\n${sessionRows.join("\n")}` : "",
    profile ? `\n## patient.json\n\n${JSON.stringify(profile, null, 2).slice(0, 60_000)}` : "",
    careAgent ? `\n## care-agent.md\n\n${careAgent}` : "",
  ].filter(Boolean).join("\n");
}

export const SYSTEM_PROMPT = `Você é o assistente clínico integrado do HealthOS — um sistema de inteligência clínica para psiquiatria.

${buildProfessionalContext()}

${buildActivePatientContext()}

## Seu papel

Você é simultaneamente:
1. **Assistente clínico** — interpreta dados de pacientes, análises linguísticas (ASL), dimensões do espaço mental (VDLP), e grafos mentais (GEM)
2. **Operador do sistema** — executa pipeline stages, gerencia dossiês, edita configurações
3. **Desenvolvedor** — lê, edita e cria arquivos do sistema HealthOS

Você tem acesso completo ao filesystem via Read, Write, Edit, Bash, Glob, Grep. Use-os livremente.

## Arquitetura HealthOS

Pipeline de 6 estágios:
1. **Transcrição** — Áudio → ElevenLabs Scribe → JSON com diarização
2. **Processamento** — Runtime LLM selecionado extrai metadados e organiza em dossiês
3. **ASL** — Análise Sistêmica Linguística (8 domínios psicolinguísticos)
4. **VDLP** — 15 Dimensões do Espaço Mental ℳ (meta-afetiva, meta-cognitiva, meta-linguística)
5. **GEM** — Grafo do Espaço-Campo Mental (camadas .aje, .ire, .e, .epe)
6. **Narrativa** — Narrativa fenomenológica multi-agente

## Estrutura de dados

\`\`\`
${PATHS.BASE}/
├── patients/                    # Dossiês de pacientes
│   └── PAT_000001/
│       ├── patient.json         # Identidade e metadados do paciente
│       ├── memory.md            # Memória clínica explícita
│       ├── care-agent.md        # Perfil operacional do caso
│       ├── agents/              # Subagentes específicos do paciente
│       └── sessions/
│           └── C1/
│               ├── session.json
│               ├── source/transcription.json
│               └── analysis/
│                   ├── patient-speech.*
│                   ├── asl.json
│                   ├── vdlp.json
│                   └── gem.json
├── audio/transcriptions/        # Transcrições brutas
├── prompts/                     # Prompts de referência
└── src/                         # Código-fonte do sistema
\`\`\`

## Diretrizes

- Responda sempre em português brasileiro
- Ao apresentar dados clínicos, seja preciso e use terminologia adequada
- Para operações destrutivas (deletar, sobrescrever), confirme antes de executar
- Ao analisar dados de pacientes, conecte achados entre ASL/VDLP/GEM quando possível
- Se houver Paciente ativo do chat, trate esse paciente como contexto padrão para perguntas clínicas e operações de dossiê, salvo pedido explícito em contrário
- Mantenha tom profissional mas acessível — você conversa com o Dr. Gustavo
- Use as ferramentas built-in (Read, Write, Edit, Bash, Glob, Grep) para operações no filesystem
- Use as custom tools (list_patients, search_content, run_pipeline) para operações clínicas`;

// ============================================================================
// CUSTOM TOOLS — via MCP Server interno
// ============================================================================

function createChatOrchestrator(runtime: "ClaudeSDK" | "CodexSubprocess" | ReturnType<typeof getSelectedRuntime> = getSelectedRuntime(), patientId = ACTIVE_PATIENT_ID): ConversationOrchestrator {
  return new ConversationOrchestrator({
    patientId: patientId ?? undefined,
    runtime,
  });
}

function toolText(content: Record<string, unknown>): { content: Array<{ type: "text"; text: string }> } {
  return {
    content: [{
      type: "text",
      text: JSON.stringify(content, null, 2),
    }],
  };
}

export const healthOSTools = createSdkMcpServer({
  name: "healthos",
  version: "1.0.0",
  tools: [
    // -------------------------------------------------------------------------
    // list_patients
    // -------------------------------------------------------------------------
    tool(
      "list_patients",
      "Lista todos os pacientes com contagem de arquivos por estágio do pipeline (transcrições, ASL, VDLP, GEM). Visão geral rápida do sistema.",
      {},
      async () => {
        if (!existsSync(PAT_DIR)) {
          return { content: [{ type: "text", text: "Diretório patients/ não encontrado." }] };
        }

        const patients = listPatientIds();

        if (patients.length === 0) {
          return { content: [{ type: "text", text: "Nenhum paciente encontrado." }] };
        }

        const rows = patients.map(id => {
          const profile = loadPatientProfile(id);
          const sessions = listPatientSessionWorkspaces(id);
          const totals = sessions.reduce((acc, session) => {
            acc.transcriptions += Number(existsSync(session.transcriptionPath));
            acc.speech += Number(existsSync(session.patientSpeechTextPath) || existsSync(session.patientSpeechJsonPath) || existsSync(session.patientSpeechMarkdownPath));
            acc.asl += Number(existsSync(session.aslPath));
            acc.vdlp += Number(existsSync(session.vdlpPath));
            acc.gem += Number(existsSync(session.gemPath));
            return acc;
          }, { transcriptions: 0, speech: 0, asl: 0, vdlp: 0, gem: 0 });

          const name = profile?.identity?.full_name || profile?.patient_name || id;
          return `${id} (${name}): ${sessions.length} sessão(ões) | ${totals.transcriptions} transcr | ${totals.speech} speech | ${totals.asl} ASL | ${totals.vdlp} VDLP | ${totals.gem} GEM`;
        });

        return {
          content: [{
            type: "text",
            text: JSON.stringify({ total: patients.length, patients: rows }, null, 2)
          }]
        };
      }
    ),

    // -------------------------------------------------------------------------
    // search_content
    // -------------------------------------------------------------------------
    tool(
      "search_content",
      "Busca texto em arquivos de pacientes ou em todo o sistema. Útil para encontrar menções a medicamentos, sintomas, temas recorrentes, palavras-chave clínicas.",
      {
        query: z.string().describe("Texto a buscar (case-insensitive)"),
        patient_id: z.string().optional().describe("Filtrar por paciente (ex: PAT_000001)"),
        file_type: z.enum(["json", "md", "txt", "all"]).optional().describe("Tipo de arquivo (default: all)"),
      },
      async (params) => {
        const searchDir = params.patient_id ? join(PAT_DIR, params.patient_id) : PAT_DIR;
        if (!existsSync(searchDir)) {
          return {
            content: [{
              type: "text",
              text: JSON.stringify({ error: `Diretório não encontrado: ${searchDir}` })
            }]
          };
        }

        const ext = params.file_type === "all" || !params.file_type ? "" : `.${params.file_type}`;
        const includeFlag = ext
          ? `--include='*${ext}'`
          : "--include='*.json' --include='*.md' --include='*.txt'";

        try {
          const output = execSync(
            `grep -rn -i --color=never ${includeFlag} "${params.query}" "${searchDir}" 2>/dev/null | head -50`,
            { encoding: "utf-8", timeout: 10_000, maxBuffer: 1024 * 1024 }
          );

          if (!output.trim()) {
            return {
              content: [{
                type: "text",
                text: JSON.stringify({ results: 0, query: params.query })
              }]
            };
          }

          const lines = output.trim().split("\n").map(l => l.replace(PATHS.BASE + "/", ""));
          return {
            content: [{
              type: "text",
              text: JSON.stringify({ results: lines.length, query: params.query, matches: lines }, null, 2)
            }]
          };
        } catch {
          return {
            content: [{
              type: "text",
              text: JSON.stringify({ results: 0, query: params.query })
            }]
          };
        }
      }
    ),

    // -------------------------------------------------------------------------
    // run_pipeline
    // -------------------------------------------------------------------------
    tool(
      "run_pipeline",
      "Executa um estágio do pipeline HealthOS. Estágios: process, speech, asl, vdlp, gem.",
      {
        stage: z.enum(["process", "speech", "asl", "vdlp", "gem"]).describe("Estágio do pipeline"),
      },
      async (params) => {
        const orchestrator = createChatOrchestrator(getSelectedRuntime());
        const task = orchestrator.createTask(`run_pipeline:${params.stage}`, {
          agentId: pipelineAgentId(params.stage),
          kind: "pipeline",
        });
        const scriptMap: Record<string, string> = {
          process: "pipeline:process",
          speech: "pipeline:speech",
          asl: "pipeline:asl",
          vdlp: "pipeline:vdlp",
          gem: "pipeline:gem",
        };

        const script = scriptMap[params.stage];
        if (!script) {
          return toolText({ error: `Estágio inválido: ${params.stage}` });
        }

        const cmd = `npm run ${script}`;
        const result = await orchestrator.runTask(task, async () => {
          const started = orchestrator.recordToolStarted(task, "run_pipeline");
          try {
            const output = execSync(cmd, {
              cwd: PATHS.BASE,
              encoding: "utf-8",
              timeout: 300_000,
              maxBuffer: 5 * 1024 * 1024,
            });
            orchestrator.recordToolCompleted(task, "run_pipeline", started.event_id);
            return {
              status: "completed",
              content: JSON.stringify({ command: cmd, output: output.slice(-2000) }, null, 2),
              output_refs: [],
            };
          } catch (err: any) {
            orchestrator.recordToolFailed(task, "run_pipeline", err, started.event_id);
            return {
              status: "failed",
              content: JSON.stringify({
                command: cmd,
                error: (err.stderr || err.message || "").slice(-1000),
                stdout: (err.stdout || "").slice(-1000),
              }, null, 2),
              output_refs: [],
              error: err.message || String(err),
            };
          }
        });
        return { content: [{ type: "text", text: result.content }] };
      }
    ),

    // -------------------------------------------------------------------------
    // run_agent_workflow
    // -------------------------------------------------------------------------
    tool(
      "run_agent_workflow",
      "Executa um workflow multiagente completo: ContextAgent monta referencias, especialista executa, SafetyReviewAgent revisa quando clinico, e tudo gera eventos.",
      {
        input: z.string().describe("Intencao/tarefa conversacional do usuario"),
        patient_id: z.string().optional().describe("Paciente alvo; se omitido, usa o paciente ativo do chat quando houver"),
        session_id: z.string().optional().describe("Sessao especifica opcional"),
        stage: z.enum(["process", "speech", "asl", "vdlp", "gem"]).optional().describe("Forca workflow de pipeline em um estagio"),
        review: z.boolean().optional().describe("Forca ou desliga revisao clinica; default segue a politica do workflow"),
      },
      async (params) => {
        const patientId = params.patient_id ?? ACTIVE_PATIENT_ID ?? undefined;
        const orchestrator = createChatOrchestrator(getSelectedRuntime(), patientId);
        try {
          const result = await runAgentWorkflow({
            input: params.input,
            patientId,
            sessionId: params.session_id,
            stage: params.stage,
            review: params.review,
            runtime: getSelectedRuntime(),
            orchestrator,
          });
          return toolText({
            workflow_kind: result.workflow_kind,
            status: result.status,
            trace: result.trace,
            output_refs: result.output_refs,
            agent_outputs: result.agent_outputs.map((step) => ({
              agent_id: step.agent_id,
              output_refs: step.output_refs,
              content: step.content.slice(0, 4000),
            })),
            content: result.content,
          });
        } catch (err: any) {
          return toolText({
            status: "failed",
            error: err.message || String(err),
          });
        }
      }
    ),

    // -------------------------------------------------------------------------
    // list_healthos_agents
    // -------------------------------------------------------------------------
    tool(
      "list_healthos_agents",
      "Lista agentes do projeto HealthOS definidos em src/agents para arquitetura, seguranca, documentacao, planejamento, pesquisa, implementacao e QA.",
      {
        includeScenario: z.boolean().optional().describe("Inclui agentes de uso apenas em cenarios especificos"),
      },
      async (params) => {
        const agents = listHealthOSAgentSummaries({ includeScenario: params.includeScenario });
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              total: agents.length,
              agents,
            }, null, 2)
          }]
        };
      }
    ),

    // -------------------------------------------------------------------------
    // list_agent_definitions
    // -------------------------------------------------------------------------
    tool(
      "list_agent_definitions",
      "Lista o registry multiagente completo: agentes internos do sistema, agentes HealthOS, subagentes Codex e agentes de paciente quando informado.",
      {
        includeScenario: z.boolean().optional().describe("Inclui agentes HealthOS de cenario especifico"),
        includeCodex: z.boolean().optional().describe("Inclui subagentes Codex instalados localmente"),
        patient_id: z.string().optional().describe("Inclui agentes declarativos de um paciente"),
      },
      async (params) => {
        const agents = listAgentDefinitions({
          includeScenario: params.includeScenario,
          includeCodex: params.includeCodex,
          patientId: params.patient_id,
        }).map(({ prompt, ...agent }) => ({
          ...agent,
          has_prompt: Boolean(prompt),
        }));
        return toolText({
          total: agents.length,
          agents,
        });
      }
    ),

    // -------------------------------------------------------------------------
    // list_patient_agents
    // -------------------------------------------------------------------------
    tool(
      "list_patient_agents",
      "Lista care-agent.md e agentes markdown em patients/<PAT_ID>/agents para um paciente.",
      {
        patient_id: z.string().describe("Patient ID canonico ou nome do paciente"),
      },
      async (params) => {
        try {
          const agents = listPatientAgents(params.patient_id);
          return {
            content: [{
              type: "text",
              text: JSON.stringify({
                total: agents.length,
                patient_id: agents[0]?.patient_id ?? params.patient_id,
                agents,
              }, null, 2)
            }]
          };
        } catch (err: any) {
          return {
            content: [{
              type: "text",
              text: JSON.stringify({ error: err.message || String(err) })
            }]
          };
        }
      }
    ),

    // -------------------------------------------------------------------------
    // run_patient_agent
    // -------------------------------------------------------------------------
    tool(
      "run_patient_agent",
      "Executa um agente de paciente usando src/lib/llm/runtime.ts, respeitando HEALTHOS_LLM_RUNTIME/HEALTHOS_CHAT_RUNTIME.",
      {
        patient_id: z.string().describe("Patient ID canonico ou nome do paciente"),
        task: z.string().describe("Tarefa objetiva para o agente do paciente"),
        agent_id: z.string().optional().describe("Agente em patients/<PAT_ID>/agents sem .md; default: care-agent"),
      },
      async (params) => {
        const selectedAgent = params.agent_id || "care-agent";
        const orchestrator = createChatOrchestrator(getSelectedRuntime(), params.patient_id);
        const task = orchestrator.createTask(params.task, {
          agentId: selectedAgent === "risk-check"
            ? "risk-check-agent"
            : selectedAgent === "session-prep"
              ? "session-prep-agent"
              : selectedAgent === "longitudinal-reviewer"
                ? "longitudinal-reviewer-agent"
                : "patient-care-agent",
          kind: "clinical",
          patientId: params.patient_id,
        });
        const result = await orchestrator.runTask(task, async () => {
          const started = orchestrator.recordToolStarted(task, "run_patient_agent");
          try {
            const output = await runPatientAgent({
              patientId: params.patient_id,
              task: params.task,
              agentId: params.agent_id,
              runtime: getSelectedRuntime(),
            });
            orchestrator.recordToolCompleted(task, "run_patient_agent", started.event_id);
            return {
              status: "completed",
              content: JSON.stringify({
                runtime: getSelectedRuntime(),
                patient_id: params.patient_id,
                agent_id: selectedAgent,
                output,
              }, null, 2),
              output_refs: [],
            };
          } catch (err: any) {
            orchestrator.recordToolFailed(task, "run_patient_agent", err, started.event_id);
            return {
              status: "failed",
              content: JSON.stringify({
                runtime: getSelectedRuntime(),
                patient_id: params.patient_id,
                agent_id: selectedAgent,
                error: err.message || String(err),
              }, null, 2),
              output_refs: [],
              error: err.message || String(err),
            };
          }
        });
        return { content: [{ type: "text", text: result.content }] };
      }
    ),

    // -------------------------------------------------------------------------
    // list_codex_agents
    // -------------------------------------------------------------------------
    tool(
      "list_codex_agents",
      "Lista subagentes Codex instalados em ~/.codex/agents para delegacao local com a configuracao Codex do usuario.",
      {},
      async () => {
        const agents = listCodexAgents();
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              total: agents.length,
              agents,
              status: getCodexStatus(),
            }, null, 2)
          }]
        };
      }
    ),

    // -------------------------------------------------------------------------
    // run_codex_subagent
    // -------------------------------------------------------------------------
    tool(
      "run_codex_subagent",
      "Delega uma tarefa para um subprocesso Codex local, podendo especializar com agente HealthOS em src/agents ou subagente Codex em ~/.codex/agents.",
      {
        task: z.string().describe("Tarefa objetiva para o subagente Codex executar"),
        agent: z.string().optional().describe("ID opcional de agente HealthOS ou subagente Codex, sem .toml"),
      },
      async (params) => {
        const orchestrator = createChatOrchestrator("CodexSubprocess");
        const task = orchestrator.createTask(params.task, {
          agentId: params.agent ?? "conversation-agent",
          kind: "subprocess",
        });
        const result = await orchestrator.runTask(task, async () => {
          const started = orchestrator.recordToolStarted(task, "run_codex_subagent");
          try {
            const output = await runCodexExec(params.task, {
              agent: params.agent,
              systemPrompt: SYSTEM_PROMPT,
              timeoutMs: 600_000,
            });
            orchestrator.recordToolCompleted(task, "run_codex_subagent", started.event_id);
            return {
              status: "completed",
              content: JSON.stringify({
                runtime: "codex",
                agent: params.agent ?? null,
                output: output.slice(-6000),
              }, null, 2),
              output_refs: [],
            };
          } catch (err: any) {
            orchestrator.recordToolFailed(task, "run_codex_subagent", err, started.event_id);
            return {
              status: "failed",
              content: JSON.stringify({
                runtime: "codex",
                agent: params.agent ?? null,
                error: (err.message || String(err)).slice(-2000),
              }, null, 2),
              output_refs: [],
              error: err.message || String(err),
            };
          }
        });
        return { content: [{ type: "text", text: result.content }] };
      }
    ),
  ],
});


// ============================================================================
// QUERY OPTIONS — usado pelo chat-cli
// ============================================================================

export const QUERY_OPTIONS = {
  systemPrompt: SYSTEM_PROMPT,
  mcpServers: {
    healthos: healthOSTools,
  },
  allowedTools: [...HEALTHOS_ALLOWED_TOOLS],
  maxTurns: 30,
  permissionMode: "acceptEdits" as const,
  cwd: PATHS.BASE,
  executable: "node" as const,
};


// ============================================================================
// CHAT INTERFACE
// ============================================================================

const useColor = Boolean(process.stdout.isTTY && !process.env.NO_COLOR);
const colors = {
  cyan: useColor ? "\x1b[36m" : "",
  green: useColor ? "\x1b[32m" : "",
  blue: useColor ? "\x1b[34m" : "",
  magenta: useColor ? "\x1b[35m" : "",
  dim: useColor ? "\x1b[2m" : "",
  bold: useColor ? "\x1b[1m" : "",
  yellow: useColor ? "\x1b[33m" : "",
  red: useColor ? "\x1b[31m" : "",
  reset: useColor ? "\x1b[0m" : "",
};

function terminalWidth(): number {
  return Math.max(72, Math.min(process.stdout.columns || 88, 120));
}

function rule(char = "-"): string {
  return char.repeat(terminalWidth());
}

function padRight(text: string, width: number): string {
  return text.length >= width ? text.slice(0, width) : text + " ".repeat(width - text.length);
}

function badge(label: string, color = colors.cyan): string {
  return `${color}${colors.bold} ${label} ${colors.reset}`;
}

function printLine(label: string, value: string, color = colors.dim): void {
  console.log(`${color}${padRight(label, 14)}${colors.reset}${value}`);
}

function printHeader(runtime: ChatRuntime): void {
  const professional = loadActiveProfessionalConfig();
  const professionalWorkspace = getActiveProfessionalWorkspace();
  console.clear();
  console.log("");
  console.log(`${colors.bold}${colors.cyan}HealthOS Chat CLI${colors.reset} ${badge(runtime.toUpperCase(), runtime === "codex" ? colors.magenta : colors.cyan)}`);
  console.log(`${colors.dim}${rule()}${colors.reset}`);
  printLine("runtime", runtime === "codex" ? "Codex local via ChatGPT login + ~/.codex" : "Claude Code Agent SDK + HealthOS MCP tools");
  printLine("professional", professional ? `${professional.nome} (${professional.registro})` : "n/a");
  printLine("prof. memory", professionalWorkspace?.memoryPath || "n/a");
  printLine("chat agent", professionalWorkspace?.chatAgentPath || "n/a");
  printLine("patient", ACTIVE_PATIENT_ID ? `${ACTIVE_PATIENT_ID} ${getPatientName(ACTIVE_PATIENT_ID)}` : "n/a");
  printLine("workspace", PATHS.BASE);
  printLine("patients", PATHS.PAT);
  printLine("codex", getCodexStatus());
  console.log(`${colors.dim}${rule()}${colors.reset}`);
  console.log(`${colors.dim}Comandos: /help, /runtime claude|codex, /agents, /status, /clear, /quit${colors.reset}\n`);
}

function printHelp(runtime: ChatRuntime): void {
  console.log(`\n${colors.bold}${colors.cyan}Comandos${colors.reset}`);
  console.log("  /runtime claude       usar Claude Code Agent SDK");
  console.log("  /runtime codex        usar Codex local com ~/.codex");
  console.log("  /agents               listar subagentes Codex instalados");
  console.log("  /agent                mostrar perfil conversacional do profissional");
  console.log("  /memory               mostrar memória do profissional");
  console.log("  /remember texto       salvar memória explícita do profissional");
  console.log("  /status               mostrar runtime, paths e auth");
  console.log("  /clear                redesenhar a tela");
  console.log("  /quit                 sair");
  console.log(`\n${colors.bold}${colors.cyan}Exemplos${colors.reset}`);
  console.log("  lista meus pacientes");
  console.log("  busca sertralina em todos os pacientes");
  console.log("  roda ASL");
  console.log("  prepara a proxima sessao deste paciente");
  console.log("  checa risco clinico deste caso");
  console.log("  use o subagente context-architect para mapear este refactor");
  console.log(`\n${colors.dim}Runtime atual: ${runtime}${colors.reset}\n`);
  if (ACTIVE_PATIENT_ID) console.log(`${colors.dim}Paciente ativo: ${ACTIVE_PATIENT_ID} ${getPatientName(ACTIVE_PATIENT_ID)}${colors.reset}\n`);
}

function printAgents(): void {
  const systemAgents = listAgentDefinitions({ includeCodex: false })
    .filter((agent) => agent.source === "system");
  const healthOSAgents = listHealthOSAgentSummaries({ includeScenario: true });
  const active = healthOSAgents.filter((agent) => agent.availability === "active");
  const scenario = healthOSAgents.filter((agent) => agent.availability === "scenario");
  const codexAgents = listCodexAgents();

  console.log(`\n${colors.bold}${colors.cyan}Agentes internos multiagent${colors.reset}`);
  for (const agent of systemAgents) {
    console.log(`  ${colors.bold}${agent.id}${colors.reset} ${colors.dim}${agent.category} · ${agent.purpose}${colors.reset}`);
  }

  console.log(`\n${colors.bold}${colors.magenta}Agentes HealthOS${colors.reset}`);
  for (const agent of active) {
    console.log(`  ${colors.bold}${agent.id}${colors.reset} ${colors.dim}${agent.category} · ${agent.purpose}${colors.reset}`);
  }

  if (scenario.length) {
    console.log(`\n${colors.bold}${colors.cyan}Cenario especifico${colors.reset}`);
    for (const agent of scenario) {
      console.log(`  ${agent.id} ${colors.dim}${agent.category} · ${agent.purpose}${colors.reset}`);
    }
  }

  console.log(`\n${colors.bold}${colors.magenta}Subagentes Codex instalados${colors.reset}`);
  if (codexAgents.length === 0) {
    console.log(`${colors.yellow}Nenhum arquivo .toml encontrado em ${CODEX_AGENTS_DIR}.${colors.reset}\n`);
    return;
  }

  const columns = terminalWidth() >= 100 ? 3 : 2;
  const colWidth = Math.floor((terminalWidth() - 4) / columns);
  for (let i = 0; i < codexAgents.length; i += columns) {
    const row = codexAgents.slice(i, i + columns)
      .map((agent) => padRight(agent, colWidth))
      .join("  ");
    console.log(`  ${row.trimEnd()}`);
  }
  console.log("");
}

function parseRuntimeArg(): ChatRuntime {
  const runtimeFlagIndex = process.argv.findIndex((arg) => arg === "--runtime");
  const runtimeFlag = runtimeFlagIndex >= 0 ? process.argv[runtimeFlagIndex + 1] : null;
  const explicit = runtimeFlag || process.env.HEALTHOS_CHAT_RUNTIME;

  if (process.argv.includes("--codex") || explicit === "codex") return "codex";
  if (process.argv.includes("--claude") || explicit === "claude") return "claude";

  return "claude";
}

function parseAgentHint(input: string): string | undefined {
  const healthOSAgent = findHealthOSAgentMention(input);
  if (healthOSAgent) return healthOSAgent.id;

  const agents = listCodexAgents();
  const lowered = input.toLowerCase();
  return agents.find((agent) => lowered.includes(agent.toLowerCase()));
}

function createSpinner(label: string): () => void {
  if (!process.stdout.isTTY) {
    console.log(`${colors.dim}${label}...${colors.reset}`);
    return () => {};
  }

  const frames = ["-", "\\", "|", "/"];
  let index = 0;
  process.stdout.write(`${colors.dim}${frames[index]} ${label}${colors.reset}`);
  const timer = setInterval(() => {
    index = (index + 1) % frames.length;
    process.stdout.write(`\r${colors.dim}${frames[index]} ${label}${colors.reset}`);
  }, 120);

  return () => {
    clearInterval(timer);
    process.stdout.write(`\r${" ".repeat(Math.min(terminalWidth(), label.length + 6))}\r`);
  };
}

async function ask(rl: ReturnType<typeof createInterface>, runtime: ChatRuntime): Promise<string> {
  const promptColor = runtime === "codex" ? colors.magenta : colors.green;
  const patientSuffix = ACTIVE_PATIENT_ID ? `:${ACTIVE_PATIENT_ID}` : "";
  return await new Promise<string>((resolve) => {
    rl.question(`${promptColor}${colors.bold}gus${colors.reset}${colors.dim}:${runtime}${patientSuffix}${colors.reset} > `, resolve);
  });
}

async function handleCodexTurn(input: string, transcript: TranscriptEntry[], orchestrator: ConversationOrchestrator): Promise<void> {
  const agent = parseAgentHint(input);
  const workflow = agent ? null : detectAgentWorkflow(input, {
    patientId: ACTIVE_PATIENT_ID ?? undefined,
  });

  if (workflow) {
    const task = orchestrator.createTask(input, {
      agentId: workflow.agentId,
      kind: workflow.kind === "pipeline_stage" ? "pipeline" : "clinical",
      patientId: ACTIVE_PATIENT_ID ?? undefined,
    });
    orchestrator.recordMessageReceived(input, task);
    const stopSpinner = createSpinner(`Workflow ${workflow.agentId}`);

    try {
      const result = await runAgentWorkflow({
        input,
        patientId: ACTIVE_PATIENT_ID ?? undefined,
        stage: workflow.stage,
        runtime: "Codex",
        orchestrator,
      });
      stopSpinner();
      if (result.status === "failed") {
        console.log(`\n${colors.red}${colors.bold}erro workflow${colors.reset} ${result.error || "falha desconhecida"}\n`);
        return;
      }

      const text = result.content || "(sem saida textual)";
      transcript.push({ role: "assistant", text });
      console.log(`\n${colors.magenta}${colors.bold}codex:workflow${colors.reset}${colors.dim}:${result.workflow_kind}${colors.reset} > ${text}\n`);
      return;
    } catch (err: any) {
      stopSpinner();
      console.log(`\n${colors.red}${colors.bold}erro workflow${colors.reset} ${err.message || String(err)}\n`);
      return;
    }
  }

  const task = orchestrator.createTask(input, {
    agentId: agent,
    kind: agent ? "subprocess" : "conversation",
  });
  orchestrator.recordMessageReceived(input, task);
  const stopSpinner = createSpinner(agent ? `Codex executando com ${agent}` : "Codex pensando");

  try {
    const result = await orchestrator.runTask(task, async () => {
      const started = orchestrator.recordToolStarted(task, "codex exec");
      try {
        const output = await runCodexExec(input, {
          agent,
          transcript,
          systemPrompt: SYSTEM_PROMPT,
          timeoutMs: 600_000,
        });
        orchestrator.recordToolCompleted(task, "codex exec", started.event_id);
        return {
          status: "completed",
          content: output,
          output_refs: [],
        };
      } catch (err: any) {
        orchestrator.recordToolFailed(task, "codex exec", err, started.event_id);
        return {
          status: "failed",
          content: "",
          output_refs: [],
          error: err.message || String(err),
        };
      }
    });

    stopSpinner();
    if (result.status === "failed") {
      console.log(`\n${colors.red}${colors.bold}erro codex${colors.reset} ${result.error || "falha desconhecida"}\n`);
      return;
    }
    const text = result.content || "(sem saida textual)";
    transcript.push({ role: "assistant", text });
    console.log(`\n${colors.magenta}${colors.bold}codex${colors.reset}${colors.dim}${agent ? `:${agent}` : ""}${colors.reset} > ${text}\n`);
  } catch (err: any) {
    stopSpinner();
    console.log(`\n${colors.red}${colors.bold}erro codex${colors.reset} ${err.message || String(err)}\n`);
  }
}

function handleCommand(input: string, runtimeRef: { value: ChatRuntime }, orchestrator?: ConversationOrchestrator): "handled" | "quit" | "pass" {
  if (input === "/quit" || input === "/exit" || input === "/q") {
    console.log(`\n${colors.dim}Ate logo.${colors.reset}\n`);
    return "quit";
  }

  if (input === "/help") {
    printHelp(runtimeRef.value);
    return "handled";
  }

  if (input === "/clear") {
    printHeader(runtimeRef.value);
    return "handled";
  }

  if (input === "/agents") {
    printAgents();
    return "handled";
  }

  if (input === "/agent") {
    const profile = loadProfessionalChatAgent();
    const workspace = getActiveProfessionalWorkspace();
    console.log(`\n${colors.bold}${colors.cyan}Perfil Conversacional${colors.reset}`);
    console.log(`${colors.dim}${workspace?.chatAgentPath || "n/a"}${colors.reset}\n`);
    console.log(profile || `${colors.yellow}Nenhum chat-agent.md encontrado.${colors.reset}`);
    console.log("");
    return "handled";
  }

  if (input === "/memory") {
    const memory = loadProfessionalMemory();
    const workspace = getActiveProfessionalWorkspace();
    console.log(`\n${colors.bold}${colors.cyan}Memória do Profissional${colors.reset}`);
    console.log(`${colors.dim}${workspace?.memoryPath || "n/a"}${colors.reset}\n`);
    console.log(memory || `${colors.yellow}Nenhuma memória encontrada.${colors.reset}`);
    console.log("");
    return "handled";
  }

  if (input.startsWith("/remember")) {
    const note = input.replace(/^\/remember\s*/i, "").trim();
    if (!note) {
      console.log(`${colors.yellow}Uso: /remember texto para salvar uma memória explícita.${colors.reset}`);
      return "handled";
    }

    const path = appendProfessionalMemory(note);
    if (orchestrator) {
      const task = orchestrator.createTask(input, {
        agentId: "memory-agent",
        kind: "memory",
      });
      orchestrator.recordMessageReceived(input, task);
      if (path) orchestrator.recordMemoryCommitted(task, path);
    }
    console.log(path
      ? `${colors.green}Memória salva em ${path}.${colors.reset}`
      : `${colors.yellow}Nenhum profissional ativo para salvar memória.${colors.reset}`);
    return "handled";
  }

  if (input === "/status") {
    console.log("");
    printLine("runtime", runtimeRef.value);
    if (orchestrator) printLine("conversation", orchestrator.conversationId);
    printLine("codex", getCodexStatus());
    const professional = loadActiveProfessionalConfig();
    const professionalWorkspace = getActiveProfessionalWorkspace();
    printLine("professional", professional ? `${professional.nome} (${professional.registro})` : "n/a");
    printLine("prof. memory", professionalWorkspace?.memoryPath || "n/a");
    printLine("chat agent", professionalWorkspace?.chatAgentPath || "n/a");
    printLine("patient", ACTIVE_PATIENT_ID ? `${ACTIVE_PATIENT_ID} ${getPatientName(ACTIVE_PATIENT_ID)}` : "n/a");
    printLine("hos agents", `${listHealthOSAgentSummaries({ includeScenario: true }).length} em src/agents`);
    printLine("codex agents", `${listCodexAgents().length} em ${CODEX_AGENTS_DIR}`);
    printLine("workspace", PATHS.BASE);
    console.log("");
    return "handled";
  }

  if (input.startsWith("/runtime")) {
    const [, selected] = input.split(/\s+/);
    if (selected === "claude" || selected === "codex") {
      runtimeRef.value = selected;
      printHeader(runtimeRef.value);
      return "handled";
    }

    console.log(`${colors.yellow}Uso: /runtime claude ou /runtime codex${colors.reset}`);
    return "handled";
  }

  return "pass";
}

async function runClaudeLoop(rl: ReturnType<typeof createInterface>, runtimeRef: { value: ChatRuntime }, orchestrator: ConversationOrchestrator): Promise<void> {
  const abortController = new AbortController();

  async function* userMessages() {
    while (runtimeRef.value === "claude") {
      const input = await ask(rl, runtimeRef.value);
      const trimmed = input.trim();
      if (!trimmed) continue;

      const commandHandled = handleCommand(trimmed, runtimeRef, orchestrator);
      if (commandHandled === "quit") {
        abortController.abort();
        return;
      }
      if (commandHandled === "handled") {
        if (runtimeRef.value !== "claude") {
          abortController.abort();
          return;
        }
        continue;
      }
      if (runtimeRef.value !== "claude") {
        abortController.abort();
        return;
      }

      const task = orchestrator.createTask(trimmed, { kind: "conversation" });
      orchestrator.recordMessageReceived(trimmed, task);

      yield {
        type: "user" as const,
        message: {
          role: "user" as const,
          content: [{ type: "text" as const, text: trimmed }]
        },
        session_id: "",
        parent_tool_use_id: null
      };
    }
  }

  try {
    for await (const message of query({
      prompt: userMessages(),
      options: {
        ...QUERY_OPTIONS,
        abortController,
      },
    })) {
      if (message.type === "assistant") {
        const textBlocks = message.message.content
          .filter((block: any) => block.type === "text")
          .map((block: any) => block.text)
          .join("");

        const toolUses = message.message.content.filter((block: any) => block.type === "tool_use");
        for (const t of toolUses) {
          console.log(`${colors.dim}tool ${colors.cyan}${(t as any).name}${colors.reset}`);
        }

        if (textBlocks) {
          console.log(`\n${colors.cyan}${colors.bold}claude${colors.reset} > ${textBlocks}\n`);
        }
      } else if (message.type === "system" && (message as any).subtype === "init") {
        const init = message as any;
        console.log(`${colors.dim}Claude pronto: ${init.model} · tools=${init.tools?.length ?? 0} · mcp=${init.mcp_servers?.length ?? 0}${colors.reset}`);
      } else if (message.type === "result") {
        const result = message as any;
        if (result.subtype === "error_max_turns") {
          console.log(`${colors.yellow}Limite de turns atingido.${colors.reset}\n`);
        } else if (result.subtype === "error_during_execution") {
          console.log(`${colors.red}Claude retornou erro durante execucao.${colors.reset}\n`);
        }
      }
    }
  } catch (err: any) {
    if (abortController.signal.aborted) {
      return;
    }

    if (err.code === "RATE_LIMITED" || err.status === 429) {
      console.log(`\n${colors.yellow}Rate limit. Aguarde e tente novamente.${colors.reset}\n`);
    } else {
      console.log(`\n${colors.red}${err.message}${colors.reset}\n`);
    }
  }
}

export async function chatLoop(initialRuntime = parseRuntimeArg()): Promise<void> {
  let rl = createInterface({ input: process.stdin, output: process.stdout });
  const runtimeRef = { value: initialRuntime };
  const transcript: TranscriptEntry[] = [];
  const orchestrator = new ConversationOrchestrator({
    patientId: ACTIVE_PATIENT_ID ?? undefined,
    runtime: initialRuntime === "codex" ? "CodexSubprocess" : "ClaudeSDK",
  });

  appendProfessionalSessionLog(`Chat CLI iniciado com runtime inicial: ${initialRuntime}${ACTIVE_PATIENT_ID ? ` e paciente ativo ${ACTIVE_PATIENT_ID} ${getPatientName(ACTIVE_PATIENT_ID)}` : ""}.`);
  printHeader(runtimeRef.value);

  try {
    while (true) {
      if (runtimeRef.value === "claude") {
        orchestrator.setRuntime("ClaudeSDK");
        await runClaudeLoop(rl, runtimeRef, orchestrator);
        if (runtimeRef.value === "claude") break;
        if ((rl as any).closed) {
          rl = createInterface({ input: process.stdin, output: process.stdout });
        }
        continue;
      }

      const input = await ask(rl, runtimeRef.value);
      const trimmed = input.trim();
      if (!trimmed) continue;

      orchestrator.setRuntime(runtimeRef.value === "codex" ? "CodexSubprocess" : "ClaudeSDK");
      const commandHandled = handleCommand(trimmed, runtimeRef, orchestrator);
      if (commandHandled === "quit") break;
      if (commandHandled === "handled") continue;

      transcript.push({ role: "user", text: trimmed });
      orchestrator.setRuntime("CodexSubprocess");
      await handleCodexTurn(trimmed, transcript, orchestrator);

      if (transcript.length > 16) {
        transcript.splice(0, transcript.length - 16);
      }
    }
  } finally {
    appendProfessionalSessionLog(`Chat CLI encerrado. Runtime final: ${runtimeRef.value}${ACTIVE_PATIENT_ID ? `; paciente ativo ${ACTIVE_PATIENT_ID}` : ""}. Turnos registrados em memoria de sessão local: ${transcript.length}.`);
    if (!(rl as any).closed) {
      rl.close();
    }
  }
}


// ============================================================================
// ENTRY POINT
// ============================================================================

const isDirectRun = basename(process.argv[1] || "") === "chat-cli.ts"
  || basename(process.argv[1] || "") === "chat-cli.js";

if (isDirectRun) {
  chatLoop().catch((err) => {
    console.error(`\n${colors.red}Erro fatal: ${err.message}${colors.reset}`);
    process.exit(1);
  });
}
