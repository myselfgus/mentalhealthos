import { runCodexExec } from "../codex-exec.js";
import type { LLMProvider, LLMTextRequest, LLMTextResponse } from "../types.js";

export const codexProvider: LLMProvider = {
  name: "Codex",
  async generateText(request: LLMTextRequest): Promise<LLMTextResponse> {
    const output = await runCodexExec(request.userPrompt, {
      prompt: buildPrompt(request),
      timeoutMs: request.timeoutMs ?? 600_000,
    });
    return {
      content: output,
      runtime: "Codex",
      model: request.model,
    };
  },
};

function buildPrompt(request: LLMTextRequest): string {
  return `${formatSystem(request.systemPrompt)}## Tarefa HealthOS

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
