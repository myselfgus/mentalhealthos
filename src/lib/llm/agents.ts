import { HEALTHOS_AGENTS, getHealthOSAgent, type HealthOSAgent } from "../../agents/catalog.js";

export type AgentSource = "healthos" | "codex";

export type AgentSummary = {
  id: string;
  title: string;
  source: AgentSource;
  category?: string;
  availability?: "active" | "scenario";
  purpose?: string;
};

export function listHealthOSAgents(options: { includeScenario?: boolean } = {}): HealthOSAgent[] {
  return HEALTHOS_AGENTS
    .filter((agent) => options.includeScenario || agent.availability === "active")
    .slice()
    .sort((a, b) => a.id.localeCompare(b.id));
}

export function listHealthOSAgentSummaries(options: { includeScenario?: boolean } = {}): AgentSummary[] {
  return listHealthOSAgents(options).map((agent) => ({
    id: agent.id,
    title: agent.title,
    source: "healthos",
    category: agent.category,
    availability: agent.availability,
    purpose: agent.purpose,
  }));
}

export function readHealthOSAgent(id?: string): string | null {
  if (!id) return null;
  const agent = getHealthOSAgent(id);
  if (!agent) return null;

  const useWhen = agent.useWhen.map((item) => `- ${item}`).join("\n");
  const avoidWhen = agent.avoidWhen?.length
    ? `\n\n## Evite quando\n${agent.avoidWhen.map((item) => `- ${item}`).join("\n")}`
    : "";

  return `# ${agent.title}

id: ${agent.id}
category: ${agent.category}
availability: ${agent.availability}

## Proposito
${agent.purpose}

## Use quando
${useWhen}${avoidWhen}

## Instrucao
${agent.prompt}`;
}

export function findHealthOSAgentMention(input: string): HealthOSAgent | undefined {
  const lowered = input.toLowerCase();
  return listHealthOSAgents({ includeScenario: true })
    .find((agent) => lowered.includes(agent.id.toLowerCase()) || lowered.includes(agent.title.toLowerCase()));
}
