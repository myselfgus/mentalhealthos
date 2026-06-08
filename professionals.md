# Professionals

## Decisão

O HealthOS usa `professionals/` como workspace dos profissionais configurados.

Cada profissional tem um diretório próprio com configuração, memória, logs, telemetria, sessões e artefatos. O sistema resolve um profissional ativo antes de carregar prompts, menu, chat-cli ou pipeline.

## Estrutura

```text
professionals/
├── active-professional.json
└── <professional-id>/
    ├── professional-config.json
    ├── memory.md
    ├── chat-agent.md
    ├── logs/
    ├── telemetry/
    ├── sessions/
    └── artifacts/
```

## Arquivos

- `active-professional.json`: ponte com o `active_professional_id`.
- `professional-config.json`: identidade profissional, registro e contexto de desambiguação.
- `memory.md`: memória carregada pelo `chat-cli` para contextualizar o LLM e os agentes.
- `chat-agent.md`: perfil conversacional do profissional, com papel, limites, estilo e política de memória.
- `logs/`: logs operacionais do profissional.
- `telemetry/`: eventos e telemetria futura por profissional.
- `sessions/`: histórico resumido de sessões do `chat-cli`.
- `artifacts/`: arquivos auxiliares gerados para o profissional.

## Seleção

O menu `healthos-psy` mostra o profissional ativo e permite criar, atualizar ou selecionar outro workspace profissional.

Também é possível fixar por ambiente:

```bash
HEALTHOS_PROFESSIONAL_ID=dr-gustavo-mendes-e-silva healthos-psy
```

## Chat CLI

Ao iniciar, o `chat-cli` carrega:

- configuração do profissional ativo;
- path do workspace profissional;
- conteúdo de `chat-agent.md`;
- conteúdo de `memory.md`.

O encerramento do chat registra um resumo operacional em `sessions/YYYY-MM-DD.md`.

Memórias persistentes não são inferidas automaticamente. O usuário precisa pedir explicitamente, por exemplo com `/remember texto`.
