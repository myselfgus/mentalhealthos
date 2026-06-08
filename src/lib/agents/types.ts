import type { LLMRuntimeName } from "../llm/types.js";

export type AgentTaskKind =
  | "conversation"
  | "pipeline"
  | "clinical"
  | "governance"
  | "memory"
  | "qa"
  | "tool"
  | "subprocess";

export type AgentResultStatus = "completed" | "failed" | "needs_review" | "handoff";

export type AgentEventStatus = "planned" | "running" | "completed" | "failed" | "blocked";

export type AgentEventKind =
  | "message.received"
  | "agent.planned"
  | "agent.started"
  | "tool.started"
  | "tool.completed"
  | "tool.failed"
  | "artifact.created"
  | "review.requested"
  | "memory.proposed"
  | "memory.committed"
  | "agent.completed"
  | "agent.failed";

export type AgentRuntimeName =
  | LLMRuntimeName
  | "ClaudeSDK"
  | "CodexSubprocess"
  | "deterministic";

export type AgentSource =
  | "healthos"
  | "codex"
  | "patient"
  | "system";

export type AgentTask = {
  task_id: string;
  conversation_id: string;
  run_id: string;
  agent_id: string;
  kind: AgentTaskKind;
  input: string;
  input_refs: string[];
  patient_id?: string;
  session_id?: string;
  requires_approval: boolean;
  created_at: string;
};

export type AgentResult = {
  status: AgentResultStatus;
  content: string;
  output_refs: string[];
  handoff_to?: string;
  review_required?: boolean;
  error?: string;
};

export type AgentEvent = {
  event_id: string;
  run_id: string;
  conversation_id: string;
  task_id?: string;
  parent_event_id: string | null;
  agent_id: string;
  kind: AgentEventKind;
  status: AgentEventStatus;
  patient_id?: string;
  session_id?: string;
  runtime: AgentRuntimeName;
  input_refs: string[];
  output_refs: string[];
  started_at: string;
  ended_at: string | null;
  error: string | null;
  metadata?: Record<string, unknown>;
};

export type AgentDefinition = {
  id: string;
  title: string;
  source: AgentSource;
  category: string;
  purpose: string;
  runtime_policy: "llm-runtime" | "codex-local" | "claude-sdk" | "deterministic";
  tools: string[];
  path?: string;
  prompt?: string;
  patient_id?: string;
};
