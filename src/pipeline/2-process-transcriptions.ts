#!/usr/bin/env node
/**
 * HealthOS Transcription Processor
 *
 * DECLARATIVE PIPELINE - Toda lógica de processamento delegada ao LLM
 *
 * Input: audio/transcriptions/*.json (transcrições já processadas)
 * Output: patients/PAT_000001/ com estrutura completa
 *
 * Etapas:
 * 1. Leitura de transcrições existentes
 * 2. LLM extrai metadados + identifica profissional/paciente (DECLARATIVO)
 * 3. Confirmação interativa do usuário
 * 4. LLM verifica/corrige transcrição (DECLARATIVO)
 * 5. Criação de estrutura de dossiê
 * 6. Salvamento de transcrição processada + session.json + patient.json
 *
 * LLM: runtime selecionado em HEALTHOS_LLM_RUNTIME ou no menu HealthOS
 * Otimização: Prompt caching ativado
 */

import {
  readFileSync,
  writeFileSync,
  readdirSync,
  existsSync,
  mkdirSync,
} from "fs";
import { join, basename } from "path";
import { createInterface } from "readline";
import { config } from "dotenv";
import { PATHS } from "../config/defaults.js";
import { callLLM, getSelectedRuntime } from "../lib/llm/runtime.js";
import { extractJSON } from "../lib/llm/json.js";
import { estimateTokens, splitIntoChunks } from "../lib/llm/chunking.js";
import { loadProfessionalConfig, type ProfessionalConfig } from "./1-professional-config.js";
import {
  createPatientScaffold,
  buildSessionArtifacts,
  ensurePatientSessionWorkspace,
  findPatientByName,
  getPatientSessionWorkspace,
  getPatientsRoot,
  listPatientWorkspaces,
  loadPatientProfile,
  ensurePatientWorkspace,
  makeSessionId,
  sessionStatus,
  upsertPatientSession,
  type PatientWorkspace,
} from "../patients/workspace.js";

config({ path: PATHS.ENV, override: false });

const TRANSCRIPTIONS_DIR = PATHS.TRANSCRIPTIONS;
const PATIENTS_DIR = getPatientsRoot();

interface ExtractedMetadata {
  patient_name: string;
  patient_initials: string | null;
  professional_name: string;
  tags: string[];
  confidence: "high" | "medium" | "low";
  needs_correction: boolean;
  correction_notes?: string;
}

interface CorrectedTranscription {
  original_had_errors: boolean;
  corrections_made: string[];
  corrected_text: string;
}

/**
 * DECLARATIVE: Claude extrai todos os metadados da transcrição
 */
async function extractMetadata(
  transcriptionText: string,
  filename: string,
  professionalConfig: ProfessionalConfig | null
): Promise<ExtractedMetadata> {
  console.log(`   🔍 Extraindo metadados (${getSelectedRuntime()} + Prompt Caching)...`);

  const professionalContext = professionalConfig
    ? `\n\nPROFESSIONAL CONTEXT (from active professional workspace):
- Nome: ${professionalConfig.nome}
${professionalConfig.registro ? `- Registro: ${professionalConfig.registro}` : ""}
${professionalConfig.disambiguation_context ? `- Contexto de desambiguação: ${professionalConfig.disambiguation_context}` : ""}

Use this information to identify the professional in the transcription.`
    : "";

  const system = `You are a clinical metadata extraction specialist. Your role is to analyze clinical transcriptions and extract essential metadata in a structured format.

TASK: Extract basic metadata from transcriptions following these principles:

EXTRACTION PRINCIPLES:
1. EXPLICIT ONLY: Extract only information explicitly stated in the transcription
2. IDENTITY DETECTION: Identify patient and professional names/initials
3. TAGGING: Create general searchable tags
4. QUALITY ASSESSMENT: Evaluate if transcription needs correction
5. STRUCTURED OUTPUT: Return JSON with all required fields${professionalContext}

METADATA TO EXTRACT:
- patient_name: Full name if mentioned in transcription OR in filename, or "Paciente" if not stated
- patient_initials: Patient initials (e.g., "JS" for João Silva), null if not mentioned
- professional_name: Therapist/doctor name (use config if available)
- tags: Array of general searchable tags (e.g., ["psicoterapia", "primeira_consulta", "ansiedade"])
- confidence: How confident you are in the extraction (high/medium/low)
- needs_correction: Boolean - does transcription have errors to fix?
- correction_notes: If needs_correction=true, note what needs fixing

IMPORTANT: The filename may contain the patient name and session date. Analyze the filename pattern to extract patient information if available.

TAGGING GUIDELINES:
- Keep tags general and broad (avoid overly specific details)
- Use professional terminology when applicable
- Include clinical domain tags (e.g., "psicologia", "psiquiatria")
- Limit to 3-8 relevant tags

QUALITY INDICATORS FOR needs_correction:
- Obvious STT errors (homophones, misrecognitions)
- Missing punctuation affecting clinical meaning
- Inconsistent speaker labels
- Medical terminology errors
- Incomplete sentences that affect understanding

OUTPUT FORMAT: Valid JSON matching the schema exactly.`;

  const prompt = `<source_filename>
${filename}
</source_filename>

<clinical_transcription>
${transcriptionText}
</clinical_transcription>

TASK: Extract basic metadata from the transcription above.

STEP-BY-STEP EXTRACTION:
1. Identify patient name/initials (check BOTH filename and transcription content)
2. Identify professional name (look for therapist/doctor identification, use config if available)
3. Generate general searchable tags (3-8 tags)
4. Assess transcription quality and identify if corrections are needed

EXAMPLES:

Example 1 - Patient name in transcription:
Filename: "audio_001.json"
Text: "[Falante 1] Olá, João Silva, como você está hoje?"
Extract: {"patient_name": "João Silva", "patient_initials": "JS"}

Example 2 - Patient name in filename:
Filename: "2025-10-20_maria_santos_consulta.json"
Text: "[Falante 1] Como você está se sentindo?"
Extract: {"patient_name": "Maria Santos", "patient_initials": "MS"}

Example 3 - No patient name anywhere:
Filename: "recording_001.json"
Text: "[Falante 1] Como você está se sentindo?"
Extract: {"patient_name": "Paciente", "patient_initials": null}

Example 4 - Tags:
Text: "Primeira consulta, paciente relata ansiedade e dificuldade para dormir"
Extract: {"tags": ["primeira_consulta", "ansiedade", "insonia", "psicoterapia"]}

Example 5 - Needs correction:
Text: "o paciente tem hiper tensão e toma aspirin"
Extract: {"needs_correction": true, "correction_notes": "Medical terms need standardization: 'hiper tensão' → 'hipertensão', 'aspirin' → 'aspirina'"}

JSON SCHEMA:
{
  "patient_name": "string",
  "patient_initials": "string | null",
  "professional_name": "string",
  "tags": ["string"],
  "confidence": "high | medium | low",
  "needs_correction": "boolean",
  "correction_notes": "string (optional)"
}

Return ONLY the JSON object (no markdown, no explanations):`;

  try {
    const response = await callLLMWithRetry(prompt, system, true);
    const metadata = extractJSON(response) as ExtractedMetadata;

    console.log(`   ✅ Metadados extraídos (confiança: ${metadata.confidence})`);
    console.log(`      • Paciente: ${metadata.patient_name}`);
    console.log(`      • Profissional: ${metadata.professional_name}`);
    console.log(`      • Tags: ${metadata.tags.length}`);
    console.log(`      • Correção necessária: ${metadata.needs_correction ? "Sim" : "Não"}`);

    return metadata;
  } catch (error) {
    console.error("   ❌ Erro ao extrair metadados:", error);
    throw error;
  }
}

/**
 * DECLARATIVE: LLM corrige/normaliza a transcrição se necessário
 */
async function correctTranscription(transcriptionText: string, correctionNotes?: string): Promise<CorrectedTranscription> {
  console.log(`   ✨ Verificando necessidade de correções (${getSelectedRuntime()})...`);

  const system = `You are a medical transcriptionist specialized in clinical documentation standards.

TASK: Review and correct transcriptions if needed, following AHDI BOSS4CD guidelines.

CORRECTION PRINCIPLES:
1. FIX ONLY ERRORS: Don't change clinical content or meaning
2. STANDARDIZATION: Apply medical terminology standards
3. CLARITY: Fix punctuation for clinical clarity
4. SPEAKER LABELS: Preserve [Falante N] markers exactly
5. PARALINGUISTICS: PRESERVE all paralinguistic markers (risadas, pigarro, pausa, suspiros, etc.)
6. TRANSPARENCY: Document all corrections made

WHAT TO CORRECT:
- Homophones and STT misrecognitions
- Medical terminology errors (especially medication names)
- Punctuation issues affecting meaning
- Inconsistent abbreviations
- Capitalization errors

WHAT TO PRESERVE:
- Clinical content and facts
- Speaker sequence and labels
- Chronological order
- Patient statements verbatim (fix only STT errors)
- ALL paralinguistic markers: (risadas), (risos), (pigarro), (pausa), (suspiro), (choro), etc.
- Emotional and communicative context indicators

CRITICAL: Paralinguistic markers are clinically valuable. They provide context about patient affect, hesitation, emotional state, and communication patterns. NEVER remove them.

OUTPUT FORMAT: JSON with corrections analysis and corrected text.`;

  const correctionContext = correctionNotes
    ? `\n\nCORRECTION GUIDANCE:\n${correctionNotes}\n\nFocus on these identified issues.`
    : "";

  const prompt = `<transcription>
${transcriptionText}
</transcription>${correctionContext}

TASK: Analyze if corrections are needed and apply them if necessary.

STEP-BY-STEP PROCESS:
1. Scan for STT errors (homophones, misrecognitions)
2. Check medical terminology accuracy
3. Verify punctuation and clarity
4. Identify needed corrections
5. Apply corrections preserving clinical meaning
6. Document all changes made

EXAMPLES OF CORRECTIONS:

Example 1 - Medical terminology:
Original: "o paciente tem hiper tensão"
Corrected: "o paciente tem hipertensão"
Reason: "Medical term standardization"

Example 2 - Medication names:
Original: "toma aspirin 100mg"
Corrected: "toma aspirina 100 mg"
Reason: "Portuguese medication name + spacing"

Example 3 - PRESERVE paralinguistics:
Original: "Acho que melhorou (risadas). Mas ainda tenho dor (pigarro)."
Corrected: "Acho que melhorou (risadas). Mas ainda tenho dor (pigarro)."
Reason: "No errors detected - paralinguistics PRESERVED"

Example 4 - Fix error BUT keep paralinguistics:
Original: "Ele toma Haldol todo dia (risos). Faz dois mêses."
Corrected: "Ele toma Haldol todo dia (risos). Faz dois meses."
Reason: "Fixed 'mêses' → 'meses', PRESERVED (risos)"

Example 5 - No corrections needed:
Original: "O paciente relatou melhora dos sintomas."
Corrected: "O paciente relatou melhora dos sintomas."
Reason: "No errors detected"

JSON SCHEMA:
{
  "original_had_errors": "boolean",
  "corrections_made": ["array of strings describing each correction"],
  "corrected_text": "string (full corrected transcription)"
}

Return ONLY the JSON object (no markdown, no explanations):`;

  try {
    // Estima tokens e decide se precisa chunkear
    const estimatedTokens = estimateTokens(transcriptionText);
    const TOKEN_BUDGET_PER_CHUNK = 15000; // Margem operacional para separar entradas longas

    if (estimatedTokens > TOKEN_BUDGET_PER_CHUNK) {
      console.log(`   📊 Transcrição grande (~${estimatedTokens.toLocaleString()} tokens) - processando em chunks...`);

      // Divide em chunks
      const chunks = splitIntoChunks(transcriptionText, TOKEN_BUDGET_PER_CHUNK);
      console.log(`   🔀 Dividido em ${chunks.length} chunks`);

      // Processa chunks em paralelo (máximo 10 por vez)
      const BATCH_SIZE = 10;
      const correctedChunks: string[] = new Array(chunks.length);
      const allCorrections: string[] = [];
      let hadErrors = false;

      console.log(`   ⚡ Processando ${chunks.length} chunks em paralelo (batches de ${BATCH_SIZE})...`);

      for (let batchStart = 0; batchStart < chunks.length; batchStart += BATCH_SIZE) {
        const batchEnd = Math.min(batchStart + BATCH_SIZE, chunks.length);
        const batchSize = batchEnd - batchStart;

        console.log(`   🚀 Batch ${Math.floor(batchStart / BATCH_SIZE) + 1}: processando chunks ${batchStart + 1}-${batchEnd}...`);

        // Cria promises para processar em paralelo
        const batchPromises = [];

        for (let i = batchStart; i < batchEnd; i++) {
          const chunkIndex = i;
          const chunkPrompt = `<transcription>
${chunks[chunkIndex]}
</transcription>${correctionContext}

TASK: Analyze if corrections are needed and apply them if necessary.
This is chunk ${chunkIndex + 1} of ${chunks.length} from a larger transcription.

STEP-BY-STEP PROCESS:
1. Scan for STT errors (homophones, misrecognitions)
2. Check medical terminology accuracy
3. Verify punctuation and clarity
4. Identify needed corrections
5. Apply corrections preserving clinical meaning
6. Document all changes made

EXAMPLES OF CORRECTIONS:

Example 1 - Medical terminology:
Original: "o paciente tem hiper tensão"
Corrected: "o paciente tem hipertensão"
Reason: "Medical term standardization"

Example 2 - Medication names:
Original: "toma aspirin 100mg"
Corrected: "toma aspirina 100 mg"
Reason: "Portuguese medication name + spacing"

Example 3 - PRESERVE paralinguistics:
Original: "Acho que melhorou (risadas). Mas ainda tenho dor (pigarro)."
Corrected: "Acho que melhorou (risadas). Mas ainda tenho dor (pigarro)."
Reason: "No errors detected - paralinguistics PRESERVED"

Example 4 - Fix error BUT keep paralinguistics:
Original: "Ele toma Haldol todo dia (risos). Faz dois mêses."
Corrected: "Ele toma Haldol todo dia (risos). Faz dois meses."
Reason: "Fixed 'mêses' → 'meses', PRESERVED (risos)"

JSON SCHEMA:
{
  "original_had_errors": "boolean",
  "corrections_made": ["array of strings describing each correction"],
  "corrected_text": "string (full corrected transcription)"
}

Return ONLY the JSON object (no markdown, no explanations):`;

          const promise = callLLMWithRetry(chunkPrompt, system, true)
            .then(response => {
              const chunkResult = extractJSON(response) as CorrectedTranscription;
              return { index: chunkIndex, result: chunkResult, error: null };
            })
            .catch(error => {
              console.log(`   ⚠️ Erro no chunk ${chunkIndex + 1}, usando texto original`);
              return {
                index: chunkIndex,
                result: {
                  original_had_errors: false,
                  corrections_made: [],
                  corrected_text: chunks[chunkIndex]
                },
                error: error.message
              };
            });

          batchPromises.push(promise);
        }

        // Aguarda todos os chunks do batch serem processados
        const batchResults = await Promise.all(batchPromises);

        // Armazena resultados na ordem correta
        for (const { index, result } of batchResults) {
          correctedChunks[index] = result.corrected_text;

          if (result.original_had_errors) {
            hadErrors = true;
            allCorrections.push(`Chunk ${index + 1}: ${result.corrections_made.join(", ")}`);
          }
        }

        console.log(`   ✅ Batch concluído (${batchSize} chunks processados)`);
      }

      // Consolida resultados
      const finalText = correctedChunks.join("\n\n");

      if (hadErrors) {
        console.log(`   ✅ Correções aplicadas em ${allCorrections.length} chunk(s)`);
        allCorrections.forEach(correction => {
          console.log(`      • ${correction}`);
        });
      } else {
        console.log(`   ✅ Nenhuma correção necessária em nenhum chunk`);
      }

      return {
        original_had_errors: hadErrors,
        corrections_made: allCorrections,
        corrected_text: finalText
      };

    } else {
      // Processa normalmente se couber em uma única requisição
      const response = await callLLMWithRetry(prompt, system, true);
      const result = extractJSON(response) as CorrectedTranscription;

      if (result.original_had_errors) {
        console.log(`   ✅ Correções aplicadas: ${result.corrections_made.length}`);
        result.corrections_made.forEach(correction => {
          console.log(`      • ${correction}`);
        });
      } else {
        console.log(`   ✅ Nenhuma correção necessária`);
      }

      return result;
    }
  } catch (error) {
    console.error("   ❌ Erro ao corrigir transcrição:", error);
    // Fallback: retorna original sem correções
    return {
      original_had_errors: false,
      corrections_made: [],
      corrected_text: transcriptionText
    };
  }
}

/**
 * Chamada LLM com retry
 * Usa o runtime LLM selecionado para a sessão.
 */
async function callLLMWithRetry(
  prompt: string,
  system: string,
  useCache: boolean = true,
  retries: number = 3
): Promise<string> {
  console.log(`      • Cache: ${useCache ? "✅ Enabled (via Gateway)" : "❌ Disabled"}`);
  console.log(`      • Runtime: ${getSelectedRuntime()}`);

  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const content = await callLLM({
        temperature: 0.2,
        systemPrompt: system,
        userPrompt: prompt,
      });
      if (content) {
        return content;
      }

      throw new Error("Resposta inválida do LLM");
    } catch (error: any) {
      const status = error?.status ?? error?.response?.status;

      if (attempt === retries) throw error;
      console.log(`   ⚠️ Tentativa ${attempt} falhou, retry em ${attempt * 2}s...`);
      await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
    }
  }

  throw new Error("Max retries reached");
}

/**
 * Extrai apenas as falas do paciente da transcrição
 * Usa Claude para identificar qual falante é o paciente e extrair suas falas
 */
async function extractPatientSpeech(
  transcriptionText: string,
  patientName: string,
  professionalName: string
): Promise<{ patient_speech: string; speaker_label: string; word_count: number } | null> {
  console.log("   🗣️  Extraindo falas do paciente...");

  const system = `You are a clinical dialogue analyst. Extract ONLY the patient's speech from transcriptions.

TASK: Identify which speaker is the patient and extract ALL their speech.

IDENTIFICATION RULES:
1. The PROFESSIONAL (doctor/therapist):
   - Asks questions about symptoms, feelings, history
   - Gives medical advice, prescriptions
   - Directs the conversation
   - May say "Eu sou o doutor/médico"

2. The PATIENT:
   - Answers questions about themselves
   - Describes symptoms, feelings, experiences
   - Talks about their life, family, work
   - Is the focus of clinical attention

SPEAKER FORMATS TO DETECT (examples):
- [Falante 1], [Falante 2]
- [Speaker 1], [Speaker 2]
- [SPEAKER_00], [SPEAKER_01]
- Speaker A:, Speaker B:
- Médico:, Paciente:
- Any similar pattern

OUTPUT: Return JSON with the patient's speech concatenated (preserving paragraph breaks between turns).`;

  const prompt = `<transcription>
${transcriptionText.substring(0, 15000)}
</transcription>

<context>
Patient name: ${patientName}
Professional name: ${professionalName}
</context>

TASK:
1. Detect the speaker label format used in this transcription
2. Identify which speaker is the patient
3. Extract ALL patient speech, concatenated with paragraph breaks

JSON SCHEMA:
{
  "speaker_format_detected": "description of format found",
  "patient_speaker_label": "the label identifying the patient",
  "patient_speech": "all patient speech concatenated with \\n\\n between turns",
  "confidence": "high | medium | low"
}

Return ONLY the JSON:`;

  try {
    const response = await callLLMWithRetry(prompt, system, false);
    const result = extractJSON(response);

    if (!result.patient_speech || result.patient_speech.length < 10) {
      console.log("   ⚠️ Não foi possível extrair falas do paciente");
      return null;
    }

    const wordCount = result.patient_speech.split(/\s+/).length;
    console.log(`   ✅ Falas extraídas: ${wordCount} palavras (${result.patient_speaker_label})`);

    return {
      patient_speech: result.patient_speech,
      speaker_label: result.patient_speaker_label,
      word_count: wordCount,
    };
  } catch (error) {
    console.log("   ⚠️ Erro ao extrair falas do paciente:", error);
    return null;
  }
}

/**
 * Confirmação interativa com o usuário
 */
async function confirmMetadata(metadata: ExtractedMetadata, rl: any): Promise<boolean> {
  console.log("\n" + "─".repeat(80));
  console.log("📋 METADADOS EXTRAÍDOS - Por favor, confirme:");
  console.log("─".repeat(80));
  console.log(`Paciente: ${metadata.patient_name}`);
  if (metadata.patient_initials) {
    console.log(`Iniciais: ${metadata.patient_initials}`);
  }
  console.log(`Profissional: ${metadata.professional_name}`);
  console.log(`Tags: ${metadata.tags.join(", ")}`);
  console.log(`Confiança: ${metadata.confidence}`);
  console.log("─".repeat(80));

  const answer = await new Promise<string>((resolve) => {
    rl.question("\n✅ Confirmar estes dados? (S/n): ", resolve);
  });

  return answer.trim().toLowerCase() !== "n";
}

/**
 * Normaliza nome de paciente para comparação
 */
function normalizePatientName(name: string): string {
  return name
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // Remove acentos
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Verifica se um arquivo de transcrição já foi processado
 * Retorna o caminho do dossiê se encontrado, null caso contrário
 */
function findProcessedFile(sourceFilename: string): string | null {
  for (const workspace of listPatientWorkspaces()) {
    const profile = loadPatientProfile(workspace);
    const hasFile = profile?.sessions?.some((session) => session.source_file === sourceFilename);
    if (hasFile) return workspace.dir;
  }

  return null;
}

/**
 * Busca dossiê de paciente existente pelo nome
 * Retorna {patientDir, patientId} se encontrado, null caso contrário
 */
function findExistingPatient(patientName: string): { patientDir: string; patientId: string } | null {
  const canonical = findPatientByName(patientName);
  if (canonical) {
    const profile = loadPatientProfile(canonical);
    const name = profile?.identity?.full_name || profile?.patient_name || patientName;
    console.log(`   🔍 Paciente encontrado: ${name} (${canonical.id})`);
    return { patientDir: canonical.dir, patientId: canonical.id };
  }

  return null;
}

/**
 * Cria estrutura de dossiê do paciente
 */
function createPatientDossier(patientName: string): { patientDir: string; patientId: string } {
  const workspace = createPatientScaffold({
    patient_name: patientName,
    identity: {
      full_name: patientName,
      aliases: [patientName],
    },
    source: "transcription-processor",
  });

  console.log(`   📂 Dossiê criado: ${workspace.dir}`);

  return { patientDir: workspace.dir, patientId: workspace.id };
}

/**
 * Processa um arquivo de transcrição
 */
async function processTranscription(transcriptionPath: string, rl: any): Promise<void> {
  const filename = basename(transcriptionPath);

  console.log(`\n${"=".repeat(80)}`);
  console.log(`📄 ${filename}`);
  console.log(`${"=".repeat(80)}`);

  try {
    // 1. Verificar se já foi processado
    const existingDossier = findProcessedFile(filename);
    if (existingDossier) {
      console.log(`   ⚠️ Arquivo já processado no dossiê: ${basename(existingDossier)}`);

      const reprocess = await new Promise<string>((resolve) => {
        rl.question("   🔄 Reprocessar este arquivo? (s/N): ", resolve);
      });

      if (reprocess.trim().toLowerCase() !== "s") {
        console.log("   ⏭️ Pulando arquivo...");
        return;
      }

      console.log("   🔄 Reprocessando arquivo...");
    }

    // 2. Carregar transcrição
    let transcriptionText = "";
    if (filename.endsWith(".json")) {
      const transcriptionData = JSON.parse(readFileSync(transcriptionPath, "utf-8"));
      transcriptionText = transcriptionData.transcricao || transcriptionData.text || "";
    } else {
      transcriptionText = readFileSync(transcriptionPath, "utf-8");
    }

    if (!transcriptionText) {
      console.warn("   ⚠️ Transcrição vazia, pulando...");
      return;
    }

    console.log(`   📝 Texto: ${transcriptionText.length} caracteres`);

    // 2. Carregar config do profissional
    const professionalConfig = loadProfessionalConfig();

    // 3. DECLARATIVO: Claude extrai metadados
    const metadata = await extractMetadata(transcriptionText, filename, professionalConfig);

    // 4. Confirmação do usuário
    const confirmed = await confirmMetadata(metadata, rl);

    if (!confirmed) {
      console.log("\n❌ Processamento cancelado pelo usuário.\n");
      return;
    }

    // 5. DECLARATIVO: Claude corrige transcrição se necessário
    let finalTranscription = transcriptionText;
    let correctionResult: CorrectedTranscription | null = null;

    if (metadata.needs_correction) {
      correctionResult = await correctTranscription(transcriptionText, metadata.correction_notes);
      finalTranscription = correctionResult.corrected_text;
    } else {
      console.log("   ✅ Transcrição não necessita correções");
    }

    // 6. Buscar dossiê existente ou criar novo
    console.log("\n   📂 Verificando dossiê do paciente...");

    let patientDir: string;
    let patientId: string;
    let isNewPatient = false;

    const existingPatient = findExistingPatient(metadata.patient_name);

    if (existingPatient) {
      // Paciente já existe - usar dossiê existente
      patientDir = existingPatient.patientDir;
      patientId = existingPatient.patientId;
      console.log(`   ✅ Usando dossiê existente: ${patientId}`);
    } else {
      // Paciente novo - criar dossiê
      const newDossier = createPatientDossier(metadata.patient_name);
      patientDir = newDossier.patientDir;
      patientId = newDossier.patientId;
      isNewPatient = true;
      console.log(`   ✅ Dossiê novo criado: ${patientId}`);
    }

    // 7. Criar sessão e salvar transcrição processada
    const timestamp = new Date().toISOString().split("T")[0];
    const sessionId = makeSessionId(timestamp, filename);
    const sessionWorkspace = ensurePatientSessionWorkspace(getPatientSessionWorkspace(patientId, sessionId));
    const transcriptionSavePath = sessionWorkspace.transcriptionPath;

    const processedTranscription = {
      source_file: filename,
      processed_at: new Date().toISOString(),
      transcription_original: transcriptionText,
      transcription_corrected: finalTranscription,
      correction_applied: metadata.needs_correction,
      corrections: correctionResult?.corrections_made || [],
      metadata: metadata,
    };

    writeFileSync(transcriptionSavePath, JSON.stringify(processedTranscription, null, 2), "utf-8");
    console.log(`   💾 Transcrição salva: ${transcriptionSavePath}`);

    // 7.5 Extrair e salvar falas do paciente
    const patientSpeechResult = await extractPatientSpeech(
      finalTranscription,
      metadata.patient_name,
      metadata.professional_name
    );

    if (patientSpeechResult) {
      const header = `# Falas do Paciente: ${metadata.patient_name}
# Fonte: ${filename}
# Falante: ${patientSpeechResult.speaker_label}
# Palavras: ${patientSpeechResult.word_count}
# Extraído: ${new Date().toISOString()}

---

`;
      writeFileSync(sessionWorkspace.patientSpeechTextPath, header + patientSpeechResult.patient_speech, "utf-8");
      console.log(`   💾 Falas do paciente: ${sessionWorkspace.patientSpeechTextPath}`);

      writeFileSync(sessionWorkspace.patientSpeechJsonPath, JSON.stringify({
        source_file: filename,
        patient_name: metadata.patient_name,
        speaker_label: patientSpeechResult.speaker_label,
        word_count: patientSpeechResult.word_count,
        char_count: patientSpeechResult.patient_speech.length,
        extracted_at: new Date().toISOString(),
        patient_speech: patientSpeechResult.patient_speech,
      }, null, 2), "utf-8");
    }

    const artifacts = buildSessionArtifacts(sessionWorkspace);
    const sessionRecord = {
      session_id: sessionId,
      date: timestamp,
      source_file: filename,
      source_slug: filename.replace(/\.[^.]+$/, ""),
      tags: metadata.tags,
      path: `sessions/${sessionId}`,
      processed_at: new Date().toISOString(),
      status: sessionStatus(sessionWorkspace),
      artifacts: artifacts.map((artifact) => artifact.artifact_id),
      clinical_delta: {},
    };
    writeFileSync(sessionWorkspace.sessionPath, JSON.stringify(sessionRecord, null, 2), "utf-8");

    if (patientId.startsWith("PAT_") && patientDir.startsWith(PATIENTS_DIR)) {
      const workspace = createPatientWorkspaceFromDir(patientId, patientDir);
      const existingProfile = loadPatientProfile(workspace);
      ensurePatientWorkspace(workspace, {
        ...existingProfile,
        patient_name: metadata.patient_name,
        patient_initials: metadata.patient_initials,
        identity: {
          ...existingProfile?.identity,
          full_name: metadata.patient_name,
          initials: metadata.patient_initials,
          aliases: Array.from(new Set([...(existingProfile?.identity?.aliases || []), metadata.patient_name])),
        },
        care_team: {
          ...(existingProfile?.care_team || {}),
          primary_professional: {
            name: metadata.professional_name,
            ...professionalConfig,
          },
        },
        source: "transcription-processor",
      });
      upsertPatientSession(patientId, sessionRecord, artifacts);
      console.log(`   💾 patient.json e session.json atualizados`);
    }

    console.log(`\n✅ Processamento concluído para ${filename}`);

  } catch (error) {
    console.error(`\n❌ Erro ao processar ${filename}:`, error);
    throw error;
  }
}

function createPatientWorkspaceFromDir(patientId: string, patientDir: string): PatientWorkspace {
  return {
    id: patientId,
    dir: patientDir,
    profilePath: join(patientDir, "patient.json"),
    memoryPath: join(patientDir, "memory.md"),
    careAgentPath: join(patientDir, "care-agent.md"),
    agentsDir: join(patientDir, "agents"),
    sessionsDir: join(patientDir, "sessions"),
    artifactsDir: join(patientDir, "artifacts"),
    logsDir: join(patientDir, "logs"),
    telemetryDir: join(patientDir, "telemetry"),
  };
}

/**
 * Main
 */
async function main() {
  console.log("\n" + "=".repeat(80));
  console.log("🔄 HEALTHOS - Processador de Transcrições");
  console.log("=".repeat(80));

  // Verificar diretórios
  if (!existsSync(TRANSCRIPTIONS_DIR)) {
    console.log(`\n⚠️ Diretório de transcrições não encontrado: ${TRANSCRIPTIONS_DIR}`);
    return;
  }

  if (!existsSync(PATIENTS_DIR)) {
    mkdirSync(PATIENTS_DIR, { recursive: true });
    console.log(`📂 Pasta patients/ criada: ${PATIENTS_DIR}`);
  }

  // Listar transcrições disponíveis
  const transcriptionFiles = readdirSync(TRANSCRIPTIONS_DIR).filter(
    (file) => file.endsWith(".json") || file.endsWith(".txt") || file.endsWith(".md")
  );

  if (transcriptionFiles.length === 0) {
    console.log("\n⚠️ Nenhuma transcrição encontrada em audio/transcriptions/");
    return;
  }

  console.log(`\n📋 Encontradas ${transcriptionFiles.length} transcrição(ões):`);
  transcriptionFiles.forEach((file, idx) => {
    const processed = findProcessedFile(file);
    const status = processed ? "✅ (processado)" : "⬜ (novo)";
    console.log(`   ${idx + 1}. ${file} ${status}`);
  });

  // Interface interativa
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log(`\n🤖 Runtime LLM: ${getSelectedRuntime()}`);

  const ask = (question: string): Promise<string> => {
    return new Promise((resolve) => {
      rl.question(question, (answer) => resolve(answer.trim()));
    });
  };

  const choice = await ask(
    `\n🎯 Escolha uma opção:\n   • Digite o número do arquivo (1-${transcriptionFiles.length})\n   • Digite "todos" ou "t" para processar todos\n   • Digite "novos" ou "n" para processar apenas os novos\n   • Digite "sair" ou "s" para cancelar\n\n→ `
  );

  if (choice.toLowerCase() === "sair" || choice.toLowerCase() === "s") {
    console.log("\n❌ Operação cancelada.\n");
    rl.close();
    return;
  }

  let filesToProcess: string[] = [];

  if (choice.toLowerCase() === "todos" || choice.toLowerCase() === "t") {
    filesToProcess = transcriptionFiles;
    console.log(`\n🚀 Processando ${filesToProcess.length} arquivo(s)...\n`);
  } else if (choice.toLowerCase() === "novos" || choice.toLowerCase() === "n") {
    filesToProcess = transcriptionFiles.filter((file) => !findProcessedFile(file));

    if (filesToProcess.length === 0) {
      console.log("\n✅ Todos os arquivos já foram processados!\n");
      rl.close();
      return;
    }

    console.log(`\n🚀 Processando ${filesToProcess.length} arquivo(s) novo(s)...\n`);
  } else {
    const idx = parseInt(choice, 10);
    if (isNaN(idx) || idx < 1 || idx > transcriptionFiles.length) {
      console.log("\n⚠️ Opção inválida. Operação cancelada.\n");
      rl.close();
      return;
    }
    filesToProcess = [transcriptionFiles[idx - 1]];
    console.log(`\n🚀 Processando: ${filesToProcess[0]}...\n`);
  }

  // Processar arquivos
  for (let i = 0; i < filesToProcess.length; i++) {
    const file = filesToProcess[i];
    const filepath = join(TRANSCRIPTIONS_DIR, file);

    if (filesToProcess.length > 1) {
      console.log(`\n[${i + 1}/${filesToProcess.length}]`);
    }

    try {
      await processTranscription(filepath, rl);
    } catch (error) {
      console.error(`❌ Erro no processamento, continuando...`);
      continue;
    }
  }

  rl.close();

  console.log("\n" + "=".repeat(80));
  console.log("✅ PROCESSAMENTO CONCLUÍDO");
  console.log("=".repeat(80));
  console.log(`\n📁 Dossiês salvos em: ${PATIENTS_DIR}\n`);
}

main().catch((error) => {
  console.error("\n❌ Erro fatal:", error);
  process.exit(1);
});
