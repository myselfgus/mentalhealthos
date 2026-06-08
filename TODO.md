# TODO

## GUI

- A interface grafica foi abandonada por enquanto e removida dos entrypoints ativos.
- Se voltar, reconstruir a partir do contrato CLI/pipeline atual, sem reintroduzir caminhos `patients/`.

## LLM Runtime

- Os pipelines ativos nao importam `src/lib/api-client.ts` nem clientes especificos como `clientSonnet`, `clientOpus` ou `clientHaiku`.
- O client LLM canonico e `src/lib/llm/runtime.ts`.
- Runtimes ativos:
  - `ClaudeAPI`: Gateway/API legado.
  - `ClaudeCode`: subprocesso local Claude Code.
  - `Codex`: subprocesso local `codex exec`.
- `src/lib/api-client.ts` foi removido; o client canonico e `src/lib/llm/runtime.ts`.
- `src/lib/llm/runtime.ts` centraliza a chamada; providers ficam em `src/lib/llm/providers/`.
- O `chat-cli` agora deve manter dois caminhos de runtime:
  - `claude`: preservar Claude Code Agent SDK e tools HealthOS.
  - `codex`: usar subprocesso `codex exec` com auth/config local em `~/.codex`.
- Proximo passo de runtime: evoluir o contrato de chamadas estruturadas sobre `src/lib/llm/runtime.ts`.

## Chat CLI / Subagents

- Agentes HealthOS do projeto ficam em `src/agents/` e sao expostos ao chat-cli por `src/lib/llm/agents.ts`.
- Claude pode listar/delegar para subagentes Codex via tools MCP internas.
- Codex deve herdar login ChatGPT, profiles, MCPs, plugins, skills e agentes instalados; nao usar `OPENAI_API_KEY` para esse caminho local.
- A selecao manual deve continuar disponivel por `--runtime claude`, `--runtime codex`, `--claude`, `--codex` e comando interno `/runtime`.
- Melhorar depois persistencia conversacional do modo Codex com `codex exec resume` ou protocolo equivalente, se o CLI estabilizar esse uso.

## Profissionais

- Workspaces de profissionais ficam em `professionals/<professional-id>/`.
- Cada workspace contem `professional-config.json`, `memory.md`, `logs/`, `telemetry/`, `sessions/` e `artifacts/`.
- O `chat-cli` carrega memoria e config do profissional ativo antes de conversar com Claude/Codex.

## Contratos Atuais

- `patients/` e o diretorio canonico de dossies clinicos.
- `patient.json` e o contrato canonico de identidade, metadados, resumo clinico, sessoes e indice de artefatos.
- Analises de sessao ficam juntas em `patients/<PAT_ID>/sessions/<SESSION_ID>/analysis/`.
- `audio/` e o diretorio canonico de entrada/transcricoes brutas.
- Entry points versionados devem existir em `package.json` antes de aparecerem no menu ou README.
