import { createConversationId, createRunId, createTaskId } from "./ids.js";
import { isExplicitMemoryCommit } from "./memory-policy.js";
import { appendAgentEvent, createAgentEvent, type AgentEventWriteOptions } from "./telemetry.js";
import { pipelineAgentId } from "./registry.js";
import type {
  AgentEvent,
  AgentRuntimeName,
  AgentResult,
  AgentTask,
  AgentTaskKind,
} from "./types.js";

export type ConversationOrchestratorOptions = {
  conversationId?: string;
  patientId?: string;
  sessionId?: string;
  runtime?: AgentRuntimeName;
  eventSinks?: string[];
  skipDefaultSinks?: boolean;
};

export type CreateAgentTaskOptions = {
  agentId?: string;
  kind?: AgentTaskKind;
  inputRefs?: string[];
  patientId?: string;
  sessionId?: string;
  requiresApproval?: boolean;
  runId?: string;
};

export class ConversationOrchestrator {
  readonly conversationId: string;
  readonly patientId?: string;
  readonly sessionId?: string;
  private runtime: AgentRuntimeName;
  private eventOptions: AgentEventWriteOptions;

  constructor(options: ConversationOrchestratorOptions = {}) {
    this.conversationId = options.conversationId ?? createConversationId();
    this.patientId = options.patientId;
    this.sessionId = options.sessionId;
    this.runtime = options.runtime ?? "deterministic";
    this.eventOptions = {
      sinks: options.eventSinks,
      skipDefaultSinks: options.skipDefaultSinks,
    };
  }

  setRuntime(runtime: AgentRuntimeName): void {
    this.runtime = runtime;
  }

  createTask(input: string, options: CreateAgentTaskOptions = {}): AgentTask {
    const agentId = options.agentId ?? routeIntentToAgent(input);
    return {
      task_id: createTaskId(),
      conversation_id: this.conversationId,
      run_id: options.runId ?? createRunId(),
      agent_id: agentId,
      kind: options.kind ?? inferTaskKind(agentId),
      input,
      input_refs: options.inputRefs ?? [],
      patient_id: options.patientId ?? this.patientId,
      session_id: options.sessionId ?? this.sessionId,
      requires_approval: options.requiresApproval ?? false,
      created_at: new Date().toISOString(),
    };
  }

  recordMessageReceived(input: string, task?: AgentTask): AgentEvent {
    const messageTask = task ?? this.createTask(input, { kind: "conversation" });
    return this.writeEvent({
      task: messageTask,
      kind: "message.received",
      status: "completed",
      metadata: {
        input_length: input.length,
        routed_agent_id: messageTask.agent_id,
      },
    });
  }

  async runTask(task: AgentTask, runner: () => Promise<AgentResult>): Promise<AgentResult> {
    this.writeEvent({ task, kind: "agent.planned", status: "planned" });
    const started = this.writeEvent({ task, kind: "agent.started", status: "running" });
    const startedAtMs = Date.now();

    try {
      const result = await runner();
      this.writeEvent({
        task,
        kind: result.status === "failed" ? "agent.failed" : result.review_required ? "review.requested" : "agent.completed",
        status: result.status === "failed" ? "failed" : result.review_required ? "blocked" : "completed",
        parentEventId: started.event_id,
        outputRefs: result.output_refs,
        error: result.error,
        metadata: {
          result_status: result.status,
          handoff_to: result.handoff_to,
          duration_ms: Date.now() - startedAtMs,
        },
      });
      return result;
    } catch (error) {
      this.writeEvent({
        task,
        kind: "agent.failed",
        status: "failed",
        parentEventId: started.event_id,
        error,
        metadata: {
          duration_ms: Date.now() - startedAtMs,
        },
      });
      return {
        status: "failed",
        content: "",
        output_refs: [],
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }

  recordToolStarted(task: AgentTask, toolName: string): AgentEvent {
    return this.writeEvent({
      task,
      kind: "tool.started",
      status: "running",
      metadata: { tool_name: toolName },
    });
  }

  recordToolCompleted(task: AgentTask, toolName: string, startedEventId?: string, outputRefs: string[] = []): AgentEvent {
    return this.writeEvent({
      task,
      kind: "tool.completed",
      status: "completed",
      parentEventId: startedEventId,
      outputRefs,
      metadata: { tool_name: toolName },
    });
  }

  recordToolFailed(task: AgentTask, toolName: string, error: unknown, startedEventId?: string): AgentEvent {
    return this.writeEvent({
      task,
      kind: "tool.failed",
      status: "failed",
      parentEventId: startedEventId,
      error,
      metadata: { tool_name: toolName },
    });
  }

  recordMemoryCommitted(task: AgentTask, outputRef?: string): AgentEvent {
    return this.writeEvent({
      task,
      kind: "memory.committed",
      status: "completed",
      outputRefs: outputRef ? [outputRef] : [],
    });
  }

  private writeEvent(input: {
    task: AgentTask;
    kind: AgentEvent["kind"];
    status: AgentEvent["status"];
    parentEventId?: string | null;
    outputRefs?: string[];
    error?: unknown;
    metadata?: Record<string, unknown>;
  }): AgentEvent {
    const now = new Date().toISOString();
    const event = createAgentEvent({
      run_id: input.task.run_id,
      conversation_id: input.task.conversation_id,
      task_id: input.task.task_id,
      parent_event_id: input.parentEventId ?? null,
      agent_id: input.task.agent_id,
      kind: input.kind,
      status: input.status,
      patient_id: input.task.patient_id,
      session_id: input.task.session_id,
      runtime: this.runtime,
      input_refs: input.task.input_refs,
      output_refs: input.outputRefs ?? [],
      started_at: now,
      ended_at: input.status === "running" || input.status === "planned" ? null : now,
      error: input.error,
      metadata: input.metadata,
    });
    appendAgentEvent(event, this.eventOptions);
    return event;
  }
}

export function routeIntentToAgent(input: string): string {
  const text = input.toLowerCase();
  if (isExplicitMemoryCommit(input) || text.includes("memoria") || text.includes("memória")) return "memory-agent";
  if (text.includes("risk") || text.includes("risco") || text.includes("suicid") || text.includes("seguranca") || text.includes("segurança")) return "risk-check-agent";
  if (text.includes("prepar") && text.includes("sess")) return "session-prep-agent";
  if (text.includes("longitudinal") || text.includes("linha do tempo")) return "longitudinal-reviewer-agent";
  if (text.includes("transcri")) return "transcription-agent";
  if (text.includes("patient-speech") || text.includes("fala do paciente")) return "speech-attribution-agent";
  if (text.includes("asl")) return "asl-agent";
  if (text.includes("vdlp")) return "vdlp-agent";
  if (text.includes("gem")) return "gem-agent";
  if (text.includes("pipeline")) return "tool-runner-agent";
  if (text.includes("qa") || text.includes("teste") || text.includes("valid")) return "qa-agent";
  if (text.includes("context") || text.includes("arquitet")) return "context-agent";
  return "conversation-agent";
}

export function taskForPipelineStage(stage: string, input: string, options: Omit<CreateAgentTaskOptions, "agentId" | "kind"> = {}): CreateAgentTaskOptions & { input: string } {
  return {
    ...options,
    input,
    agentId: pipelineAgentId(stage),
    kind: "pipeline",
  };
}

function inferTaskKind(agentId: string): AgentTaskKind {
  if (agentId.endsWith("-agent") && ["asl-agent", "vdlp-agent", "gem-agent", "transcription-agent", "speech-attribution-agent", "session-structuring-agent"].includes(agentId)) {
    return "pipeline";
  }
  if (agentId.includes("risk") || agentId.includes("session-prep") || agentId.includes("longitudinal") || agentId.includes("patient-care")) return "clinical";
  if (agentId.includes("memory")) return "memory";
  if (agentId.includes("qa")) return "qa";
  if (agentId.includes("tool-runner")) return "tool";
  if (agentId.includes("context") || agentId.includes("safety")) return "governance";
  return "conversation";
}
