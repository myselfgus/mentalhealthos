import { execSync, spawn } from "child_process";
import { PATHS } from "../../config/defaults.js";
import { readHealthOSAgent } from "./agents.js";
import { readCodexAgent } from "./codex-agents.js";

export type CodexTranscriptEntry = {
  role: "user" | "assistant";
  text: string;
};

export type CodexExecOptions = {
  agent?: string;
  sandbox?: "read-only" | "workspace-write" | "danger-full-access";
  transcript?: CodexTranscriptEntry[];
  timeoutMs?: number;
  systemPrompt?: string;
  prompt?: string;
};

export function getCommandPath(command: string): string | null {
  try {
    return execSync(`command -v ${command}`, {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim() || null;
  } catch {
    return null;
  }
}

export function getCodexStatus(): string {
  try {
    return execSync("codex login status 2>&1", {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 10_000,
    }).trim();
  } catch (err: any) {
    return `Codex indisponivel: ${(err.stderr || err.message || "").toString().trim()}`;
  }
}

export function buildCodexPrompt(input: string, options: CodexExecOptions = {}): string {
  const recentTranscript = (options.transcript ?? [])
    .slice(-8)
    .map((entry) => `${entry.role === "user" ? "Usuario" : "Assistente"}: ${entry.text}`)
    .join("\n\n");

  const healthOSAgentDefinition = readHealthOSAgent(options.agent);
  const codexAgentDefinition = readCodexAgent(options.agent);
  const agentBlock = healthOSAgentDefinition
    ? `\n## Agente HealthOS selecionado: ${options.agent}\n\nUse esta definicao do projeto como especializacao da tarefa:\n\n${healthOSAgentDefinition}\n`
    : codexAgentDefinition
      ? `\n## Subagente Codex selecionado: ${options.agent}\n\nUse esta definicao instalada em ~/.codex/agents como especializacao da tarefa:\n\n\`\`\`toml\n${codexAgentDefinition}\n\`\`\`\n`
      : options.agent
        ? `\n## Agente solicitado\n\nO agente "${options.agent}" nao foi encontrado em src/agents nem em ~/.codex/agents; siga com a configuracao Codex instalada.\n`
        : "";

  return `${options.systemPrompt ?? ""}

## Runtime

Voce esta rodando como subprocesso Codex local dentro do HealthOS.
Use a configuracao instalada em ~/.codex, incluindo login ChatGPT, MCPs, plugins, skills, regras e profiles disponiveis.
Nao peca OPENAI_API_KEY para executar tarefas Codex locais.

${agentBlock}
${recentTranscript ? `## Contexto recente da conversa\n\n${recentTranscript}\n\n` : ""}## Pedido atual

${input}`;
}

export async function runCodexExec(input: string, options: CodexExecOptions = {}): Promise<string> {
  const codexPath = getCommandPath("codex");
  if (!codexPath) {
    throw new Error("Codex CLI nao encontrado no PATH.");
  }

  const sandbox = options.sandbox || process.env.HEALTHOS_CODEX_SANDBOX || "workspace-write";
  const args = [
    "--sandbox", sandbox,
    "-a", "never",
    "--cd", PATHS.BASE,
  ];

  const profile = process.env.HEALTHOS_CODEX_PROFILE;
  if (profile) {
    args.push("--profile", profile);
  }

  args.push("exec", "--skip-git-repo-check", "-");
  const stdin = options.prompt ?? buildCodexPrompt(input, options);

  return await new Promise((resolve, reject) => {
    const child = spawn(codexPath, args, {
      cwd: PATHS.BASE,
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        HEALTHOS_BASE: PATHS.BASE,
      },
    });

    let stdout = "";
    let stderr = "";
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error("Codex excedeu o tempo limite da execucao."));
    }, options.timeoutMs ?? 600_000);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });

    child.on("close", (code) => {
      clearTimeout(timeout);
      if (code === 0) {
        resolve(stdout.trim());
        return;
      }

      reject(new Error((stderr || stdout || `Codex saiu com codigo ${code}`).trim()));
    });

    child.stdin.write(stdin);
    child.stdin.end();
  });
}
