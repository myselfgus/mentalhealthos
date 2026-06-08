# LLM Agents

## Decisão

O catálogo de agentes próprios do HealthOS fica em `src/agents/`.

Eles não ficam dentro de `src/lib/llm/providers/` porque não são providers nem clientes. São papéis operacionais que podem ser injetados como contexto para runtimes LLM, especialmente no `chat-cli`.

## Fronteiras

- `src/agents/catalog.ts`: catálogo canônico de agentes HealthOS.
- `src/agents/README.md`: regra de fronteira e uso humano.
- `src/lib/llm/agents.ts`: ponte de leitura/listagem para runtimes e chat-cli.
- `src/lib/agents/`: contratos, registry, política de memória, telemetry e `ConversationOrchestrator`.
- `~/.codex/agents`: agentes globais instalados no Codex do usuário.

## Agentes ativos

- `context-architect`
- `doublecheck`
- `se-responsible-ai-code`
- `se-security-reviewer`
- `se-system-architecture-reviewer`
- `project-documenter`
- `se-technical-writer`
- `implementation-plan`
- `planner`
- `task-researcher`
- `research-technical-spike`
- `ai-team-dev`
- `ai-team-qa`
- `ai-team-producer`

## Agentes por cenário

- `prd`
- `se-product-manager-advisor`
- `se-ux-ui-designer`
- `expert-react-frontend-engineer`
- `typescript-mcp-expert`
- `python-mcp-expert`
- `postgresql-dba`
- `meta-agentic-project-scaffold`

## Como o chat-cli usa

`/agents` lista os agentes HealthOS e os subagentes Codex instalados.

Quando uma mensagem menciona o `id` de um agente HealthOS, o modo Codex injeta a definição do agente no prompt do subprocesso. Se o `id` não existir em `src/agents`, o chat-cli tenta encontrar o mesmo nome em `~/.codex/agents`.

Isso mantém os agentes do projeto versionados no repositório, sem alterar a configuração global do Codex.

## Runtime multiagente

`src/lib/agents/types.ts` define os contratos estáveis:

- `AgentTask`: intenção/tarefa roteada a um agente.
- `AgentResult`: saída, status, handoff e revisão.
- `AgentEvent`: trilha append-only de execução.
- `AgentDefinition`: ponte entre agentes HealthOS, Codex, paciente e agentes internos do sistema.

`ConversationOrchestrator` mantém a posse da resposta final, cria `conversation_id` e `run_id`, roteia intenções para especialistas e grava eventos em `runs/<RUN_ID>/trace.jsonl`, além de telemetry do profissional/paciente quando disponível.

`src/lib/agents/workflows.ts` executa fluxos compostos na prática:

- `ContextAgent` seleciona referências de profissional, paciente, sessão e artefatos.
- `PatientCareAgent`, `RiskCheckAgent`, `SessionPrepAgent` ou `LongitudinalReviewerAgent` chama agentes declarativos de paciente via `run_patient_agent`.
- `ToolRunnerAgent` executa estágios `process`, `speech`, `asl`, `vdlp` e `gem` por `npm run`.
- `SafetyReviewAgent` revisa respostas clínicas sensíveis antes da síntese final.

O `chat-cli` expõe `list_agent_definitions` e `run_agent_workflow` no MCP interno. `list_agent_definitions` omite o corpo dos prompts e retorna `has_prompt` para manter a resposta leve.

Memória persistente continua bloqueada por política explícita: somente `/remember texto` grava memória. Pedidos conversacionais de memória devem virar proposta ou confirmação, não escrita direta.
