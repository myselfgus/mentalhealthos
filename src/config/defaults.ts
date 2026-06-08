/**
 * HealthOS — Configurações Centralizadas
 *
 * Todas as constantes, paths, modelos, timeouts e helpers
 * usados pelos módulos do pipeline.
 *
 * @author Dr. Gustavo Mendes e Silva
 */

import { join } from "path";
import { homedir } from "os";
import { readFileSync, existsSync } from "fs";

// ============================================================================
// PATHS — centralizados, sem hardcode em nenhum script
// ============================================================================

// Detecta BASE: env var > diretório atual se tiver package.json > fallback
const detectBase = (): string => {
  if (process.env.HEALTHOS_BASE) return process.env.HEALTHOS_BASE;

  // Se estamos no diretório do projeto (tem package.json com name=healthos)
  const cwd = process.cwd();
  try {
    const pkg = JSON.parse(readFileSync(join(cwd, "package.json"), "utf-8"));
    if (pkg.name === "healthos") return cwd;
  } catch {}

  // Fallback para ~/HealthOS ou ~/Desktop/healthos
  const candidates = [
    join(homedir(), "HealthOS"),
    join(homedir(), "Desktop", "healthos"),
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }

  return join(homedir(), "HealthOS");
};

const BASE = detectBase();

export const PATHS = {
  BASE,
  ENV: join(BASE, ".env"),
  PATIENTS: join(BASE, "patients"),
  PAT: join(BASE, "patients"),
  AUDIO: join(BASE, "audio"),
  TRANSCRIPTIONS: join(BASE, "audio", "transcriptions"),
  PROFESSIONALS: join(BASE, "professionals"),
  ACTIVE_PROFESSIONAL: join(BASE, "professionals", "active-professional.json"),
  RUNS: join(BASE, "runs"),
} as const;

// ============================================================================
// CLOUDFLARE AI GATEWAY
// ============================================================================

const CF_ACCOUNT_ID = process.env.CLOUDFLARE_ACCOUNT_ID
  || "1a481f7cdb7027c30174a692c89cbda1";

const CF_GATEWAY_NAME = process.env.CLOUDFLARE_GATEWAY_NAME
  || "healthos";

export const CLOUDFLARE = {
  ACCOUNT_ID: CF_ACCOUNT_ID,
  GATEWAY_NAME: CF_GATEWAY_NAME,
  OPENAI_COMPAT_ENDPOINT: `https://gateway.ai.cloudflare.com/v1/${CF_ACCOUNT_ID}/${CF_GATEWAY_NAME}/anthropic/v1`,
  WORKERS_AI_ENDPOINT: `https://gateway.ai.cloudflare.com/v1/${CF_ACCOUNT_ID}/${CF_GATEWAY_NAME}/workers-ai`,
} as const;

// ============================================================================
// MODELO PADRAO — usado apenas pelo runtime ClaudeAPI
// ============================================================================

export type GatewayModel = string;

export const DEFAULT_CLAUDE_API_MODEL =
  process.env.HEALTHOS_CLAUDE_API_MODEL
  || process.env.ANTHROPIC_MODEL;

export const MODELS = {
  DEFAULT: DEFAULT_CLAUDE_API_MODEL,
} as const;

// ============================================================================
// TOKENS
// ============================================================================

export const TOKENS = {
  /** Estimativa: ~4 chars por token */
  CHARS_PER_TOKEN: 4,
} as const;

// ============================================================================
// TIMEOUTS (em ms)
// ============================================================================

export const TIMEOUTS = {
  SHORT: 30_000,
  MEDIUM: 120_000,
  LONG: 300_000,
  EXTRA_LONG: 600_000,

  PER_OPERATION: {
    TRANSCRIBE: 180_000,
    PROCESS: 120_000,
    ASL: 300_000,
    VDLP: 300_000,
    GEM: 600_000,
    NARRATIVE: 300_000,
    FINETUNE: 300_000,
    SOAP: 300_000,
  },
} as const;

// ============================================================================
// RETRY
// ============================================================================

export const RETRY = {
  MAX_ATTEMPTS: 3,
  BASE_DELAY_MS: 2_000,
  RATE_LIMIT_DELAY_MS: 10_000,
} as const;

// ============================================================================
// CACHE (Anthropic prompt caching)
// ============================================================================

export const CACHE = {
  EXTENDED_TTL: "1h",
  BETA_HEADERS: {
    "anthropic-beta": "prompt-caching-2024-07-31,extended-cache-ttl-2025-04-11",
  },
} as const;

// ============================================================================
// TEMPERATURE
// ============================================================================

export const TEMPERATURE = {
  /** Extração de dados, JSON, metadados */
  EXTRACTION: 0.1,
  /** Análise clínica, ASL, VDLP, GEM */
  ANALYSIS: 0.3,
  /** Narrativa fenomenológica, escrita criativa */
  NARRATIVE: 0.7,
} as const;

// ============================================================================
// HELPERS
// ============================================================================

/**
 * Calcula timeout dinâmico baseado no tamanho do input e tipo de operação
 */
export function calculateDynamicTimeout(
  inputSizeChars: number,
  operation: keyof typeof TIMEOUTS.PER_OPERATION
): number {
  const baseTimeout = TIMEOUTS.PER_OPERATION[operation] ?? TIMEOUTS.MEDIUM;
  const estimatedTokens = inputSizeChars / TOKENS.CHARS_PER_TOKEN;

  // Escala: +50% para cada 50k tokens acima de 10k
  if (estimatedTokens > 10_000) {
    const factor = 1 + Math.floor((estimatedTokens - 10_000) / 50_000) * 0.5;
    return Math.min(baseTimeout * factor, TIMEOUTS.EXTRA_LONG);
  }

  return baseTimeout;
}

/**
 * Calcula delay de retry com backoff exponencial
 */
export function calculateRetryDelay(attempt: number, isRateLimit: boolean): number {
  if (isRateLimit) {
    return RETRY.RATE_LIMIT_DELAY_MS * attempt;
  }
  return RETRY.BASE_DELAY_MS * Math.pow(2, attempt - 1);
}

/**
 * Verifica se um erro é retryable (429, 5xx, timeout, rede)
 */
export function isRetryableError(error: any): boolean {
  const status = error?.status ?? error?.response?.status;

  if (status === 429) return true;  // Rate limit
  if (status >= 500) return true;   // Server error
  if (error?.code === "ECONNRESET") return true;
  if (error?.code === "ETIMEDOUT") return true;
  if (error?.name === "AbortError") return true;

  return false;
}
