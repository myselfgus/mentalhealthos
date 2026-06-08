import { MODELS } from "../../config/defaults.js";
import { claudeAPIProvider } from "./providers/claude-api.js";
import { claudeCodeProvider } from "./providers/claude-code.js";
import { codexProvider } from "./providers/codex.js";
import type { LLMProvider, LLMRuntimeName, LLMTextRequest, LLMTextResponse } from "./types.js";
export { CODEX_AGENTS_DIR, listCodexAgents, readCodexAgent } from "./codex-agents.js";

export { MODELS };
export type { LLMRuntimeName, LLMTextRequest, LLMTextResponse };
export type HealthOSLLMRuntime = LLMRuntimeName;

export function normalizeRuntime(value?: string | null): LLMRuntimeName {
  const raw = (value || "").trim().toLowerCase();
  if (raw === "claudecode" || raw === "claude-code" || raw === "claude_code") return "ClaudeCode";
  if (raw === "codex") return "Codex";
  return "ClaudeAPI";
}

export function getSelectedRuntime(): LLMRuntimeName {
  return normalizeRuntime(process.env.HEALTHOS_LLM_RUNTIME || process.env.HEALTHOS_CHAT_RUNTIME);
}

export const getSelectedLLMRuntime = getSelectedRuntime;

export function listLLMRuntimes(): LLMRuntimeName[] {
  return ["ClaudeAPI", "ClaudeCode", "Codex"];
}

export function getLLMClient(runtime: LLMRuntimeName = getSelectedRuntime()): LLMProvider {
  if (runtime === "ClaudeCode") return claudeCodeProvider;
  if (runtime === "Codex") return codexProvider;
  return claudeAPIProvider;
}

export async function callLLM(request: LLMTextRequest): Promise<string> {
  const response = await getLLMClient().generateText(request);
  return response.content;
}

export async function generateRuntimeText(request: LLMTextRequest): Promise<string> {
  const response = await getLLMClient(request.runtime).generateText(request);
  return response.content;
}

export function messagesToPrompt(messages: any[] = []): { systemPrompt: string; userPrompt: string } {
  const systemParts: string[] = [];
  const userParts: string[] = [];

  for (const message of messages) {
    const content = stringifyContent(message.content);
    if (message.role === "system") systemParts.push(content);
    else userParts.push(`${message.role || "user"}:\n${content}`);
  }

  return {
    systemPrompt: systemParts.join("\n\n"),
    userPrompt: userParts.join("\n\n"),
  };
}

function stringifyContent(content: any): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content.map((part) => {
      if (typeof part === "string") return part;
      if (part?.type === "text") return part.text || "";
      return JSON.stringify(part);
    }).join("\n");
  }
  return content == null ? "" : JSON.stringify(content);
}
