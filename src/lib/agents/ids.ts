import { randomUUID } from "crypto";

export function createAgentId(prefix: "task" | "run" | "conv" | "evt"): string {
  return `${prefix}_${randomUUID()}`;
}

export function createConversationId(): string {
  return createAgentId("conv");
}

export function createRunId(): string {
  return createAgentId("run");
}

export function createTaskId(): string {
  return createAgentId("task");
}

export function createEventId(): string {
  return createAgentId("evt");
}
