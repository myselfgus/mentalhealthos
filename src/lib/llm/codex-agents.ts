import { existsSync, readFileSync, readdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";

export const CODEX_AGENTS_DIR = join(homedir(), ".codex", "agents");

export function listCodexAgents(): string[] {
  if (!existsSync(CODEX_AGENTS_DIR)) return [];
  return readdirSync(CODEX_AGENTS_DIR)
    .filter((file) => file.endsWith(".toml"))
    .map((file) => file.replace(/\.toml$/, ""))
    .sort();
}

export function readCodexAgent(agent?: string): string | null {
  if (!agent) return null;
  const safeName = agent.replace(/[^a-zA-Z0-9._-]/g, "");
  const file = join(CODEX_AGENTS_DIR, `${safeName}.toml`);
  return existsSync(file) ? readFileSync(file, "utf-8") : null;
}
