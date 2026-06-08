/**
 * Utilidades para gerenciamento de dossiês de pacientes no HealthOS
 *
 * Estrutura de dossiê:
 * healthos/patients/PAT_000001/
 *   ├── patient.json       # Metadados canônicos
 *   ├── memory.md          # Memória clínica explícita
 *   ├── care-agent.md      # Agente operacional do caso
 *   ├── agents/            # Subagentes específicos do paciente
 *   ├── sessions/<SESSION_ID>/source/transcription.json
 *   ├── sessions/<SESSION_ID>/analysis/patient-speech.*
 *   ├── sessions/<SESSION_ID>/analysis/asl.json
 *   ├── sessions/<SESSION_ID>/analysis/vdlp.json
 *   ├── sessions/<SESSION_ID>/analysis/gem.json
 *   └── patient.json       # Índice e síntese longitudinal canônica
 */

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from "fs";
import { join } from "path";
import { createInterface } from "readline";
import { loadProfessionalConfig } from "./1-professional-config.js";
import { createPatientScaffold } from "../patients/workspace.js";
import { generateNextPatientId } from "../patients/ids.js";

export interface ProfessionalInfo {
  nome?: string;
  registro?: string;
}

export interface SessionInfo {
  numero?: string;
}

export interface ClinicalSummary {
  all_icd_codes: {
    code: string;
    description: string;
    first_mentioned: string;
    last_mentioned: string;
    occurrences: number;
    certainty_history: ("confirmed" | "suspected" | "rule_out")[];
  }[];
  all_medications: {
    name: string;
    first_mentioned: string;
    last_mentioned: string;
    contexts: ("current" | "past" | "discussed")[];
    dosages_mentioned?: string[];
  }[];
  common_topics: {
    topic: string;
    frequency: number;
  }[];
  encounter_types: {
    type: string;
    count: number;
  }[];
  last_updated: string;
}

export interface PatientMetadata {
  patient_id: string;
  patient_name?: string;
  patient_initials?: string;
  _profissional?: ProfessionalInfo;
  _sessao?: SessionInfo;
  sessions: SessionEntry[];
  clinical_summary?: ClinicalSummary;
}

export interface SessionEntry {
  source_file: string;
  source_slug: string;
  session?: string;
  date?: string;
  processed_at: string;
}

/**
 * Extrai iniciais do nome do paciente (máx 4 letras)
 * Exemplo: "Gustavo Mendes e Silva" → "GMS"
 */
export function extractInitials(fullName: string): string {
  if (!fullName || fullName.trim().length === 0) {
    return "XXX";
  }

  const normalized = fullName
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // Remove acentos
    .toUpperCase();

  const parts = normalized.split(/\s+/).filter((part) => part.length > 0);

  // Ignorar conectores comuns
  const connectors = ["E", "DE", "DA", "DO", "DAS", "DOS"];
  const significantParts = parts.filter((part) => !connectors.includes(part));

  // Pega primeira letra de cada parte (máx 4)
  const initials = significantParts.slice(0, 4).map((part) => part[0]).join("");

  return initials || "XXX";
}

/**
 * Gera Patient ID único no padrão PAT_000001.
 */
export function generatePatientID(
  _patientName: string,
  patBaseDir: string
): string {
  return generateNextPatientId(patBaseDir);
}

/**
 * Valida se um Patient ID existe no diretório informado.
 */
export function patientIDExists(patientID: string, patBaseDir: string): boolean {
  const patientPath = join(patBaseDir, patientID);
  return existsSync(patientPath);
}

/**
 * Cria estrutura de diretórios para dossiê do paciente
 */
export function ensurePatientDossier(
  patientID: string,
  _patBaseDir: string
): {
  patientDir: string;
  transcriptionsDir: string;
  documentsDir: string;
  analysisDir: string;
  graphDir: string;
  metadataPath: string;
} {
  const workspace = createPatientScaffold({
    ...( /^PAT_\d{6}$/.test(patientID) ? { patient_id: patientID } : {}),
    source: "patient-utils",
  });

  return {
    patientDir: workspace.dir,
    transcriptionsDir: join(workspace.sessionsDir, "UNASSIGNED", "source"),
    documentsDir: join(workspace.sessionsDir, "UNASSIGNED", "documents"),
    analysisDir: join(workspace.sessionsDir, "UNASSIGNED", "analysis"),
    graphDir: join(workspace.sessionsDir, "UNASSIGNED", "analysis"),
    metadataPath: workspace.profilePath,
  };
}

/**
 * Carrega metadados do paciente do patient.json
 */
export function loadPatientMetadata(metadataPath: string): PatientMetadata | null {
  if (!existsSync(metadataPath)) {
    return null;
  }

  try {
    const content = readFileSync(metadataPath, "utf-8");
    return JSON.parse(content);
  } catch (error) {
    console.warn(`⚠️  Erro ao ler ${metadataPath}:`, error);
    return null;
  }
}

/**
 * Salva metadados do paciente no patient.json
 */
export function savePatientMetadata(
  metadataPath: string,
  metadata: PatientMetadata
): void {
  writeFileSync(metadataPath, JSON.stringify(metadata, null, 2), "utf-8");
}

/**
 * Conferência profissional: coleta metadados após transcrição
 * Retorna: { patientID, patientName, profissional, sessao }
 */
export async function runProfessionalConference(
  patBaseDir: string,
  suggestedPatientName?: string
): Promise<{
  patientID: string;
  patientName: string;
  profissional: ProfessionalInfo;
  sessao: SessionInfo;
}> {
  // Carrega configuração profissional
  const professionalConfig = loadProfessionalConfig();

  const rl = createInterface({ input: process.stdin, output: process.stdout });

  const ask = (question: string): Promise<string> => {
    return new Promise((resolve) => {
      rl.question(question, (answer) => resolve(answer.trim()));
    });
  };

  console.log("\n" + "=".repeat(80));
  console.log("📝 CONFERÊNCIA PROFISSIONAL - Metadados da Sessão");
  console.log("=".repeat(80));

  if (professionalConfig) {
    console.log(`\n👨‍⚕️  Profissional: ${professionalConfig.nome} (${professionalConfig.registro})`);
  }

  console.log("\n💡 Pressione ENTER para manter/ignorar cada campo\n");

  // 1. Patient ID (opcional - para reusar dossiê existente)
  const inputPatientID = await ask("• Patient ID (opcional, ex: PAT_000001): ");
  let finalPatientID = "";
  let finalPatientName = suggestedPatientName || "";

  if (inputPatientID && patientIDExists(inputPatientID, patBaseDir)) {
    // Reusa dossiê existente
    console.log(`   ✅ Dossiê existente encontrado: ${inputPatientID}`);
    finalPatientID = inputPatientID;

    // Carrega nome do paciente do patient.json
    const dossier = ensurePatientDossier(inputPatientID, patBaseDir);
    const existingMetadata = loadPatientMetadata(dossier.metadataPath);
    if (existingMetadata && existingMetadata.patient_name) {
      finalPatientName = existingMetadata.patient_name;
      console.log(`   📋 Paciente: ${finalPatientName}`);
    }
  } else if (inputPatientID) {
    console.log(`   ⚠️  Patient ID "${inputPatientID}" não encontrado. Criando novo dossiê.`);
  }

  // 2. Nome do paciente (obrigatório se novo dossiê)
  if (!finalPatientID) {
    const inputPatientName = await ask(
      `• Nome do paciente${suggestedPatientName ? ` (detectado: "${suggestedPatientName}")` : ""}: `
    );

    finalPatientName = inputPatientName || suggestedPatientName || "Paciente Desconhecido";

    // Gera novo Patient ID
    finalPatientID = generatePatientID(finalPatientName, patBaseDir);
    console.log(`   ✅ Novo dossiê criado: ${finalPatientID}`);
  }

  // 3. Dados da sessão
  const numeroSessao = await ask("• Número da sessão: ");

  rl.close();

  console.log("\n" + "=".repeat(80));
  console.log("✅ Conferência concluída!");
  console.log("=".repeat(80) + "\n");

  return {
    patientID: finalPatientID,
    patientName: finalPatientName,
    profissional: {
      nome: professionalConfig?.nome || undefined,
      registro: professionalConfig?.registro || undefined,
    },
    sessao: {
      numero: numeroSessao || undefined,
    },
  };
}

/**
 * Atualiza summary clínico consolidado com novos metadados
 */
function updateClinicalSummary(
  currentSummary: ClinicalSummary | undefined,
  newClinicalMetadata: any,
  timestamp: string
): ClinicalSummary {
  const summary: ClinicalSummary = currentSummary || {
    all_icd_codes: [],
    all_medications: [],
    common_topics: [],
    encounter_types: [],
    last_updated: timestamp,
  };

  // Agregar ICD codes
  if (newClinicalMetadata.icd_codes && Array.isArray(newClinicalMetadata.icd_codes)) {
    for (const icd of newClinicalMetadata.icd_codes) {
      const existing = summary.all_icd_codes.find((i) => i.code === icd.code);
      if (existing) {
        existing.last_mentioned = timestamp;
        existing.occurrences += 1;
        if (!existing.certainty_history.includes(icd.certainty)) {
          existing.certainty_history.push(icd.certainty);
        }
      } else {
        summary.all_icd_codes.push({
          code: icd.code,
          description: icd.description,
          first_mentioned: timestamp,
          last_mentioned: timestamp,
          occurrences: 1,
          certainty_history: [icd.certainty],
        });
      }
    }
  }

  // Agregar medicações
  if (newClinicalMetadata.medications_mentioned && Array.isArray(newClinicalMetadata.medications_mentioned)) {
    for (const med of newClinicalMetadata.medications_mentioned) {
      const existing = summary.all_medications.find((m) => m.name.toLowerCase() === med.name.toLowerCase());
      if (existing) {
        existing.last_mentioned = timestamp;
        if (!existing.contexts.includes(med.context)) {
          existing.contexts.push(med.context);
        }
        if (med.dosage && (!existing.dosages_mentioned || !existing.dosages_mentioned.includes(med.dosage))) {
          existing.dosages_mentioned = existing.dosages_mentioned || [];
          existing.dosages_mentioned.push(med.dosage);
        }
      } else {
        summary.all_medications.push({
          name: med.name,
          first_mentioned: timestamp,
          last_mentioned: timestamp,
          contexts: [med.context],
          dosages_mentioned: med.dosage ? [med.dosage] : undefined,
        });
      }
    }
  }

  // Agregar tópicos
  if (newClinicalMetadata.topicos_principais && Array.isArray(newClinicalMetadata.topicos_principais)) {
    for (const topic of newClinicalMetadata.topicos_principais) {
      const existing = summary.common_topics.find((t) => t.topic === topic);
      if (existing) {
        existing.frequency += 1;
      } else {
        summary.common_topics.push({
          topic,
          frequency: 1,
        });
      }
    }
    // Ordenar por frequência
    summary.common_topics.sort((a, b) => b.frequency - a.frequency);
  }

  // Agregar tipos de encontro
  if (newClinicalMetadata.clinical_context?.encounter_type) {
    const encounterType = newClinicalMetadata.clinical_context.encounter_type;
    const existing = summary.encounter_types.find((e) => e.type === encounterType);
    if (existing) {
      existing.count += 1;
    } else {
      summary.encounter_types.push({
        type: encounterType,
        count: 1,
      });
    }
  }

  summary.last_updated = timestamp;
  return summary;
}

/**
 * Atualiza patient.json com nova sessão e metadados clínicos
 */
export function registerSession(
  metadataPath: string,
  patientID: string,
  patientName: string,
  profissional: ProfessionalInfo,
  sessao: SessionInfo,
  sessionEntry: SessionEntry,
  clinicalMetadata?: any
): void {
  let metadata = loadPatientMetadata(metadataPath);

  if (!metadata) {
    // Cria novo metadata
    metadata = {
      patient_id: patientID,
      patient_name: patientName,
      _profissional: profissional,
      _sessao: sessao,
      sessions: [],
    };
  } else {
    // Atualiza metadata existente
    metadata.patient_name = patientName;
    metadata._profissional = profissional;
    metadata._sessao = sessao;
  }

  // Remove sessão duplicada se existir
  metadata.sessions = metadata.sessions.filter(
    (s) => s.source_slug !== sessionEntry.source_slug
  );

  // Adiciona nova sessão
  metadata.sessions.push(sessionEntry);

  // Atualiza clinical summary se metadados clínicos fornecidos
  if (clinicalMetadata) {
    const previousSummary = metadata.clinical_summary;
    metadata.clinical_summary = updateClinicalSummary(
      metadata.clinical_summary,
      clinicalMetadata,
      sessionEntry.processed_at
    );

    // Log de agregação
    const icdAdded = (metadata.clinical_summary.all_icd_codes.length || 0) - (previousSummary?.all_icd_codes.length || 0);
    const medAdded = (metadata.clinical_summary.all_medications.length || 0) - (previousSummary?.all_medications.length || 0);

    if (icdAdded > 0 || medAdded > 0) {
      console.log(`   📊 Clinical Summary agregado:`);
      if (icdAdded > 0) console.log(`      • ${icdAdded} novo(s) ICD code(s)`);
      if (medAdded > 0) console.log(`      • ${medAdded} nova(s) medicação(ões)`);
      console.log(`      • Total: ${metadata.clinical_summary.all_icd_codes.length} ICD(s), ${metadata.clinical_summary.all_medications.length} medicação(ões)`);
    }
  }

  savePatientMetadata(metadataPath, metadata);
}
