# LLM Chunking

## Decisão

O HealthOS usa chunking clínico adaptativo em `src/lib/llm/chunking.ts`.

Chunking aqui não é limite de output do modelo. É preparação de entrada para preservar contexto clínico quando uma transcrição, ASL ou VDLP fica grande demais para análise confiável em uma única chamada.

## Princípios

- Estrutura antes de tamanho: preservar turnos de fala, parágrafos, headings, listas e sentenças.
- Contexto clínico auditável: cada chunk pode carregar índice, range de caracteres, speakers, estimativa de tokens e overlap.
- Overlap intencional: análises interpretativas usam pequena janela de contexto; tarefas de reescrita/correção usam overlap zero para evitar duplicação.
- Sem dependência do modelo: ClaudeCode e Codex não expõem tokenizer/modelo antes da chamada, então a estimativa local é usada apenas para planejamento.
- Sem `max_tokens` hardcoded: limite de output fica a cargo do runtime/modelo.

## APIs

- `estimateTokens(text)`: estimativa determinística por caracteres.
- `splitIntoChunks(text, options)`: API compatível usada pelos pipelines atuais.
- `chunkClinicalText(text, options)`: API rica para próximos estágios, com metadados de proveniência.

## Presets atuais

- Processamento/correção de transcrição: `splitIntoChunks(text, number)` com overlap zero.
- ASL e VDLP: `mode: "clinical-transcript"`, preservação de turnos e overlap moderado.
- GEM: `mode: "clinical-transcript"`, chunks maiores e overlap maior por depender de eventos longitudinais.

## Próximos incrementos possíveis

- Avaliação automática de qualidade de chunk: integridade de bloco, coesão intra-chunk, completude de referências, conformidade de tamanho.
- Chunking por entidades clínicas quando houver NER local confiável.
- Parent-child retrieval: recuperar chunk pequeno com contexto pai maior quando houver índice vetorial.
