import { appendFileSync, existsSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { PATHS } from "../../config/defaults.js";
import { getActiveProfessionalWorkspace } from "../../professionals/workspace.js";
import { getPatientWorkspace } from "../../patients/workspace.js";
import { createEventId } from "./ids.js";
import type {
  AgentEvent,
  AgentEventKind,
  AgentEventStatus,
  AgentRuntimeName,
} from "./types.js";

export type AgentEventDraft = {
  run_id: string;
  conversation_id: string;
  task_id?: string;
  parent_event_id?: string | null;
  agent_id: string;
  kind: AgentEventKind;
  status: AgentEventStatus;
  patient_id?: string;
  session_id?: string;
  runtime: AgentRuntimeName;
  input_refs?: string[];
  output_refs?: string[];
  started_at?: string;
  ended_at?: string | null;
  error?: unknown;
  metadata?: Record<string, unknown>;
};

export type AgentEventWriteOptions = {
  sinks?: string[];
  skipDefaultSinks?: boolean;
};

export function createAgentEvent(draft: AgentEventDraft): AgentEvent {
  return {
    event_id: createEventId(),
    run_id: draft.run_id,
    conversation_id: draft.conversation_id,
    task_id: draft.task_id,
    parent_event_id: draft.parent_event_id ?? null,
    agent_id: draft.agent_id,
    kind: draft.kind,
    status: draft.status,
    patient_id: draft.patient_id,
    session_id: draft.session_id,
    runtime: draft.runtime,
    input_refs: draft.input_refs ?? [],
    output_refs: draft.output_refs ?? [],
    started_at: draft.started_at ?? new Date().toISOString(),
    ended_at: draft.ended_at ?? null,
    error: draft.error ? redactError(draft.error) : null,
    metadata: draft.metadata,
  };
}

export function appendAgentEvent(event: AgentEvent, options: AgentEventWriteOptions = {}): void {
  const sinks = options.sinks ?? (options.skipDefaultSinks ? [] : defaultEventSinks(event));
  for (const sink of unique(sinks)) {
    ensureParentDir(sink);
    appendFileSync(sink, `${JSON.stringify(event)}\n`, "utf-8");
  }
}

export function defaultEventSinks(event: AgentEvent): string[] {
  const sinks = [
    join(PATHS.RUNS, event.run_id, "trace.jsonl"),
  ];

  const professionalWorkspace = getActiveProfessionalWorkspace();
  if (professionalWorkspace) {
    sinks.push(join(professionalWorkspace.telemetryDir, "events.jsonl"));
  }

  if (event.patient_id && /^PAT_\d{6}$/i.test(event.patient_id)) {
    const workspace = getPatientWorkspace(event.patient_id);
    if (existsSync(workspace.dir)) {
      sinks.push(join(workspace.telemetryDir, "events.jsonl"));
    }
  }

  return sinks;
}

export function redactError(error: unknown, maxLength = 2000): string {
  const raw = error instanceof Error ? error.message : String(error);
  return raw
    .replace(/\s+/g, " ")
    .replace(/(["']?api[_-]?key["']?\s*[:=]\s*)["'][^"']+["']/gi, "$1[redacted]")
    .slice(0, maxLength);
}

function ensureParentDir(filePath: string): void {
  mkdirSync(dirname(filePath), { recursive: true });
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}
