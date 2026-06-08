import { spawn } from "child_process";
import { PATHS } from "../../../config/defaults.js";
import type { LLMProvider, LLMTextRequest, LLMTextResponse } from "../types.js";

export const claudeCodeProvider: LLMProvider = {
  name: "ClaudeCode",
  async generateText(request: LLMTextRequest): Promise<LLMTextResponse> {
    const output = await runProcess("claude", [
      "-p",
      "--output-format", "text",
      "--permission-mode", "acceptEdits",
      buildPrompt(request),
    ], request.timeoutMs ?? 600_000);

    return {
      content: output,
      runtime: "ClaudeCode",
      model: request.model,
    };
  },
};

function buildPrompt(request: LLMTextRequest): string {
  return `${formatSystem(request.systemPrompt)}## Tarefa

${request.userPrompt}

## Saida

Responda somente com o conteudo solicitado. Se a tarefa pedir JSON, retorne JSON valido sem markdown.`;
}

function formatSystem(systemPrompt?: string | any[]): string {
  if (!systemPrompt) return "";
  const text = Array.isArray(systemPrompt)
    ? systemPrompt.map((part) => part?.text || JSON.stringify(part)).join("\n")
    : String(systemPrompt);
  return `## Sistema\n\n${text}\n\n`;
}

function runProcess(command: string, args: string[], timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: PATHS.BASE,
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        HEALTHOS_BASE: PATHS.BASE,
      },
    });

    let stdout = "";
    let stderr = "";
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`${command} excedeu o tempo limite.`));
    }, timeoutMs);

    child.stdout?.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr?.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      if (code === 0) resolve(stdout.trim());
      else reject(new Error((stderr || stdout || `${command} saiu com codigo ${code}`).trim()));
    });
  });
}
