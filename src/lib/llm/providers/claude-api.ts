import OpenAI from "openai";
import { config } from "dotenv";
import { CACHE, CLOUDFLARE, DEFAULT_CLAUDE_API_MODEL, PATHS } from "../../../config/defaults.js";
import type { LLMProvider, LLMTextRequest, LLMTextResponse } from "../types.js";

config({ path: PATHS.ENV, override: false });

const GATEWAY_TOKEN = process.env.CLOUDFLARE_AI_GATEWAY_TOKEN;
const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY;

let client: OpenAI | null = null;

function getClient(): OpenAI {
  const apiKey = GATEWAY_TOKEN || ANTHROPIC_KEY;
  if (!apiKey) {
    throw new Error("Missing Cloudflare AI Gateway token and provider key for ClaudeAPI runtime.");
  }

  client ??= new OpenAI({
    apiKey,
    baseURL: CLOUDFLARE.OPENAI_COMPAT_ENDPOINT,
    defaultHeaders: GATEWAY_TOKEN && ANTHROPIC_KEY
      ? { "cf-aig-authorization": `Bearer ${ANTHROPIC_KEY}` }
      : undefined,
  });

  return client;
}

export const claudeAPIProvider: LLMProvider = {
  name: "ClaudeAPI",
  async generateText(request: LLMTextRequest): Promise<LLMTextResponse> {
    const model = request.model ?? DEFAULT_CLAUDE_API_MODEL;
    if (!model) {
      throw new Error("ClaudeAPI runtime requires HEALTHOS_CLAUDE_API_MODEL or ANTHROPIC_MODEL.");
    }

    const body: any = {
      model,
      temperature: request.temperature ?? 0,
      messages: [
        {
          role: "system",
          content: normalizeSystemContent(request.systemPrompt, request.useCache),
        },
        { role: "user", content: request.userPrompt },
      ],
      // @ts-ignore - Anthropic beta headers via OpenAI-compatible gateway.
      extra_headers: request.useCache === false ? undefined : CACHE.BETA_HEADERS,
    };

    const response = await getClient().chat.completions.create(
      body,
      request.timeoutMs ? { timeout: request.timeoutMs } as any : undefined
    );

    const content = response.choices[0]?.message?.content || "";
    return {
      content,
      runtime: "ClaudeAPI",
      model: body.model,
      usage: {
        input: response.usage?.prompt_tokens || 0,
        output: response.usage?.completion_tokens || 0,
        total: response.usage?.total_tokens || 0,
      },
    };
  },
};

function normalizeSystemContent(systemPrompt?: string | any[], useCache = true): any {
  if (Array.isArray(systemPrompt)) return systemPrompt;
  const text = systemPrompt ? String(systemPrompt) : "";
  if (!useCache) return text;

  return [{
    type: "text",
    text,
    cache_control: { type: "ephemeral", ttl: CACHE.EXTENDED_TTL },
  }];
}
