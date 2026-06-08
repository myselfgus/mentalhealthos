export type LLMRuntimeName = "ClaudeAPI" | "ClaudeCode" | "Codex";

export type LLMTextRequest = {
  systemPrompt?: string | any[];
  userPrompt: string;
  model?: string;
  temperature?: number;
  timeoutMs?: number;
  useCache?: boolean;
  runtime?: LLMRuntimeName;
};

export type LLMTextResponse = {
  content: string;
  usage?: {
    input: number;
    output: number;
    total: number;
  };
  runtime: LLMRuntimeName;
  model?: string;
};

export interface LLMProvider {
  name: LLMRuntimeName;
  generateText(request: LLMTextRequest): Promise<LLMTextResponse>;
}
