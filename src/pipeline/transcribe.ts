#!/usr/bin/env node
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { readFileSync, writeFileSync, readdirSync, existsSync } from "fs";
import { extname, join, parse, relative } from "path";
import { createInterface } from "readline";
import { config } from "dotenv";
import { Buffer } from "node:buffer";
import { execSync } from "child_process";
import { PATHS, CLOUDFLARE } from "./config/defaults.js";
import {
  ensurePatientSessionWorkspace,
  listAllPatientSessionWorkspaces,
  type PatientSessionWorkspace,
} from "./patients/workspace.js";

config({ path: PATHS.ENV, override: false });

const CF_ACCOUNT_ID = CLOUDFLARE.ACCOUNT_ID;
const CF_GATEWAY_NAME = CLOUDFLARE.GATEWAY_NAME;
const CF_AUTHORIZATION = process.env.CLOUDFLARE_API_TOKEN ? `Bearer ${process.env.CLOUDFLARE_API_TOKEN}` : "";
const CF_AIG_AUTHORIZATION = process.env.CLOUDFLARE_AI_GATEWAY_TOKEN ? `Bearer ${process.env.CLOUDFLARE_AI_GATEWAY_TOKEN}` : "";

const AUDIO_EXTENSIONS = [".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg", ".webm", ".mp4", ".mov"];

const MIME_TYPES: Record<string, string> = {
  m4a: "audio/mp4",
  mp3: "audio/mpeg",
  wav: "audio/wav",
  aac: "audio/aac",
  flac: "audio/flac",
  ogg: "audio/ogg",
  webm: "audio/webm",
  mp4: "audio/mp4",
  mov: "video/quicktime",
};

type SessionAudioFile = {
  session: PatientSessionWorkspace;
  file: string;
  audioPath: string;
};

function displayPath(path: string): string {
  return relative(PATHS.BASE, path) || path;
}

function listSessionAudioFiles(): SessionAudioFile[] {
  return listAllPatientSessionWorkspaces()
    .flatMap((session) => {
      if (!existsSync(session.audioDir)) return [];
      return readdirSync(session.audioDir)
        .filter((file) => AUDIO_EXTENSIONS.includes(extname(file).toLowerCase()))
        .sort()
        .map((file) => ({
          session,
          file,
          audioPath: join(session.audioDir, file),
        }));
    })
    .sort((a, b) => a.audioPath.localeCompare(b.audioPath));
}

function formatDiarizedText(words: any[]): string {
  if (!words?.length) return "";
  
  let result = "";
  let currentSpeaker: string | null = null;
  
  for (const word of words) {
    const speaker = word.speakerId;
    const text = word.text || "";
    
    if (speaker && speaker !== currentSpeaker) {
      currentSpeaker = speaker;
      const speakerNum = parseInt(speaker.split("_")[1] || "0") + 1;
      result += `\n\n[Falante ${speakerNum}] `;
    }
    
    result += text;
  }
  
  return result.trim();
}

export async function transcribeAudio(audioPath: string, enableDiarization: boolean = true) {
  const elevenlabs = new ElevenLabsClient({ apiKey: process.env.ELEVENLABS_API_KEY });
  
  const audioBuffer = readFileSync(audioPath);
  const extensao = extname(audioPath).toLowerCase().replace(".", "");
  const audioBlob = new Blob([audioBuffer], { type: MIME_TYPES[extensao] || `audio/${extensao}` });

  const result = await elevenlabs.speechToText.convert({
    file: audioBlob,
    modelId: "scribe_v1",
    tagAudioEvents: true,
    languageCode: "por",
    diarize: enableDiarization,
  }) as any;

  const text = enableDiarization && result.words?.length 
    ? formatDiarizedText(result.words)
    : result.text;

  return {
    text,
    language_code: result.languageCode,
    language_probability: result.languageProbability,
  };
}

export async function transcribeWithWorkersAI(audioPath: string, enableDiarization: boolean = true) {
  const audioBuffer = readFileSync(audioPath);
  const base64Audio = Buffer.from(audioBuffer).toString("base64");
  const gatewayUrl = `https://gateway.ai.cloudflare.com/v1/${CF_ACCOUNT_ID}/${CF_GATEWAY_NAME}/workers-ai/run/@cf/openai/whisper-large-v3-turbo`;

  const requestBody: any = { audio: base64Audio };
  if (enableDiarization) requestBody.diarize = true;

  const response = await fetch(gatewayUrl, {
    method: "POST",
    headers: {
      "Authorization": CF_AUTHORIZATION,
      "cf-aig-authorization": CF_AIG_AUTHORIZATION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Workers AI error (${response.status}): ${errorText}`);
  }

  const result = await response.json() as any;

  return {
    text: result.text || result.result?.text,
    language_code: "por",
    language_probability: 0.95,
  };
}

export async function transcribeWithWhisperXMLX(audioPath: string) {
  // WhisperX-MLX sempre usa diarização (built-in)
  const whisperScriptPath = join(PATHS.BASE, "local-whisper", "transcribe.py");
  const outputDir = join(PATHS.BASE, "local-whisper", "output");
  const inputDir = join(PATHS.BASE, "local-whisper", "input");

  // Copia arquivo para input/ do whisperx
  const fileName = parse(audioPath).base;
  const tempInputPath = join(inputDir, fileName);
  const audioBuffer = readFileSync(audioPath);
  writeFileSync(tempInputPath, audioBuffer);

  try {
    console.log("   🚀 Processando com WhisperX-MLX (large-v3 + diarização)...");

    // Executa script Python do WhisperX
    execSync(`python3 "${whisperScriptPath}" "${tempInputPath}"`, {
      stdio: "inherit", // Mostra progresso no terminal
      cwd: join(PATHS.BASE, "local-whisper")
    });

    // Lê resultado JSON gerado
    const fileBase = parse(fileName).name;
    const outputPath = join(outputDir, `${fileBase}_transcricao.json`);

    if (!existsSync(outputPath)) {
      throw new Error("WhisperX não gerou arquivo de saída");
    }

    const result = JSON.parse(readFileSync(outputPath, "utf-8"));

    return {
      text: result.transcricao,
      language_code: result.language || "pt",
      language_probability: 0.98, // WhisperX large-v3 tem alta acurácia
    };
  } finally {
    // Cleanup: remove arquivo temporário do input
    if (existsSync(tempInputPath)) {
      execSync(`rm "${tempInputPath}"`);
    }
  }
}

async function main() {
  console.log("\n" + "=".repeat(80));
  console.log("🎙️  TRANSCRIBE");
  console.log("=".repeat(80));

  const rl = createInterface({ input: process.stdin, output: process.stdout });

  console.log("\n🔧 Serviço:");
  console.log("   1. ElevenLabs Scribe v1 (Cloud, diarização)");
  console.log("   2. Cloudflare Workers AI (Cloud, Whisper large-v3-turbo)");
  console.log("   3. WhisperX-MLX Local (Apple Silicon, large-v3 + diarização)");

  const providerChoice = await new Promise<string>((resolve) => {
    rl.question("\n💬 Escolha (1/2/3): ", resolve);
  });

  const provider = providerChoice.trim();
  const useWorkersAI = provider === "2";
  const useWhisperXMLX = provider === "3";

  let enableDiarization = true;

  // WhisperX-MLX sempre tem diarização, não precisa perguntar
  if (!useWhisperXMLX) {
    const diarizeChoice = await new Promise<string>((resolve) => {
      rl.question("💬 Diarização? (S/n): ", resolve);
    });
    enableDiarization = diarizeChoice.trim().toLowerCase() !== "n";
  } else {
    console.log("💬 Diarização: Ativada (automática no WhisperX-MLX)");
  }

  const forceChoice = await new Promise<string>((resolve) => {
    rl.question("💬 Reprocessar arquivos já transcritos? (s/N): ", resolve);
  });
  const forceReprocess = forceChoice.trim().toLowerCase() === "s";

  const audioFiles = listSessionAudioFiles();

  if (audioFiles.length === 0) {
    console.log("\n⚠️  Nenhum áudio encontrado em patients/*/sessions/*/source/audio/");
    return;
  }

  console.log(`\n📋 ${audioFiles.length} arquivo(s):`);
  audioFiles.forEach((item, idx) => {
    console.log(`   ${idx + 1}. ${item.session.patientId}/${item.session.id} — ${displayPath(item.audioPath)}`);
  });

  const answer = await new Promise<string>((resolve) => {
    rl.question("\n💬 Processar (números, 'a' ou Enter para todos): ", resolve);
  });
  rl.close();

  let selectedFiles: SessionAudioFile[];
  if (!answer || answer.trim() === "" || answer.trim().toLowerCase() === "a") {
    selectedFiles = audioFiles;
  } else {
    const indices = answer
      .split(",")
      .map((s) => parseInt(s.trim()) - 1)
      .filter((i) => i >= 0 && i < audioFiles.length);
    selectedFiles = indices.map((i) => audioFiles[i]);
  }

  if (selectedFiles.length === 0) {
    console.log("\n⚠️  Nenhum arquivo selecionado");
    return;
  }

  console.log("\n" + "=".repeat(80));
  console.log(`🚀 ${selectedFiles.length} ARQUIVO(S)`);
  console.log("=".repeat(80));

  let processed = 0;
  let skipped = 0;

  for (let i = 0; i < selectedFiles.length; i++) {
    const item = selectedFiles[i];
    const { session, file, audioPath } = item;
    const outputPath = ensurePatientSessionWorkspace(session).transcriptionPath;

    console.log(`\n[${i + 1}/${selectedFiles.length}] ${session.patientId}/${session.id} — ${file}`);

    if (!forceReprocess && existsSync(outputPath)) {
      console.log(`⏭️  Cache: sessão já tem transcrição`);
      skipped++;
      continue;
    }

    try {
      let result;
      let serviceName;

      if (useWhisperXMLX) {
        result = await transcribeWithWhisperXMLX(audioPath);
        serviceName = "whisperx_mlx_local";
      } else if (useWorkersAI) {
        result = await transcribeWithWorkersAI(audioPath, enableDiarization);
        serviceName = "cloudflare_workers_ai";
      } else {
        result = await transcribeAudio(audioPath, enableDiarization);
        serviceName = "elevenlabs_scribe_v1";
      }

      const output = {
        arquivo: file,
        audio_source: {
          patient_id: session.patientId,
          session_id: session.id,
          file,
          path: displayPath(audioPath),
        },
        data: new Date().toISOString(),
        servico: serviceName,
        idioma: result.language_code,
        confianca: result.language_probability,
        diarizacao: useWhisperXMLX ? true : enableDiarization,
        transcricao: result.text,
      };

      writeFileSync(outputPath, JSON.stringify(output, null, 2));
      console.log(`✅ ${displayPath(outputPath)}`);
      processed++;
    } catch (error) {
      console.error(`❌ Erro:`, error);
    }
  }

  console.log("\n" + "=".repeat(80));
  console.log("✅ CONCLUÍDO");
  console.log(`   Processados: ${processed}`);
  console.log(`   Cache (pulados): ${skipped}`);
  console.log("=".repeat(80) + "\n");
}

main().catch((error) => {
  console.error("\n❌ Erro:", error);
  process.exit(1);
});
