/**
 * HealthOS — adaptive clinical chunking for LLM calls.
 *
 * Design goals:
 * - preserve clinical discourse boundaries before enforcing size;
 * - keep speaker turns intact whenever possible;
 * - add controlled overlap only for analytical stages, not transcription rewrite;
 * - return provenance metadata for auditability.
 */

import { TOKENS } from "../../config/defaults.js";

export type ClinicalChunkKind =
  | "heading"
  | "speaker_turn"
  | "paragraph"
  | "list_item"
  | "sentence"
  | "oversize";

export type ChunkingMode =
  | "clinical-transcript"
  | "clinical-document"
  | "adaptive";

export interface ChunkingOptions {
  /** Target chunk size. This is an input planning budget, not model max output. */
  targetTokens?: number;
  /** Hard ceiling for a chunk before fallback splitting. */
  maxTokensPerChunk?: number;
  /** Context copied from previous chunk. Use 0 for rewrite/correction tasks. */
  overlapTokens?: number;
  /** Preserve speaker turns, headings, paragraphs and sentences. */
  preserveBoundaries?: boolean;
  /** Add provenance micro-header to chunk text. */
  includeMetadataHeader?: boolean;
  /** Strategy hint for block detection. */
  mode?: ChunkingMode;
  /** Label written in optional metadata header. */
  sourceLabel?: string;
}

export interface ClinicalChunk {
  index: number;
  total: number;
  text: string;
  rawText: string;
  tokenEstimate: number;
  charStart: number;
  charEnd: number;
  overlapFromPrevious: boolean;
  overlapTokenEstimate: number;
  kinds: ClinicalChunkKind[];
  speakers: string[];
  headings: string[];
}

interface TextBlock {
  text: string;
  kind: ClinicalChunkKind;
  charStart: number;
  charEnd: number;
  speaker?: string;
  heading?: string;
}

const DEFAULT_TARGET_TOKENS = 1800;
const DEFAULT_MAX_TOKENS = 2400;
const DEFAULT_OVERLAP_TOKENS = 180;
const MIN_OVERSIZE_SPLIT_TOKENS = 600;

/**
 * Estima tokens de um texto. Mantemos estimativa local e determinística porque
 * os runtimes ClaudeCode/Codex não expõem tokenizer/modelo antes da chamada.
 */
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / TOKENS.CHARS_PER_TOKEN);
}

/**
 * API compatível com os scripts existentes.
 */
export function splitIntoChunks(
  text: string,
  optionsOrMaxTokens: number | ChunkingOptions = DEFAULT_TARGET_TOKENS
): string[] {
  const options = normalizeOptions(optionsOrMaxTokens);
  return chunkClinicalText(text, options).map((chunk) => chunk.text);
}

export function chunkClinicalText(
  text: string,
  options: ChunkingOptions = {}
): ClinicalChunk[] {
  const normalized = normalizeText(text);
  if (!normalized.trim()) return [];

  const opts = normalizeOptions(options);
  const blocks = opts.preserveBoundaries === false
    ? splitOversizeBlock({
        text: normalized,
        kind: "paragraph",
        charStart: 0,
        charEnd: normalized.length,
      }, opts)
    : buildBlocks(normalized, opts);

  const grouped = groupBlocks(blocks, opts);
  return finalizeChunks(grouped, opts);
}

function normalizeOptions(optionsOrMaxTokens: number | ChunkingOptions): Required<ChunkingOptions> {
  if (typeof optionsOrMaxTokens === "number") {
    return {
      targetTokens: Math.max(MIN_OVERSIZE_SPLIT_TOKENS, Math.floor(optionsOrMaxTokens * 0.85)),
      maxTokensPerChunk: optionsOrMaxTokens,
      overlapTokens: 0,
      preserveBoundaries: true,
      includeMetadataHeader: false,
      mode: "adaptive",
      sourceLabel: "clinical_text",
    };
  }

  const maxTokens = optionsOrMaxTokens.maxTokensPerChunk ?? DEFAULT_MAX_TOKENS;
  return {
    targetTokens: optionsOrMaxTokens.targetTokens ?? Math.min(DEFAULT_TARGET_TOKENS, Math.floor(maxTokens * 0.82)),
    maxTokensPerChunk: maxTokens,
    overlapTokens: optionsOrMaxTokens.overlapTokens ?? DEFAULT_OVERLAP_TOKENS,
    preserveBoundaries: optionsOrMaxTokens.preserveBoundaries ?? true,
    includeMetadataHeader: optionsOrMaxTokens.includeMetadataHeader ?? false,
    mode: optionsOrMaxTokens.mode ?? "adaptive",
    sourceLabel: optionsOrMaxTokens.sourceLabel ?? "clinical_text",
  };
}

function normalizeText(text: string): string {
  return text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .trim();
}

function buildBlocks(text: string, options: Required<ChunkingOptions>): TextBlock[] {
  const primary = options.mode === "clinical-transcript"
    ? splitSpeakerTurns(text)
    : splitStructuredBlocks(text);

  return primary.flatMap((block) => {
    if (estimateTokens(block.text) <= options.maxTokensPerChunk) return [block];
    return splitOversizeBlock(block, options);
  });
}

function splitStructuredBlocks(text: string): TextBlock[] {
  const blocks: TextBlock[] = [];
  const blockRegex = /(?:^|\n{2,})([\s\S]*?)(?=\n{2,}|$)/g;
  let match: RegExpExecArray | null;

  while ((match = blockRegex.exec(text)) !== null) {
    const raw = match[1]?.trim();
    if (!raw) continue;
    const charStart = match.index + (match[0].startsWith("\n\n") ? 2 : 0);
    const kind = classifyBlock(raw);
    blocks.push({
      text: raw,
      kind,
      charStart,
      charEnd: charStart + raw.length,
      heading: kind === "heading" ? raw.replace(/^#+\s*/, "") : undefined,
      speaker: extractSpeaker(raw),
    });
  }

  return blocks.length ? blocks : [{
    text,
    kind: "paragraph",
    charStart: 0,
    charEnd: text.length,
    speaker: extractSpeaker(text),
  }];
}

function splitSpeakerTurns(text: string): TextBlock[] {
  const turnRegex = /(^|\n)(\s*(?:Falante|Speaker)\s+\d+|Paciente|Profissional|Terapeuta|Psiquiatra|Dr\.?\s+[^:\n]{1,80}|Dra\.?\s+[^:\n]{1,80})\s*[:：-]\s*/gim;
  const matches = [...text.matchAll(turnRegex)];
  if (matches.length === 0) return splitStructuredBlocks(text);

  const blocks: TextBlock[] = [];
  for (let i = 0; i < matches.length; i++) {
    const current = matches[i];
    const next = matches[i + 1];
    const charStart = current.index ?? 0;
    const charEnd = next?.index ?? text.length;
    const raw = text.slice(charStart, charEnd).trim();
    if (!raw) continue;

    blocks.push({
      text: raw,
      kind: "speaker_turn",
      charStart,
      charEnd,
      speaker: current[2]?.trim(),
    });
  }

  const prefix = text.slice(0, matches[0].index ?? 0).trim();
  if (prefix) {
    blocks.unshift({
      text: prefix,
      kind: "paragraph",
      charStart: 0,
      charEnd: prefix.length,
    });
  }

  return blocks;
}

function classifyBlock(text: string): ClinicalChunkKind {
  if (/^#{1,6}\s+\S/.test(text) || /^[A-ZÀ-Ú0-9][^.\n]{2,80}:$/.test(text)) return "heading";
  if (/^\s*(?:[-*•]|\d+[.)])\s+/.test(text)) return "list_item";
  if (extractSpeaker(text)) return "speaker_turn";
  return "paragraph";
}

function extractSpeaker(text: string): string | undefined {
  const match = text.match(/^\s*((?:Falante|Speaker)\s+\d+|Paciente|Profissional|Terapeuta|Psiquiatra|Dr\.?\s+[^:\n]{1,80}|Dra\.?\s+[^:\n]{1,80})\s*[:：-]/i);
  return match?.[1]?.trim();
}

function splitOversizeBlock(block: TextBlock, options: Required<ChunkingOptions>): TextBlock[] {
  const sentenceParts = splitSentences(block.text);
  const parts = sentenceParts.length > 1 ? sentenceParts : splitByTokenBudget(block.text, options.targetTokens);
  const output: TextBlock[] = [];
  let cursor = block.charStart;
  let current = "";
  let currentStart = block.charStart;

  for (const part of parts) {
    const proposed = current ? `${current} ${part}` : part;
    if (current && estimateTokens(proposed) > options.targetTokens) {
      output.push({
        text: current.trim(),
        kind: sentenceParts.length > 1 ? "sentence" : "oversize",
        charStart: currentStart,
        charEnd: currentStart + current.length,
        speaker: block.speaker,
        heading: block.heading,
      });
      currentStart = cursor;
      current = part;
    } else {
      current = proposed;
    }
    cursor += part.length + 1;
  }

  if (current.trim()) {
    output.push({
      text: current.trim(),
      kind: sentenceParts.length > 1 ? "sentence" : "oversize",
      charStart: currentStart,
      charEnd: block.charEnd,
      speaker: block.speaker,
      heading: block.heading,
    });
  }

  return output;
}

function splitSentences(text: string): string[] {
  const segmented = text
    .split(/(?<=[.!?…])\s+(?=[A-ZÀ-Ú0-9"“])/)
    .map((part) => part.trim())
    .filter(Boolean);
  return segmented.length > 1 ? segmented : [];
}

function splitByTokenBudget(text: string, targetTokens: number): string[] {
  const maxChars = targetTokens * TOKENS.CHARS_PER_TOKEN;
  const words = text.split(/\s+/);
  const parts: string[] = [];
  let current = "";

  for (const word of words) {
    const proposed = current ? `${current} ${word}` : word;
    if (current && proposed.length > maxChars) {
      parts.push(current);
      current = word;
    } else {
      current = proposed;
    }
  }

  if (current) parts.push(current);
  return parts;
}

function groupBlocks(blocks: TextBlock[], options: Required<ChunkingOptions>): TextBlock[][] {
  const groups: TextBlock[][] = [];
  let current: TextBlock[] = [];
  let currentTokens = 0;

  for (const block of blocks) {
    const blockTokens = estimateTokens(block.text);
    const wouldExceed = current.length > 0 && currentTokens + blockTokens > options.targetTokens;
    const hardExceed = current.length > 0 && currentTokens + blockTokens > options.maxTokensPerChunk;

    if (wouldExceed || hardExceed) {
      groups.push(current);
      current = buildOverlap(current, options);
      currentTokens = current.reduce((sum, item) => sum + estimateTokens(item.text), 0);
    }

    current.push(block);
    currentTokens += blockTokens;
  }

  if (current.length) groups.push(current);
  return groups;
}

function buildOverlap(blocks: TextBlock[], options: Required<ChunkingOptions>): TextBlock[] {
  if (options.overlapTokens <= 0) return [];

  const overlap: TextBlock[] = [];
  let tokens = 0;

  for (let i = blocks.length - 1; i >= 0; i--) {
    const block = blocks[i];
    const blockTokens = estimateTokens(block.text);
    if (overlap.length && tokens + blockTokens > options.overlapTokens) break;
    overlap.unshift({ ...block });
    tokens += blockTokens;
    if (tokens >= options.overlapTokens) break;
  }

  return overlap;
}

function finalizeChunks(groups: TextBlock[][], options: Required<ChunkingOptions>): ClinicalChunk[] {
  return groups.map((group, index) => {
    const rawText = group.map((block) => block.text).join("\n\n").trim();
    const overlapFromPrevious = index > 0 && hasOverlap(group, groups[index - 1]);
    const overlapTokenEstimate = overlapFromPrevious ? estimateOverlap(group, groups[index - 1]) : 0;
    const metadata = collectMetadata(group);
    const chunk: ClinicalChunk = {
      index,
      total: groups.length,
      text: rawText,
      rawText,
      tokenEstimate: estimateTokens(rawText),
      charStart: Math.min(...group.map((block) => block.charStart)),
      charEnd: Math.max(...group.map((block) => block.charEnd)),
      overlapFromPrevious,
      overlapTokenEstimate,
      ...metadata,
    };

    if (options.includeMetadataHeader) {
      chunk.text = renderChunkWithHeader(chunk, options.sourceLabel);
    }

    return chunk;
  });
}

function collectMetadata(group: TextBlock[]): Pick<ClinicalChunk, "kinds" | "speakers" | "headings"> {
  return {
    kinds: [...new Set(group.map((block) => block.kind))],
    speakers: [...new Set(group.map((block) => block.speaker).filter(Boolean) as string[])],
    headings: [...new Set(group.map((block) => block.heading).filter(Boolean) as string[])],
  };
}

function hasOverlap(group: TextBlock[], previous?: TextBlock[]): boolean {
  if (!previous?.length || !group.length) return false;
  return group.some((block) => previous.some((prev) => prev.charStart === block.charStart && prev.charEnd === block.charEnd));
}

function estimateOverlap(group: TextBlock[], previous?: TextBlock[]): number {
  if (!previous?.length) return 0;
  return group
    .filter((block) => previous.some((prev) => prev.charStart === block.charStart && prev.charEnd === block.charEnd))
    .reduce((sum, block) => sum + estimateTokens(block.text), 0);
}

function renderChunkWithHeader(chunk: ClinicalChunk, sourceLabel: string): string {
  const speakers = chunk.speakers.length ? chunk.speakers.join(", ") : "n/a";
  const overlap = chunk.overlapFromPrevious ? `yes ~${chunk.overlapTokenEstimate} tokens` : "no";
  return [
    `[HealthOS chunk ${chunk.index + 1}/${chunk.total}]`,
    `source=${sourceLabel}; chars=${chunk.charStart}-${chunk.charEnd}; tokens~=${chunk.tokenEstimate}; overlap=${overlap}; speakers=${speakers}`,
    "",
    chunk.rawText,
  ].join("\n");
}
