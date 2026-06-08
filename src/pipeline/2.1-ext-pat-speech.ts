#!/usr/bin/env node
/**
 * HealthOS Patient Speech Extractor
 *
 * Script independente para extrair apenas as falas do paciente
 * de transcrições já processadas.
 *
 * Input: patients/<patient>/sessions/<session>/source/transcription.json
 * Output: patients/<patient>/sessions/<session>/analysis/patient-speech.*
 *
 * Estratégia de identificação:
 * 1. Usa Claude (Haiku) para identificar qual Falante é o paciente
 * 2. Filtra apenas as falas desse falante
 * 3. Gera arquivo de texto limpo com apenas o discurso do paciente
 */

import {
  readFileSync,
  writeFileSync,
  readdirSync,
  existsSync,
  mkdirSync,
  statSync,
} from "fs";
import { join, basename, dirname } from "path";
import { createInterface } from "readline";
import { config } from "dotenv";
import { PATHS } from "../config/defaults.js";
import { callLLM } from "../lib/llm/runtime.js";
import {
  listPatientIds,
  listPatientSessionWorkspaces,
  refreshPatientSessionStatus,
  type PatientSessionWorkspace,
} from "../patients/workspace.js";

config({ path: PATHS.ENV, override: false });

const PAT_DIR = PATHS.PAT;

interface TranscriptionData {
  source_file: string;
  processed_at: string;
  transcription_original: string;
  transcription_corrected: string;
  correction_applied: boolean;
  metadata?: {
    patient_name: string;
    professional_name: string;
  };
}

interface SpeakerIdentification {
  patient_speaker: string; // "Falante 1" ou "Falante 2" etc
  confidence: "high" | "medium" | "low";
  reasoning: string;
}

/**
 * Identifica qual falante é o paciente usando Claude
 */
async function identifyPatientSpeaker(
  transcriptionSample: string,
  patientName?: string
): Promise<SpeakerIdentification> {
  console.log("   🔍 Identificando qual falante é o paciente...");

  const system = `You are a clinical dialogue analyst. Your task is to identify which speaker in a transcription is the patient.

IDENTIFICATION RULES:
1. The PROFESSIONAL (doctor/therapist) typically:
   - Asks questions about symptoms, history, feelings
   - Gives medical advice or prescriptions
   - Uses clinical terminology
   - Directs the conversation
   - May mention they are the doctor/therapist

2. The PATIENT typically:
   - Answers questions about themselves
   - Describes symptoms, feelings, experiences
   - Talks about their life, family, work
   - Uses personal language ("eu", "meu", "minha")
   - May be more hesitant or emotional

3. Look for explicit identifiers:
   - "Eu sou o doutor/médico/psicólogo" = PROFESSIONAL
   - Patient name mentioned when addressing them = that speaker is PATIENT

OUTPUT: JSON with patient_speaker, confidence, and reasoning.`;

  const prompt = `<transcription_sample>
${transcriptionSample.substring(0, 4000)}
</transcription_sample>

${patientName ? `<patient_name_from_metadata>${patientName}</patient_name_from_metadata>` : ""}

TASK: Identify which speaker label (e.g., "Falante 1", "Falante 2") corresponds to the PATIENT.

Analyze the dialogue patterns and identify the patient.

JSON SCHEMA:
{
  "patient_speaker": "Falante N",
  "confidence": "high | medium | low",
  "reasoning": "Brief explanation of how you identified the patient"
}

Return ONLY the JSON object:`;

  try {
    const content = await callLLM({
      temperature: 0.1,
      systemPrompt: system,
      userPrompt: prompt,
    });
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      throw new Error("No JSON in response");
    }

    const result = JSON.parse(jsonMatch[0]) as SpeakerIdentification;
    console.log(`   ✅ Paciente identificado: ${result.patient_speaker} (${result.confidence})`);
    return result;
  } catch (error) {
    console.warn("   ⚠️ Erro na identificação, usando heurística padrão (Falante 2)");
    return {
      patient_speaker: "Falante 2",
      confidence: "low",
      reasoning: "Fallback: assuming Falante 2 is patient (most common pattern)",
    };
  }
}

/**
 * Extrai falas de um falante específico
 */
function extractSpeakerLines(text: string, speakerLabel: string): string {
  const lines: string[] = [];

  // Regex para encontrar blocos de fala: [Falante N] texto...
  // Captura tudo até o próximo [Falante ou fim do texto
  const regex = new RegExp(
    `\\[${speakerLabel}\\]\\s*([\\s\\S]*?)(?=\\[Falante \\d+\\]|$)`,
    "gi"
  );

  let match;
  while ((match = regex.exec(text)) !== null) {
    const speechContent = match[1].trim();
    if (speechContent) {
      lines.push(speechContent);
    }
  }

  return lines.join("\n\n");
}

/**
 * Conta quantos falantes existem na transcrição
 */
function countSpeakers(text: string): string[] {
  const speakers = new Set<string>();
  const regex = /\[Falante (\d+)\]/gi;
  let match;
  while ((match = regex.exec(text)) !== null) {
    speakers.add(`Falante ${match[1]}`);
  }
  return Array.from(speakers).sort();
}

/**
 * Processa um arquivo de transcrição
 */
async function processTranscription(
  transcriptionPath: string,
  session: PatientSessionWorkspace,
  useAI: boolean = true
): Promise<{ success: boolean; outputPath?: string; error?: string }> {
  const filename = basename(transcriptionPath);

  try {
    // Ler transcrição
    const data: TranscriptionData = JSON.parse(
      readFileSync(transcriptionPath, "utf-8")
    );

    // Usar texto corrigido se disponível, senão original
    const text = data.transcription_corrected || data.transcription_original;

    if (!text) {
      return { success: false, error: "Transcrição vazia" };
    }

    // Verificar falantes
    const speakers = countSpeakers(text);
    if (speakers.length === 0) {
      return { success: false, error: "Nenhum falante identificado no formato [Falante N]" };
    }

    console.log(`   📝 Falantes encontrados: ${speakers.join(", ")}`);

    // Identificar paciente
    let patientSpeaker: string;

    if (speakers.length === 1) {
      // Se só tem um falante, é ele
      patientSpeaker = speakers[0];
      console.log(`   ℹ️ Apenas um falante, usando: ${patientSpeaker}`);
    } else if (useAI) {
      // Usar Claude para identificar
      const identification = await identifyPatientSpeaker(
        text,
        data.metadata?.patient_name
      );
      patientSpeaker = identification.patient_speaker;
    } else {
      // Heurística: geralmente Falante 2 é o paciente
      patientSpeaker = speakers.includes("Falante 2") ? "Falante 2" : speakers[0];
      console.log(`   ℹ️ Usando heurística: ${patientSpeaker}`);
    }

    // Extrair falas do paciente
    const patientSpeech = extractSpeakerLines(text, patientSpeaker);

    if (!patientSpeech) {
      return { success: false, error: `Nenhuma fala encontrada para ${patientSpeaker}` };
    }

    if (!existsSync(session.analysisDir)) {
      mkdirSync(session.analysisDir, { recursive: true });
    }

    const outputPath = session.patientSpeechTextPath;

    // Salvar
    const header = `# Falas do Paciente
# Fonte: ${data.source_file}
# Processado: ${new Date().toISOString()}
# Falante identificado: ${patientSpeaker}
# Paciente: ${data.metadata?.patient_name || "N/A"}

---

`;

    writeFileSync(outputPath, header + patientSpeech, "utf-8");

    // Também salvar versão JSON com metadados
    const jsonOutput = {
      source_file: data.source_file,
      extracted_at: new Date().toISOString(),
      patient_speaker: patientSpeaker,
      patient_name: data.metadata?.patient_name || null,
      total_speakers: speakers.length,
      speakers_found: speakers,
      patient_speech: patientSpeech,
      word_count: patientSpeech.split(/\s+/).length,
      char_count: patientSpeech.length,
    };

    const jsonOutputPath = outputPath.replace(".txt", ".json");
    writeFileSync(jsonOutputPath, JSON.stringify(jsonOutput, null, 2), "utf-8");
    refreshPatientSessionStatus(session.patientId, session.id);

    return { success: true, outputPath };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

/**
 * Lista todos os pacientes disponíveis
 */
function listPatients(): string[] {
  return listPatientIds();
}

/**
 * Lista transcrições de um paciente
 */
function listSessionsWithTranscription(patientId: string): PatientSessionWorkspace[] {
  return listPatientSessionWorkspaces(patientId).filter((session) => existsSync(session.transcriptionPath));
}

/**
 * Main
 */
async function main() {
  console.log("\n" + "=".repeat(80));
  console.log("🗣️  HEALTHOS - Extrator de Falas do Paciente");
  console.log("=".repeat(80));

  // Listar pacientes
  const patients = listPatients();

  if (patients.length === 0) {
    console.log("\n⚠️ Nenhum paciente encontrado em patients/");
    return;
  }

  console.log(`\n📋 Encontrados ${patients.length} paciente(s)`);

  // Interface interativa
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const ask = (question: string): Promise<string> => {
    return new Promise((resolve) => {
      rl.question(question, (answer) => resolve(answer.trim()));
    });
  };

  // Mostrar opções
  console.log("\n🎯 Opções:");
  console.log("   1. Processar TODOS os pacientes");
  console.log("   2. Selecionar paciente específico");
  console.log("   3. Sair");

  const mainChoice = await ask("\n→ Escolha (1-3): ");

  if (mainChoice === "3") {
    console.log("\n❌ Operação cancelada.\n");
    rl.close();
    return;
  }

  // Perguntar sobre uso de IA
  const useAIChoice = await ask("\n🤖 Usar IA para identificar paciente? (S/n): ");
  const useAI = useAIChoice.toLowerCase() !== "n";
  console.log(useAI ? "   ✅ Usando runtime LLM para identificação" : "   ℹ️ Usando heurística (Falante 2)");

  let patientsToProcess: string[] = [];

  if (mainChoice === "1") {
    patientsToProcess = patients;
  } else if (mainChoice === "2") {
    // Listar pacientes para seleção
    console.log("\n📋 Pacientes disponíveis:");
    patients.forEach((p, idx) => {
      console.log(`   ${idx + 1}. ${p}`);
    });

    const patientChoice = await ask(`\n→ Número do paciente (1-${patients.length}): `);
    const idx = parseInt(patientChoice, 10) - 1;

    if (isNaN(idx) || idx < 0 || idx >= patients.length) {
      console.log("\n⚠️ Opção inválida.");
      rl.close();
      return;
    }

    patientsToProcess = [patients[idx]];
  }

  // Processar
  console.log(`\n🚀 Processando ${patientsToProcess.length} paciente(s)...\n`);

  let totalProcessed = 0;
  let totalSuccess = 0;
  let totalError = 0;

  for (const patient of patientsToProcess) {
    const sessions = listSessionsWithTranscription(patient);

    if (sessions.length === 0) {
      console.log(`\n⚠️ ${patient}: Nenhuma transcrição encontrada`);
      continue;
    }

    console.log(`\n${"─".repeat(60)}`);
    console.log(`👤 ${patient}`);
    console.log(`${"─".repeat(60)}`);
    console.log(`   📄 ${sessions.length} sessão(ões) com transcrição`);

    for (const session of sessions) {
      console.log(`\n   📝 ${session.id}/source/transcription.json`);

      const result = await processTranscription(session.transcriptionPath, session, useAI);
      totalProcessed++;

      if (result.success) {
        console.log(`   ✅ Salvo: ${basename(result.outputPath!)}`);
        totalSuccess++;
      } else {
        console.log(`   ❌ Erro: ${result.error}`);
        totalError++;
      }
    }
  }

  rl.close();

  // Resumo
  console.log("\n" + "=".repeat(80));
  console.log("📊 RESUMO");
  console.log("=".repeat(80));
  console.log(`   Total processado: ${totalProcessed}`);
  console.log(`   ✅ Sucesso: ${totalSuccess}`);
  console.log(`   ❌ Erros: ${totalError}`);
  console.log(`\n📁 Saída: patients/<paciente>/sessions/<sessao>/analysis/patient-speech.*\n`);
}

main().catch((error) => {
  console.error("\n❌ Erro fatal:", error);
  process.exit(1);
});
