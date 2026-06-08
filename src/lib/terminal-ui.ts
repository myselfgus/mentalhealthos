import { execSync } from "child_process";
import { basename } from "path";
import { PATHS } from "../config/defaults.js";

const supportsColor = Boolean(process.stdout.isTTY && !process.env.NO_COLOR);

export const ui = {
  reset: supportsColor ? "\x1b[0m" : "",
  bold: supportsColor ? "\x1b[1m" : "",
  dim: supportsColor ? "\x1b[2m" : "",
  cyan: supportsColor ? "\x1b[36m" : "",
  green: supportsColor ? "\x1b[32m" : "",
  yellow: supportsColor ? "\x1b[33m" : "",
  red: supportsColor ? "\x1b[31m" : "",
  magenta: supportsColor ? "\x1b[35m" : "",
  blue: supportsColor ? "\x1b[34m" : "",
};

export type RuntimeBadge = "ClaudeAPI" | "ClaudeCode" | "Codex";

export function terminalWidth(): number {
  return Math.max(72, Math.min(process.stdout.columns || 88, 120));
}

export function rule(char = "-"): string {
  return char.repeat(terminalWidth());
}

export function badge(label: string, color = ui.cyan): string {
  return `${color}${ui.bold} ${label} ${ui.reset}`;
}

export function runtimeColor(runtime: string): string {
  if (runtime === "Codex") return ui.magenta;
  if (runtime === "ClaudeCode") return ui.cyan;
  return ui.green;
}

export function printStatusLine(runtime: string): void {
  const git = getGitSegment();
  const cwd = basename(PATHS.BASE);
  console.log(`${ui.dim}${rule()}${ui.reset}`);
  console.log(`${badge("HealthOS Psy", ui.cyan)} ${badge(runtime, runtimeColor(runtime))} ${ui.dim}${cwd}${git ? ` | ${git}` : ""}${ui.reset}`);
  console.log(`${ui.dim}${rule()}${ui.reset}`);
}

export function section(title: string, runtime?: string): void {
  console.log("");
  console.log(`${ui.bold}${ui.cyan}${title}${ui.reset}${runtime ? ` ${badge(runtime, runtimeColor(runtime))}` : ""}`);
  console.log(`${ui.dim}${rule()}${ui.reset}`);
}

export function info(label: string, value: string): void {
  const padded = label.padEnd(20, " ");
  console.log(`${ui.dim}${padded}${ui.reset}${value}`);
}

export function success(message: string): void {
  console.log(`${ui.green}${ui.bold}OK${ui.reset} ${message}`);
}

export function warn(message: string): void {
  console.log(`${ui.yellow}${ui.bold}AVISO${ui.reset} ${message}`);
}

export function error(message: string): void {
  console.error(`${ui.red}${ui.bold}ERRO${ui.reset} ${message}`);
}

export function createSpinner(label: string): () => void {
  if (!process.stdout.isTTY) {
    console.log(`${ui.dim}${label}...${ui.reset}`);
    return () => {};
  }

  const frames = ["-", "\\", "|", "/"];
  let index = 0;
  process.stdout.write(`${ui.dim}${frames[index]} ${label}${ui.reset}`);
  const timer = setInterval(() => {
    index = (index + 1) % frames.length;
    process.stdout.write(`\r${ui.dim}${frames[index]} ${label}${ui.reset}`);
  }, 120);

  return () => {
    clearInterval(timer);
    process.stdout.write(`\r${" ".repeat(Math.min(terminalWidth(), label.length + 8))}\r`);
  };
}

function getGitSegment(): string {
  try {
    const branch = execSync("git branch --show-current", {
      cwd: PATHS.BASE,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const changed = execSync("git status --short", {
      cwd: PATHS.BASE,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).split("\n").filter(Boolean).length;

    return changed > 0 ? `${branch} +${changed}` : branch;
  } catch {
    return "";
  }
}
