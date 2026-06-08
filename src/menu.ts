#!/usr/bin/env node
/**
 * HealthOS Psy - Terminal menu
 */

import { spawn } from "child_process";
import { createInterface, type Interface } from "readline";
import { existsSync, readdirSync, readFileSync, rmSync, statSync } from "fs";
import { join } from "path";
import {
  ensureProfessionalConfig,
  getProfessionalWorkspaceSummary,
  listProfessionals,
  loadProfessionalConfig,
  selectProfessional,
  updateProfessionalConfig,
} from "./pipeline/1-professional-config.js";
import { PATHS } from "./config/defaults.js";
import { listLLMRuntimes, normalizeRuntime, type HealthOSLLMRuntime } from "./lib/llm/runtime.js";
import { badge, createSpinner, info, printStatusLine, rule, section, success, ui, warn } from "./lib/terminal-ui.js";
import { getActiveProfessionalId } from "./professionals/workspace.js";
import { listPatientIds, listPatientSessionWorkspaces, listSessionAudioPaths, loadPatientProfile } from "./patients/workspace.js";

const PAT_DIR = PATHS.PAT;

const runtimeFlagIndex = process.argv.findIndex((arg) => arg === "--runtime");
const runtimeFlag = runtimeFlagIndex >= 0 ? process.argv[runtimeFlagIndex + 1] : null;
const runtimeLockedByEnv = Boolean(process.env.HEALTHOS_LLM_RUNTIME);
let selectedRuntime: HealthOSLLMRuntime = normalizeRuntime(runtimeFlag || process.env.HEALTHOS_LLM_RUNTIME);
let rl: Interface | null = null;

type MenuAction = {
  key: string;
  label: string;
  detail: string;
  run: () => Promise<void>;
};

type ProjectCounts = {
  patients: number;
  patientsWithTranscriptions: number;
  audio: number;
  transcripts: number;
  speech: number;
  asl: number;
  vdlp: number;
  gem: number;
};

type PatientMenuSummary = {
  id: string;
  name: string;
  sessions: number;
  audio: number;
  transcriptions: number;
  speech: number;
  asl: number;
  vdlp: number;
  gem: number;
};

function createReadlineInterface(): Interface {
  return createInterface({ input: process.stdin, output: process.stdout });
}

function clearScreen(): void {
  if (process.stdout.isTTY) console.clear();
}

async function ask(question: string): Promise<string> {
  rl = createReadlineInterface();
  return await new Promise((resolve) => {
    rl?.question(question, (answer) => {
      rl?.close();
      rl = null;
      resolve(answer.trim());
    });
  });
}

async function pause(message = "Pressione ENTER para continuar..."): Promise<void> {
  await ask(`${ui.dim}${message}${ui.reset}`);
}

function countFiles(dir: string, extensions?: string[]): number {
  if (!existsSync(dir)) return 0;
  const entries = readdirSync(dir);
  if (!extensions) return entries.length;
  return entries.filter((entry) => extensions.some((ext) => entry.toLowerCase().endsWith(ext))).length;
}

function listPatients(): string[] {
  return listPatientIds();
}

function getPatientName(patientId: string): string {
  const profile = loadPatientProfile(patientId);
  return profile?.identity?.full_name || profile?.patient_name || "Nome nao informado";
}

function getPatientSummary(patientId: string): PatientMenuSummary {
  const sessions = listPatientSessionWorkspaces(patientId);
  return {
    id: patientId,
    name: getPatientName(patientId),
    sessions: sessions.length,
    audio: sessions.reduce((total, session) => total + listSessionAudioPaths(session).length, 0),
    transcriptions: sessions.filter((session) => existsSync(session.transcriptionPath)).length,
    speech: sessions.filter((session) => existsSync(session.patientSpeechTextPath) || existsSync(session.patientSpeechJsonPath) || existsSync(session.patientSpeechMarkdownPath)).length,
    asl: sessions.filter((session) => existsSync(session.aslPath)).length,
    vdlp: sessions.filter((session) => existsSync(session.vdlpPath)).length,
    gem: sessions.filter((session) => existsSync(session.gemPath)).length,
  };
}

function formatPatientSummary(summary: PatientMenuSummary): string {
  return `${summary.id} ${ui.bold}${summary.name}${ui.reset} ${ui.dim}sessoes=${summary.sessions} audio=${summary.audio} transcr=${summary.transcriptions} speech=${summary.speech} ASL=${summary.asl} VDLP=${summary.vdlp} GEM=${summary.gem}${ui.reset}`;
}

function collectCounts(): ProjectCounts {
  const patients = listPatients();
  let speech = 0;
  let asl = 0;
  let vdlp = 0;
  let gem = 0;
  let audio = 0;
  let transcripts = 0;

  for (const patient of patients) {
    for (const session of listPatientSessionWorkspaces(patient)) {
      audio += listSessionAudioPaths(session).length;
      transcripts += Number(existsSync(session.transcriptionPath));
      speech += Number(existsSync(session.patientSpeechTextPath) || existsSync(session.patientSpeechJsonPath) || existsSync(session.patientSpeechMarkdownPath));
      asl += Number(existsSync(session.aslPath));
      vdlp += Number(existsSync(session.vdlpPath));
      gem += Number(existsSync(session.gemPath));
    }
  }

  return {
    patients: patients.length,
    patientsWithTranscriptions: patients.filter((patient) => listPatientSessionWorkspaces(patient).some((session) => existsSync(session.transcriptionPath))).length,
    audio,
    transcripts,
    speech,
    asl,
    vdlp,
    gem,
  };
}

function frame(progress: number): string {
  const width = 26;
  const filled = Math.max(0, Math.min(width, Math.round(width * progress)));
  return `${"█".repeat(filled)}${"░".repeat(width - filled)}`;
}

async function intro(): Promise<void> {
  if (!process.stdout.isTTY) return;

  const steps = [
    ["boot", 0.12],
    ["config", 0.28],
    ["patients", 0.46],
    ["runtime", 0.68],
    ["pipeline", 0.86],
    ["ready", 1],
  ] as const;

  for (const [label, progress] of steps) {
    clearScreen();
    console.log("");
    console.log(`${ui.cyan}${ui.bold}HealthOS Psy${ui.reset}`);
    console.log(`${ui.dim}${rule()}${ui.reset}`);
    console.log(`${ui.dim}workspace${ui.reset} ${PATHS.BASE}`);
    console.log(`${ui.dim}runtime  ${ui.reset} ${badge(selectedRuntime, ui.magenta)}`);
    console.log("");
    console.log(`${ui.cyan}${frame(progress)}${ui.reset} ${Math.round(progress * 100)}%`);
    console.log(`${ui.dim}${label}${ui.reset}`);
    await new Promise((resolve) => setTimeout(resolve, 90));
  }
}

function renderHeader(): void {
  clearScreen();
  printStatusLine(selectedRuntime);

  const config = loadProfessionalConfig();
  const counts = collectCounts();

  if (config) {
    info("profissional", `${config.nome} (${config.registro})`);
  } else {
    warn("Configuracao profissional ainda nao foi criada.");
  }

  info("dados", `${counts.patients} dossies | ${counts.patientsWithTranscriptions} com transcricoes | ${counts.audio} audios`);
  info("analises", `${counts.speech} falas | ${counts.asl} ASL | ${counts.vdlp} VDLP | ${counts.gem} GEM`);
  console.log(`${ui.dim}${rule()}${ui.reset}`);
}

function buildMenuActions(): MenuAction[] {
  return [
    {
      key: "1",
      label: "Transcrever audios",
      detail: "sessions/*/source/audio -> source/transcription.json",
      run: () => executeScript("npm", ["run", "transcribe"], "Transcrever audios", false),
    },
    {
      key: "2",
      label: "Processar transcricoes",
      detail: "legado: audio/transcriptions -> patients/PAT_000001",
      run: () => executeScript("npm", ["run", "pipeline:process"], "Processar transcricoes", true),
    },
    {
      key: "3",
      label: "Extrair fala do paciente",
      detail: "sessions/source -> sessions/analysis/patient-speech",
      run: () => executeScript("npm", ["run", "pipeline:speech"], "Extrair fala do paciente", true),
    },
    {
      key: "4",
      label: "Gerar ASL",
      detail: "sessions/analysis/asl.json",
      run: () => executeScript("npm", ["run", "pipeline:asl"], "Gerar ASL", true),
    },
    {
      key: "5",
      label: "Gerar VDLP",
      detail: "sessions/analysis/vdlp.json",
      run: () => executeScript("npm", ["run", "pipeline:vdlp"], "Gerar VDLP", true),
    },
    {
      key: "6",
      label: "Gerar GEM",
      detail: "sessions/analysis/gem.json",
      run: () => executeScript("npm", ["run", "pipeline:gem"], "Gerar GEM", true),
    },
    {
      key: "C",
      label: "Chat CLI",
      detail: selectedRuntime === "Codex" ? "chat com Codex local" : "chat com Claude Code",
      run: () => executeChat(),
    },
    {
      key: "T",
      label: "Chat do paciente",
      detail: "abrir chat-agent com contexto de um paciente",
      run: executePatientChat,
    },
    {
      key: "P",
      label: "Explorar pacientes",
      detail: "abrir dossies e arquivos",
      run: explorePatientDossiers,
    },
    {
      key: "S",
      label: "Status do projeto",
      detail: "pastas, arquivos e outputs",
      run: showFolderStatus,
    },
    {
      key: "R",
      label: "Runtime LLM",
      detail: `atual: ${selectedRuntime}`,
      run: selectRuntime,
    },
    {
      key: "O",
      label: "Profissional",
      detail: "gerenciar workspace profissional",
      run: updateProfessionalConfigScreen,
    },
    {
      key: "K",
      label: "Limpar outputs",
      detail: "remove dossies em patients/",
      run: cleanOutputs,
    },
  ];
}

function renderMenu(actions: MenuAction[]): void {
  section("Pipeline");
  for (const action of actions.slice(0, 6)) {
    console.log(`${badge(action.key, ui.cyan)} ${ui.bold}${action.label}${ui.reset} ${ui.dim}${action.detail}${ui.reset}`);
  }

  section("Operacao");
  for (const action of actions.slice(6)) {
    console.log(`${badge(action.key, ui.magenta)} ${ui.bold}${action.label}${ui.reset} ${ui.dim}${action.detail}${ui.reset}`);
  }

  console.log("");
  console.log(`${badge("0", ui.red)} Sair`);
  console.log("");
}

async function selectRuntime(): Promise<void> {
  if (runtimeLockedByEnv) {
    warn(`Runtime fixado por HEALTHOS_LLM_RUNTIME=${process.env.HEALTHOS_LLM_RUNTIME}.`);
    await pause();
    return;
  }

  renderHeader();
  section("Runtime LLM");
  const runtimes = listLLMRuntimes();
  runtimes.forEach((runtime, index) => {
    const current = runtime === selectedRuntime ? `${ui.green}atual${ui.reset}` : "";
    console.log(`${badge(String(index + 1), ui.cyan)} ${runtime} ${ui.dim}${current}${ui.reset}`);
  });
  console.log("");

  const choice = await ask(`${ui.bold}Escolha o runtime [ENTER mantém ${selectedRuntime}]: ${ui.reset}`);
  const index = Number(choice) - 1;
  if (choice && runtimes[index]) {
    selectedRuntime = runtimes[index];
  }
}

async function executeScript(command: string, args: string[], description: string, usesLLM: boolean): Promise<void> {
  renderHeader();
  section(description, usesLLM ? selectedRuntime : undefined);
  info("comando", [command, ...args].join(" "));
  if (usesLLM) info("runtime", selectedRuntime);
  console.log("");

  await new Promise<void>((resolve) => {
    const child = spawn(command, args, {
      cwd: PATHS.BASE,
      stdio: "inherit",
      env: {
        ...process.env,
        HEALTHOS_BASE: PATHS.BASE,
        HEALTHOS_LLM_RUNTIME: selectedRuntime,
        HEALTHOS_PROFESSIONAL_ID: getActiveProfessionalId() || "",
      },
    });

    child.on("close", (code) => {
      console.log("");
      if (code === 0) success(`${description} concluido.`);
      else warn(`${description} terminou com codigo ${code}.`);
      resolve();
    });

    child.on("error", (error) => {
      warn(`Erro ao executar ${description}: ${error.message}`);
      resolve();
    });
  });

  await pause();
}

async function executeChat(): Promise<void> {
  const args = ["run", "chat-cli", "--", "--runtime", selectedRuntime === "Codex" ? "codex" : "claude"];

  await executeScript("npm", args, "HealthOS Chat CLI", false);
}

async function executePatientChat(): Promise<void> {
  const patientId = await choosePatient("Chat do paciente");
  if (!patientId) return;

  const args = [
    "run",
    "chat-cli",
    "--",
    "--runtime",
    selectedRuntime === "Codex" ? "codex" : "claude",
    "--patient",
    patientId,
  ];

  await executeScript("npm", args, `HealthOS Chat CLI - ${patientId} ${getPatientName(patientId)}`, false);
}

async function showFolderStatus(): Promise<void> {
  renderHeader();
  section("Status do projeto");

  const counts = collectCounts();
  info("audio", `${counts.audio} arquivo(s) em sessions/*/source/audio`);
  info("transcricoes", `${counts.transcripts} JSON em sessions/*/source/transcription.json`);
  info("pacientes", `${counts.patients} dossie(s) em ${PAT_DIR}`);
  info("acionaveis", `${counts.patientsWithTranscriptions} dossie(s) com sessions/*/source/transcription.json`);
  info("patient-speech", String(counts.speech));
  info("ASL", String(counts.asl));
  info("VDLP", String(counts.vdlp));
  info("GEM", String(counts.gem));
  info("profissionais", `${listProfessionals().length} workspace(s) em ${PATHS.PROFESSIONALS}`);
  info("profissional ativo", getProfessionalWorkspaceSummary());

  const patients = listPatients();
  if (patients.length > 0) {
    console.log("");
    console.log(`${ui.bold}Dossies${ui.reset}`);
    for (const patient of patients) {
      const summary = getPatientSummary(patient);
      console.log(formatPatientSummary(summary));
    }
  }

  console.log("");
  await pause();
}

async function explorePatientDossiers(): Promise<void> {
  const patient = await choosePatient("Pacientes");
  if (patient) await explorePatientFolder(patient);
}

async function choosePatient(title: string): Promise<string | null> {
  const patients = listPatients();
  if (patients.length === 0) {
    renderHeader();
    warn("Nenhum paciente encontrado em patients/.");
    await pause();
    return null;
  }

  while (true) {
    renderHeader();
    section(title);
    patients.forEach((patient, index) => {
      console.log(`${badge(String(index + 1), ui.cyan)} ${formatPatientSummary(getPatientSummary(patient))}`);
    });
    console.log(`${badge("0", ui.red)} Voltar\n`);

    const choice = await ask(`${ui.bold}Paciente: ${ui.reset}`);
    if (!choice || choice === "0") return null;

    const patient = patients[Number(choice) - 1];
    if (patient) return patient;
  }
}

async function explorePatientFolder(patientId: string): Promise<void> {
  const patientDir = join(PAT_DIR, patientId);
  const folders = [
    ["patient.json", "Patient JSON"],
    ["sessions", "Sessoes"],
    ["agents", "Agentes do paciente"],
    ["artifacts", "Artefatos"],
    ["logs", "Logs"],
    ["telemetry", "Telemetria"],
  ] as const;

  while (true) {
    renderHeader();
    section(`Dossie ${patientId} - ${getPatientName(patientId)}`);
    folders.forEach(([folder, label], index) => {
      const path = join(patientDir, folder);
      const count = folder.endsWith(".json") ? (existsSync(path) ? 1 : 0) : countFiles(path, [".json", ".md", ".txt"]);
      console.log(`${badge(String(index + 1), ui.cyan)} ${label} ${ui.dim}${folder} (${count})${ui.reset}`);
    });
    console.log(`${badge("C", ui.magenta)} Abrir Chat do paciente ${ui.dim}${patientId} ${getPatientName(patientId)}${ui.reset}`);
    console.log(`${badge("0", ui.red)} Voltar\n`);

    const choice = await ask(`${ui.bold}Abrir: ${ui.reset}`);
    if (!choice || choice === "0") return;

    if (choice.trim().toUpperCase() === "C") {
      await executeScript("npm", [
        "run",
        "chat-cli",
        "--",
        "--runtime",
        selectedRuntime === "Codex" ? "codex" : "claude",
        "--patient",
        patientId,
      ], `HealthOS Chat CLI - ${patientId} ${getPatientName(patientId)}`, false);
      continue;
    }

    const selected = folders[Number(choice) - 1];
    if (!selected) continue;

    const [folder, label] = selected;
    const path = join(patientDir, folder);
    if (folder.endsWith(".json")) {
      await viewFile(label, path);
    } else {
      await exploreFolderFiles(label, path);
    }
  }
}

async function exploreFolderFiles(label: string, folderPath: string): Promise<void> {
  if (!existsSync(folderPath)) {
    warn(`Pasta nao encontrada: ${folderPath}`);
    await pause();
    return;
  }

  while (true) {
    renderHeader();
    section(label);
    const files = readdirSync(folderPath).filter((file) => /\.(json|md|txt)$/i.test(file)).sort();
    if (files.length === 0) {
      warn("Nenhum arquivo encontrado.");
      await pause();
      return;
    }

    files.forEach((file, index) => {
      const sizeKb = (statSync(join(folderPath, file)).size / 1024).toFixed(1);
      console.log(`${badge(String(index + 1), ui.cyan)} ${file} ${ui.dim}${sizeKb} KB${ui.reset}`);
    });
    console.log(`${badge("0", ui.red)} Voltar\n`);

    const choice = await ask(`${ui.bold}Arquivo: ${ui.reset}`);
    if (!choice || choice === "0") return;

    const selected = files[Number(choice) - 1];
    if (selected) await viewFile(selected, join(folderPath, selected));
  }
}

async function viewFile(title: string, filePath: string): Promise<void> {
  renderHeader();
  section(title);
  if (!existsSync(filePath)) {
    warn(`Arquivo nao encontrado: ${filePath}`);
    await pause();
    return;
  }

  const content = readFileSync(filePath, "utf-8");
  console.log(`${ui.dim}${filePath}${ui.reset}`);
  console.log(`${ui.dim}${rule()}${ui.reset}`);
  if (filePath.endsWith(".json")) {
    try {
      console.log(JSON.stringify(JSON.parse(content), null, 2));
    } catch {
      console.log(content);
    }
  } else {
    console.log(content);
  }
  console.log(`${ui.dim}${rule()}${ui.reset}`);
  await pause();
}

async function updateProfessionalConfigScreen(): Promise<void> {
  while (true) {
    renderHeader();
    section("Profissional");

    const config = loadProfessionalConfig();
    if (config) {
      info("ativo", `${config.nome} (${config.registro})`);
      info("workspace", getProfessionalWorkspaceSummary());
    } else {
      warn("Nenhum profissional ativo configurado.");
    }

    const professionals = listProfessionals();
    console.log("");
    console.log(`${badge("1", ui.cyan)} Criar ou atualizar profissional ativo`);
    console.log(`${badge("2", ui.cyan)} Selecionar profissional ativo ${ui.dim}${professionals.length} disponiveis${ui.reset}`);
    console.log(`${badge("0", ui.red)} Voltar\n`);

    const choice = await ask(`${ui.bold}Acao profissional: ${ui.reset}`);
    if (!choice || choice === "0") return;

    if (choice === "1") {
      await updateProfessionalConfig();
      await pause();
      continue;
    }

    if (choice === "2") {
      await selectProfessionalScreen();
      continue;
    }
  }
}

async function selectProfessionalScreen(): Promise<void> {
  const professionals = listProfessionals();
  if (professionals.length === 0) {
    warn("Nenhum workspace profissional encontrado.");
    await pause();
    return;
  }

  renderHeader();
  section("Selecionar profissional");
  professionals.forEach((id, index) => {
    const current = id === getActiveProfessionalId() ? `${ui.green}ativo${ui.reset}` : "";
    console.log(`${badge(String(index + 1), ui.cyan)} ${id} ${ui.dim}${current}${ui.reset}`);
  });
  console.log(`${badge("0", ui.red)} Voltar\n`);

  const choice = await ask(`${ui.bold}Profissional: ${ui.reset}`);
  if (!choice || choice === "0") return;

  const selected = professionals[Number(choice) - 1];
  if (!selected) {
    warn("Profissional invalido.");
    await pause();
    return;
  }

  const config = selectProfessional(selected);
  if (config) success(`Profissional ativo: ${config.nome}`);
  else warn("Nao foi possivel ativar o profissional selecionado.");
  await pause();
}

async function cleanOutputs(): Promise<void> {
  renderHeader();
  section("Limpar outputs");
  warn("Esta acao remove todos os dossies em patients/.");
  const answer = await ask(`${ui.bold}Digite LIMPAR para confirmar: ${ui.reset}`);
  if (answer !== "LIMPAR") {
    warn("Operacao cancelada.");
    await pause();
    return;
  }

  const stop = createSpinner("Removendo outputs");
  if (existsSync(PAT_DIR)) {
    for (const entry of readdirSync(PAT_DIR)) {
      if (!entry.startsWith(".")) {
        rmSync(join(PAT_DIR, entry), { recursive: true, force: true });
      }
    }
  }
  stop();
  success("Outputs removidos.");
  await pause();
}

async function handleMenu(choice: string, actions: MenuAction[]): Promise<boolean> {
  const normalized = choice.trim().toUpperCase();
  if (normalized === "0" || normalized === "Q") return false;

  const action = actions.find((item) => item.key.toUpperCase() === normalized);
  if (!action) {
    warn("Opcao invalida.");
    await pause();
    return true;
  }

  await action.run();
  return true;
}

async function main(): Promise<void> {
  let running = true;

  await intro();
  await ensureProfessionalConfig();

  if (!runtimeFlag && !runtimeLockedByEnv && process.stdin.isTTY) {
    await selectRuntime();
  }

  while (running) {
    const actions = buildMenuActions();
    renderHeader();
    renderMenu(actions);
    const choice = await ask(`${ui.bold}Acao: ${ui.reset}`);
    running = await handleMenu(choice, actions);
  }

  clearScreen();
  console.log(`${ui.cyan}${ui.bold}HealthOS Psy encerrado.${ui.reset}\n`);
}

main().catch((error) => {
  console.error(`${ui.red}${ui.bold}Erro fatal:${ui.reset}`, error);
  rl?.close();
  process.exit(1);
});
