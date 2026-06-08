/**
 * Gerenciamento de configuração profissional do HealthOS
 * Armazena dados do profissional para reutilização em toda a aplicação
 */

import { createInterface } from "readline";
import {
  ensureActiveProfessionalWorkspace,
  getActiveProfessionalWorkspace,
  listProfessionalIds,
  loadActiveProfessionalConfig,
  saveProfessionalConfig as saveProfessionalWorkspaceConfig,
  setActiveProfessional,
  type ProfessionalConfig,
} from "../professionals/workspace.js";

export type { ProfessionalConfig } from "../professionals/workspace.js";

/**
 * Carrega configuração profissional existente
 */
export function loadProfessionalConfig(): ProfessionalConfig | null {
  ensureActiveProfessionalWorkspace();
  return loadActiveProfessionalConfig();
}

/**
 * Salva configuração profissional
 */
export function saveProfessionalConfig(config: ProfessionalConfig): void {
  saveProfessionalWorkspaceConfig(config);
}

/**
 * Coleta dados profissionais via readline interface
 */
export async function collectProfessionalInfo(): Promise<ProfessionalConfig> {
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const ask = (question: string): Promise<string> => {
    return new Promise((resolve) => {
      rl.question(question, (answer) => resolve(answer.trim()));
    });
  };

  console.log("\n" + "=".repeat(80));
  console.log("👨‍⚕️  CONFIGURAÇÃO PROFISSIONAL");
  console.log("=".repeat(80));
  console.log("\nEssas informações serão usadas em todos os documentos gerados.\n");

  const nome = await ask("• Nome completo do profissional: ");
  const registro = await ask("• Registro profissional (CRM/CRP/COREN/etc): ");

  console.log("\n📝 Contexto de desambiguação (opcional):");
  console.log("   Use este campo para informar dados pessoais seus que podem ser");
  console.log("   mencionados em sessões (doenças, experiências, etc) para evitar");
  console.log("   que a IA os associe ao paciente.\n");

  const disambiguation = await ask("• Contexto de desambiguação (pressione ENTER para pular): ");

  rl.close();

  const config: ProfessionalConfig = {
    nome: nome || "Profissional",
    registro: registro || "",
    disambiguation_context: disambiguation || undefined,
    last_updated: new Date().toISOString(),
  };

  saveProfessionalConfig(config);
  const workspace = getActiveProfessionalWorkspace();

  console.log("\n✅ Configuração profissional salva!");
  if (workspace) {
    console.log(`📁 Workspace: ${workspace.dir}`);
  }
  console.log("=".repeat(80) + "\n");

  return config;
}

/**
 * Garante que configuração profissional existe, coletando se necessário
 */
export async function ensureProfessionalConfig(): Promise<ProfessionalConfig> {
  ensureActiveProfessionalWorkspace();
  let config = loadProfessionalConfig();

  if (!config) {
    config = await collectProfessionalInfo();
  }

  return config;
}

/**
 * Permite atualizar configuração profissional existente
 */
export async function updateProfessionalConfig(): Promise<ProfessionalConfig> {
  ensureActiveProfessionalWorkspace();
  const existing = loadProfessionalConfig();

  console.log("\n" + "=".repeat(80));
  console.log("🔄 ATUALIZAR CONFIGURAÇÃO PROFISSIONAL");
  console.log("=".repeat(80));

  if (existing) {
    console.log("\nConfigurações atuais:");
    console.log(`  Nome: ${existing.nome}`);
    console.log(`  Registro: ${existing.registro}`);
    if (existing.disambiguation_context) {
      console.log(`  Contexto de desambiguação: ${existing.disambiguation_context}`);
    }
    console.log("");
  }

  return await collectProfessionalInfo();
}

export function listProfessionals(): string[] {
  return listProfessionalIds();
}

export function selectProfessional(id: string): ProfessionalConfig | null {
  setActiveProfessional(id);
  return loadProfessionalConfig();
}

export function getProfessionalWorkspaceSummary(): string {
  const workspace = getActiveProfessionalWorkspace();
  if (!workspace) return "Nenhum workspace profissional ativo.";
  return `${workspace.id} em ${workspace.dir}`;
}
