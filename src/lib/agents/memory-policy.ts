export function isExplicitMemoryCommit(input: string): boolean {
  return /^\/remember\s+\S/i.test(input.trim());
}

export function memoryAgentInstruction(): string {
  return [
    "MemoryAgent grava memoria persistente somente quando o usuario usa /remember.",
    "Pedidos conversacionais como 'lembre disso' devem virar proposta ou pergunta de confirmacao, nunca escrita direta.",
    "Nao gravar PHI desnecessaria em memoria profissional.",
  ].join("\n");
}
