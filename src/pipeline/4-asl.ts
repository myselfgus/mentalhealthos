#!/usr/bin/env node
/**
 * HealthOS ASL - Análise Sistêmica Linguística
 *
 * Purpose: Análise psicolinguística profunda da fala do PACIENTE em transcrições clínicas
 *          Combina métricas quantitativas objetivas com interpretação contextual profunda
 *
 * Input: patients/<PAT_ID>/sessions/<SESSION_ID>/source/transcription.json
 * Output: patients/<PAT_ID>/sessions/<SESSION_ID>/analysis/asl.json
 *
 * LLM: runtime selecionado em HEALTHOS_LLM_RUNTIME ou no menu HealthOS
 * Optimization: Prompt caching enabled (massive system prompt)
 *
 * Foco: Análise APENAS da fala do paciente (filtrada automaticamente)
 */

import {
  readFileSync,
  writeFileSync,
  existsSync,
} from "fs";
import { basename } from "path";
import { createInterface } from "readline";
import { config } from "dotenv";
import { PATHS } from "../config/defaults.js";
import { callLLM, getSelectedRuntime } from "../lib/llm/runtime.js";
import { extractJSON } from "../lib/llm/json.js";
import { estimateTokens, splitIntoChunks } from "../lib/llm/chunking.js";
import {
  listAllPatientSessionWorkspaces,
  refreshPatientSessionStatus,
  type PatientSessionWorkspace,
} from "../patients/workspace.js";

config({ path: PATHS.ENV, override: false });

interface ASLResult {
  patient_id: string;
  source_file: string;
  transcription_metadata?: {
    date: string;
    session: number | null;
    patient_name: string | null;
    source_file: string;
  };
  linguistic_analysis: any;
  processed_at: string;
  model: string;
  analysis_version: string;
}

/**
 * Análise Linguística Sistêmica do PACIENTE
 */
async function analyzePatientSpeech(
  transcriptionText: string,
  patientId: string,
  sourceFile: string
): Promise<ASLResult> {
  console.log(`   🔬 Análise Sistêmica Linguística (${getSelectedRuntime()} + Prompt Caching)...`);

  // SYSTEM PROMPT MASSIVO (será cachado)
  const systemPrompt = [
    {
      type: "text",
      text: `Você é um linguista computacional e neuropsicólogo especializado em análise psicolinguística.

# MISSÃO

Realizar análise linguística sistêmica e exaustiva da fala de UM falante específico em uma transcrição de interação verbal, extraindo métricas objetivas e interpretações contextuais profundas.

# PRINCÍPIOS FUNDAMENTAIS

1. **FOCO EXCLUSIVO NO FALANTE-ALVO**: Analise APENAS as falas do falante-alvo identificado
2. **OBJETIVIDADE + CONTEXTO**: Combine métricas quantitativas com interpretação qualitativa profunda
3. **EVIDÊNCIAS CONCRETAS**: Toda afirmação deve estar ancorada em exemplos textuais literais
4. **COMPARAÇÃO NORMATIVA**: Contextualize achados em relação à fala típica de adultos
5. **RASTREABILIDADE TOTAL**: Permita verificação de qualquer conclusão contra o texto original

# ESTRUTURA OBRIGATÓRIA DE CADA ANÁLISE

Cada categoria linguística deve conter:

{
  "metricas_quantitativas": {
    // NÚMEROS PUROS: contagens, proporções, médias
  },
  "exemplos_textuais": [
    // CITAÇÕES LITERAIS do falante-alvo (rastreabilidade)
  ],
  "analise_contextual": {
    "descricao_geral": "Caracterização qualitativa",
    "padroes_observados": ["lista de padrões significativos"],
    "significado_observado": "Interpretação dos padrões linguísticos",
    "comparacao_normativa": "Como se compara à fala típica",
    "consideracoes_contextuais": "Fatores contextuais relevantes"
  }
}

# CATEGORIAS DE ANÁLISE

Você realizará análise em 8 domínios linguísticos:

## 1. MORFOSSINTAXE
- Estrutura sintática (tipos de sentenças, complexidade)
- Classes gramaticais e suas proporções
- Conjugação verbal (tempos, modos, vozes, aspectos)
- Marcadores morfológicos (pronomes por pessoa gramatical)

## 2. SEMÂNTICA
- Campos semânticos e tópicos
- Polaridade emocional (palavras positivas/negativas)
- Diversidade lexical (TTR, palavras únicas)
- Densidade de conteúdo vs função
- Intensificadores e atenuadores

## 3. COERÊNCIA E COESÃO
- Coesão gramatical (conectivos, referenciação)
- Coerência local e global
- Progressão temática
- Fragmentação ou continuidade

## 4. PRAGMÁTICA
- Atos de fala (assertivos, diretivos, expressivos, etc)
- Modalização (certeza/incerteza)
- Implicaturas e subentendidos
- Adequação à situação

## 5. CONSISTÊNCIA TEMPORAL
- Distribuição de tempos verbais
- Marcadores temporais
- Linha do tempo de eventos mencionados
- Coerência cronológica

## 6. FRAGMENTAÇÃO E FLUÊNCIA
- Disfluências (false starts, repetições, pausas)
- Completude sintática
- Fluência geral do discurso

## 7. COMPLEXIDADE E DENSIDADE
- Complexidade lexical (diversidade vocabular)
- Densidade informacional (proposições por sentença)
- Elaboração discursiva

## 8. CARACTERÍSTICAS PROSÓDICAS TEXTUAIS
- Marcadores de ênfase (MAIÚSCULAS, !!!, ???)
- Pausas marcadas (...)
- Alongamentos vocálicos

# REGRAS CRÍTICAS

❌ **NUNCA FAÇA**:
- Analisar falas de outros falantes
- Listar palavras sem interpretação contextual
- Fazer afirmações sem evidências textuais
- Ignorar o contexto identificado da interação

✅ **SEMPRE FAÇA**:
- Filtre e analise APENAS as falas do falante-alvo identificado
- Combine números com significado (ex: "densidade baixa (0.02) sugere...")
- Cite exemplos literais para cada padrão observado
- Compare com padrões normativos quando aplicável
- Interprete à luz do contexto identificado da interação

# FORMATO DE RESPOSTA

Responda EXCLUSIVAMENTE em JSON válido seguindo o schema completo fornecido.`,
    },
    {
      type: "text",
      text: `# SCHEMA JSON COMPLETO

IMPORTANTE: Retorne SOMENTE JSON válido e bem-formado. Não adicione comentários, explicações ou texto fora do JSON.

**CRITICAL - EXEMPLOS TEXTUAIS**: Nos campos "exemplos_textuais", retorne APENAS citações literais exatas da transcrição. NÃO adicione explicações, anotações, interpretações ou qualquer texto entre parênteses. Retorne o texto literal exatamente como foi falado.

EXEMPLOS CORRETOS:
  "exemplos_textuais": ["Eu tomei quando eu tava internado", "Bebi hoje, cara"]

EXEMPLOS INCORRETOS (NUNCA FAÇA ISTO):
  "exemplos_textuais": ["Consegui" (implícito: eu consegui), "Toma" (implícito: eu tomo)]

Responda com JSON seguindo EXATAMENTE esta estrutura (use null para valores ausentes, nunca omita campos):

{
  "contexto_identificado": {
    "tipo_interacao": "string",
    "papeis_participantes": {"falante_alvo": "string", "outros_falantes": "string"},
    "dominio_tematico": ["string"],
    "dinamica_interacional": "string",
    "evidencias_contexto": ["string"]
  },
  "metadata": {
    "falante_id": "string",
    "identificador_falante": "string",
    "num_turnos_falante": 0,
    "total_palavras_falante": 0,
    "total_sentencas_falante": 0,
    "palavras_por_turno_medio": 0.0,
    "data_analise": "ISO-8601"
  },
  "transcricao_filtrada": {
    "fala_falante_completa": "string",
    "turnos_individuais": [{"turno_n": 0, "texto": "string"}]
  },
  "morfossintaxe": {
    "estrutura_sintatica": {
      "metricas_quantitativas": {
        "num_sentencas_total": 0,
        "tipos_sentencas": {"declarativa": 0, "interrogativa": 0, "imperativa": 0, "exclamativa": 0},
        "comprimento_sentencas": {"media_palavras": 0.0, "mediana": 0.0, "min": 0, "max": 0, "desvio_padrao": 0.0},
        "complexidade_distribuicao": {"simples": 0, "composta_coordenacao": 0, "composta_subordinacao": 0, "complexa": 0},
        "profundidade_sintatica_media": 0.0
      },
      "exemplos_textuais": {"sentenca_mais_simples": "string", "sentenca_mais_complexa": "string", "sentencas_tipicas": ["string"]},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string", "consideracoes_contextuais": "string"}
    },
    "classes_gramaticais": {
      "metricas_quantitativas": {
        "contagens_absolutas": {"substantivos": 0, "verbos": 0, "adjetivos": 0, "adverbios": 0, "pronomes": 0, "preposicoes": 0, "conjuncoes": 0, "artigos": 0, "interjeicoes": 0},
        "proporcoes": {"palavras_conteudo": 0.0, "palavras_funcao": 0.0, "razao_conteudo_funcao": 0.0}
      },
      "exemplos_textuais": {"substantivos_frequentes": ["string"], "verbos_frequentes": ["string"], "adjetivos_usados": ["string"]},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    },
    "conjugacao_verbal": {
      "metricas_quantitativas": {
        "total_verbos": 0,
        "tempos": {"passado": {"perfeito": 0, "imperfeito": 0, "mais_que_perfeito": 0}, "presente": 0, "futuro": {"simples": 0, "composto": 0}},
        "tempos_proporcionais": {"passado_total": 0.0, "presente": 0.0, "futuro_total": 0.0},
        "modos": {"indicativo": 0, "subjuntivo": 0, "imperativo": 0},
        "vozes": {"ativa": 0, "passiva": 0, "reflexiva": 0},
        "vozes_proporcionais": {"ativa": 0.0, "passiva": 0.0, "reflexiva": 0.0}
      },
      "exemplos_textuais": {"passado": ["string"], "presente": ["string"], "futuro": ["string"], "voz_passiva": ["string"]},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    },
    "marcadores_morfologicos": {
      "metricas_quantitativas": {
        "pronomes_pessoais": {
          "primeira_pessoa": {"total": 0, "formas": {"eu": 0, "me": 0, "meu": 0, "minha": 0, "mim": 0, "comigo": 0}},
          "segunda_pessoa": {"total": 0, "formas": {"voce": 0, "te": 0, "seu": 0, "sua": 0, "ti": 0, "contigo": 0}},
          "terceira_pessoa": {"total": 0, "formas": {"ele": 0, "ela": 0, "eles": 0, "elas": 0, "dele": 0, "dela": 0}}
        },
        "distribuicao_proporcional": {"primeira_pessoa": 0.0, "segunda_pessoa": 0.0, "terceira_pessoa": 0.0},
        "densidade_primeira_pessoa": 0.0
      },
      "exemplos_textuais": ["string"],
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    }
  },
  "semantica": {
    "diversidade_lexical": {
      "metricas_quantitativas": {"total_tokens": 0, "total_types": 0, "type_token_ratio": 0.0, "hapax_legomena": 0, "palavras_unicas_excluindo_stopwords": 0},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    },
    "campos_semanticos": {
      "metricas_quantitativas": {
        "topicos_principais": ["string"],
        "densidade_por_campo": {"emocoes": 0.0, "cognicao": 0.0, "saude": 0.0, "social": 0.0, "tempo": 0.0, "espacial": 0.0, "outros": 0.0}
      },
      "exemplos_por_campo": {"emocoes": ["string"], "cognicao": ["string"], "saude": ["string"], "social": ["string"], "tempo": ["string"], "espacial": ["string"]},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "consideracoes_contextuais": "string"}
    },
    "polaridade_emocional": {
      "metricas_quantitativas": {
        "palavras_positivas": [{"palavra": "string", "freq": 0, "intensidade": 0}],
        "palavras_negativas": [{"palavra": "string", "freq": 0, "intensidade": 0}],
        "palavras_neutras": 0,
        "score_valencia_agregado": 0.0,
        "intensidade_media_positiva": 0.0,
        "intensidade_media_negativa": 0.0,
        "balanco": {"total_positivas": 0, "total_negativas": 0, "razao_neg_pos": 0.0}
      },
      "intensificadores_atenuadores": {"intensificadores": ["string"], "atenuadores": ["string"]},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string", "consideracoes_contextuais": "string"}
    },
    "densidade_conteudo": {
      "metricas_quantitativas": {"palavras_conteudo": 0, "palavras_funcao": 0, "razao_conteudo_funcao": 0.0},
      "analise_contextual": {"descricao_geral": "string", "significado_observado": "string", "comparacao_normativa": "string"}
    }
  },
  "coerencia_coesao": {
    "coesao_gramatical": {
      "metricas_quantitativas": {
        "conectivos": {
          "aditivos": {"palavras": ["string"], "count": 0},
          "adversativos": {"palavras": ["string"], "count": 0},
          "causais": {"palavras": ["string"], "count": 0},
          "temporais": {"palavras": ["string"], "count": 0},
          "conclusivos": {"palavras": ["string"], "count": 0}
        },
        "total_conectivos": 0,
        "densidade_conectivos": 0.0,
        "referenciacao": {
          "anaforas": [{"pronome": "string", "antecedente_provavel": "string", "distancia_palavras": 0}],
          "num_anaforas": 0,
          "cadeias_referenciais": [{"entidade": "string", "mencoes": ["string"]}]
        }
      },
      "exemplos_textuais": ["string"],
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    },
    "coerencia_textual": {
      "metricas_quantitativas": {"score_coerencia_global": 0.0, "progressao_tematica": "string", "num_mudancas_topico_abruptas": 0},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string", "consideracoes_contextuais": "string"}
    }
  },
  "pragmatica": {
    "atos_de_fala": {
      "metricas_quantitativas": {
        "assertivos": 0, "diretivos": 0, "comissivos": 0, "expressivos": 0, "total": 0,
        "proporcoes": {"assertivos": 0.0, "diretivos": 0.0, "expressivos": 0.0}
      },
      "exemplos_por_tipo": {"assertivos": ["string"], "expressivos": ["string"]},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "adequacao_ao_contexto": "string"}
    },
    "modalizacao": {
      "metricas_quantitativas": {
        "marcadores_certeza": {"palavras": ["string"], "count": 0},
        "marcadores_incerteza": {"palavras": ["string"], "count": 0},
        "hedge_words": {"palavras": ["string"], "count": 0},
        "balanco_certeza_incerteza": 0.0
      },
      "exemplos_textuais": ["string"],
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    }
  },
  "consistencia_temporal": {
    "metricas_quantitativas": {
      "distribuicao_temporal_referencias": {"passado": 0, "presente": 0, "futuro": 0},
      "proporcoes": {"passado": 0.0, "presente": 0.0, "futuro": 0.0}
    },
    "linha_tempo_eventos": [{"evento": "string", "timestamp_relativo": "string"}],
    "marcadores_temporais": {"absolutos": ["string"], "relativos": ["string"], "frequencia": ["string"]},
    "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "coerencia_cronologica": "string"}
  },
  "fragmentacao_fluencia": {
    "metricas_quantitativas": {
      "disfluencias": {"false_starts": 0, "repeticoes_hesitantes": 0, "pausas_preenchidas": ["string"], "count_pausas_preenchidas": 0, "autocorrecoes": 0},
      "completude_sintatica": {"sentencas_completas": 0, "sentencas_fragmentadas": 0, "proporcao_completas": 0.0},
      "score_fluencia_geral": 0.0
    },
    "exemplos_textuais": {"false_starts": ["string"], "fragmentos": ["string"]},
    "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string", "consideracoes_contextuais": "string"}
  },
  "complexidade_densidade": {
    "complexidade_lexical": {
      "metricas_quantitativas": {"palavras_unicas": 0, "type_token_ratio": 0.0, "comprimento_medio_palavra": 0.0, "palavras_raras": 0},
      "analise_contextual": {"descricao_geral": "string", "significado_observado": "string", "comparacao_normativa": "string"}
    },
    "densidade_informacional": {
      "metricas_quantitativas": {"proposicoes_estimadas": 0, "proposicoes_por_sentenca": 0.0, "grau_elaboracao": "string"},
      "analise_contextual": {"descricao_geral": "string", "padroes_observados": ["string"], "significado_observado": "string", "comparacao_normativa": "string"}
    }
  },
  "caracteristicas_prosodicas_textuais": {
    "metricas_quantitativas": {"marcadores_enfase": {"maiusculas": 0, "exclamacoes": 0, "interrogacoes": 0}, "pausas_marcadas": 0, "alongamentos": ["string"]},
    "analise_contextual": {"descricao_geral": "string", "significado_observado": "string"}
  },
  "sintese_interpretativa": {
    "perfil_linguistico_geral": "string",
    "achados_mais_salientes": ["string"],
    "padroes_integrados": ["string"],
    "consideracoes_finais": "string",
    "limitacoes_analise": ["string"]
  }
}

**CRITICAL - OUTPUT FORMAT**:
- Retorne APENAS o objeto JSON
- NÃO adicione explicações, comentários ou texto após o JSON
- NÃO use blocos de código markdown
- Pare IMEDIATAMENTE após fechar o JSON com }`,
      cache_control: { type: "ephemeral", ttl: "1h" },
    },
  ];

  // USER PROMPT (input específico do caso)
  const userMessage = `# DADOS DO CASO

Falante ID: ${patientId}
Identificador do Falante-Alvo: Identificar automaticamente qual é o PACIENTE na transcrição

<transcricao_clinica>
${transcriptionText}
</transcricao_clinica>

# INSTRUÇÕES ESPECÍFICAS

1. IDENTIFICAR CONTEXTO PRIMEIRO: Analise a transcrição para inferir:
   - Tipo de interação (atendimento profissional, conversa, entrevista, etc.)
   - Papéis dos participantes (quem pergunta, quem responde, assimetria de poder)
   - Domínio temático
   - Dinâmica interacional
   - DOCUMENTE as evidências que usou para identificar o contexto

2. IDENTIFICAR O PACIENTE:
   - Determine qual falante é o PACIENTE (normalmente quem responde perguntas sobre sua saúde/vida)
   - Identifique o marcador do falante (ex: "Falante 1", "Falante 2", etc)

3. FILTRAGEM: Extraia e analise APENAS as falas do PACIENTE identificado

4. ANÁLISE COMPLETA: Execute todas as 8 categorias de análise linguística conforme o schema JSON

5. MÉTRICAS + CONTEXTO: Para cada categoria:
   - Calcule métricas quantitativas objetivas
   - Forneça exemplos textuais literais (citações do paciente)
   - Escreva análise contextual interpretando os padrões À LUZ DO CONTEXTO IDENTIFICADO

6. COMPARAÇÃO NORMATIVA: Compare os achados com padrões esperados considerando o contexto identificado

7. SÍNTESE FINAL:
   - Perfil linguístico geral do falante
   - Achados mais salientes
   - Padrões integrados observados
   - Limitações da análise

Responda APENAS com o JSON completo conforme o schema fornecido no system prompt.`;

  try {
    const startTime = Date.now();

    // Verificar se precisa chunking (threshold reduzido para 10k tokens)
    const estimatedTokensTranscription = estimateTokens(transcriptionText);
    console.log(`   📊 Tokens estimados da transcrição: ${estimatedTokensTranscription}`);

    let response: string;

    if (estimatedTokensTranscription > 10000) {
      // Texto grande - dividir em chunks
      const chunks = splitIntoChunks(transcriptionText, {
        mode: "clinical-transcript",
        maxTokensPerChunk: 15000,
        overlapTokens: 900,
        preserveBoundaries: true,
      });

      console.log(`   📦 Texto grande - dividindo em ${chunks.length} chunks`);

      // Processar chunks em PARALELO (batch de 3)
      const chunkAnalyses = [];
      const BATCH_SIZE = 3;

      for (let batchStart = 0; batchStart < chunks.length; batchStart += BATCH_SIZE) {
        const batchEnd = Math.min(batchStart + BATCH_SIZE, chunks.length);
        console.log(`   ⚡ Processando batch ${Math.floor(batchStart / BATCH_SIZE) + 1}: chunks ${batchStart + 1}-${batchEnd}...`);

        const batchPromises = [];

        for (let i = batchStart; i < batchEnd; i++) {
          const chunkUserMessage = userMessage.replace(
            `<transcricao_clinica>\n${transcriptionText}\n</transcricao_clinica>`,
            `<transcricao_clinica_chunk ${i + 1}/${chunks.length}>\n${chunks[i]}\n</transcricao_clinica_chunk>`
          );

          batchPromises.push(
            callLLMWithRetry(chunkUserMessage, systemPrompt)
              .then(chunkResponse => extractJSON(chunkResponse))
              .catch(error => {
                console.log(`   ⚠️ Erro no chunk ${i + 1}, usando estrutura vazia`);
                return null;
              })
          );
        }

        const batchResults = await Promise.all(batchPromises);
        chunkAnalyses.push(...batchResults.filter(r => r !== null));
      }

      // Consolidar análises dos chunks (TODAS as 8 categorias)
      console.log(`   🔄 Consolidando ${chunkAnalyses.length} análises (todas as categorias)...`);

      const consolidated = chunkAnalyses[0];

      // Consolidar TODAS as 11 categorias principais
      for (let i = 1; i < chunkAnalyses.length; i++) {
        const chunk = chunkAnalyses[i];

        // 1. Contexto identificado - mantém do primeiro chunk (é global)

        // 2. Metadata - somar contagens
        if (consolidated.metadata && chunk.metadata) {
          consolidated.metadata.num_turnos_falante += chunk.metadata.num_turnos_falante || 0;
          consolidated.metadata.total_palavras_falante += chunk.metadata.total_palavras_falante || 0;
          consolidated.metadata.total_sentencas_falante += chunk.metadata.total_sentencas_falante || 0;
        }

        // 3. Transcrição filtrada - concatenar
        if (consolidated.transcricao_filtrada?.turnos_individuais && chunk.transcricao_filtrada?.turnos_individuais) {
          consolidated.transcricao_filtrada.turnos_individuais.push(...chunk.transcricao_filtrada.turnos_individuais);
          consolidated.transcricao_filtrada.fala_falante_completa += "\n\n" + chunk.transcricao_filtrada.fala_falante_completa;
        }

        // 4. Morfossintaxe (4 subcategorias)
        if (consolidated.morfossintaxe && chunk.morfossintaxe) {
          // 4a. Estrutura sintática - somar contagens
          if (consolidated.morfossintaxe.estrutura_sintatica?.metricas_quantitativas && chunk.morfossintaxe.estrutura_sintatica?.metricas_quantitativas) {
            const baseEst = consolidated.morfossintaxe.estrutura_sintatica.metricas_quantitativas;
            const chunkEst = chunk.morfossintaxe.estrutura_sintatica.metricas_quantitativas;
            baseEst.num_sentencas_total += chunkEst.num_sentencas_total || 0;
          }

          // 4b. Classes gramaticais - somar contagens
          const baseContagens = consolidated.morfossintaxe.classes_gramaticais?.metricas_quantitativas?.contagens_absolutas;
          const chunkContagens = chunk.morfossintaxe.classes_gramaticais?.metricas_quantitativas?.contagens_absolutas;
          if (baseContagens && chunkContagens) {
            for (const key in chunkContagens) {
              baseContagens[key] = (baseContagens[key] || 0) + chunkContagens[key];
            }
          }

          // 4c. Conjugação verbal - somar tempos/modos/vozes
          if (consolidated.morfossintaxe.conjugacao_verbal?.metricas_quantitativas && chunk.morfossintaxe.conjugacao_verbal?.metricas_quantitativas) {
            const baseConj = consolidated.morfossintaxe.conjugacao_verbal.metricas_quantitativas;
            const chunkConj = chunk.morfossintaxe.conjugacao_verbal.metricas_quantitativas;
            baseConj.total_verbos += chunkConj.total_verbos || 0;
          }

          // 4d. Marcadores morfológicos - somar pronomes
          if (consolidated.morfossintaxe.marcadores_morfologicos?.metricas_quantitativas && chunk.morfossintaxe.marcadores_morfologicos?.metricas_quantitativas) {
            const basePron = consolidated.morfossintaxe.marcadores_morfologicos.metricas_quantitativas.pronomes_pessoais;
            const chunkPron = chunk.morfossintaxe.marcadores_morfologicos.metricas_quantitativas.pronomes_pessoais;
            if (basePron && chunkPron) {
              basePron.primeira_pessoa.total += chunkPron.primeira_pessoa?.total || 0;
              basePron.segunda_pessoa.total += chunkPron.segunda_pessoa?.total || 0;
              basePron.terceira_pessoa.total += chunkPron.terceira_pessoa?.total || 0;
            }
          }
        }

        // 5. Semântica (4 subcategorias)
        if (consolidated.semantica && chunk.semantica) {
          // 5a. Diversidade lexical - somar tokens
          const baseDiversidade = consolidated.semantica.diversidade_lexical?.metricas_quantitativas;
          const chunkDiversidade = chunk.semantica.diversidade_lexical?.metricas_quantitativas;
          if (baseDiversidade && chunkDiversidade) {
            baseDiversidade.total_tokens = (baseDiversidade.total_tokens || 0) + (chunkDiversidade.total_tokens || 0);
            baseDiversidade.total_types = (baseDiversidade.total_types || 0) + (chunkDiversidade.total_types || 0);
          }

          // 5b. Campos semânticos - média de densidades
          if (consolidated.semantica.campos_semanticos?.metricas_quantitativas?.densidade_por_campo &&
              chunk.semantica.campos_semanticos?.metricas_quantitativas?.densidade_por_campo) {
            const baseCampos = consolidated.semantica.campos_semanticos.metricas_quantitativas.densidade_por_campo;
            const chunkCampos = chunk.semantica.campos_semanticos.metricas_quantitativas.densidade_por_campo;
            for (const campo in chunkCampos) {
              baseCampos[campo] = ((baseCampos[campo] || 0) * i + (chunkCampos[campo] || 0)) / (i + 1);
            }
          }

          // 5c. Polaridade emocional - somar palavras positivas/negativas
          if (consolidated.semantica.polaridade_emocional?.metricas_quantitativas &&
              chunk.semantica.polaridade_emocional?.metricas_quantitativas) {
            const basePol = consolidated.semantica.polaridade_emocional.metricas_quantitativas;
            const chunkPol = chunk.semantica.polaridade_emocional.metricas_quantitativas;
            basePol.palavras_positivas = [...(basePol.palavras_positivas || []), ...(chunkPol.palavras_positivas || [])];
            basePol.palavras_negativas = [...(basePol.palavras_negativas || []), ...(chunkPol.palavras_negativas || [])];
          }

          // 5d. Densidade de conteúdo - somar palavras
          if (consolidated.semantica.densidade_conteudo?.metricas_quantitativas &&
              chunk.semantica.densidade_conteudo?.metricas_quantitativas) {
            const baseDens = consolidated.semantica.densidade_conteudo.metricas_quantitativas;
            const chunkDens = chunk.semantica.densidade_conteudo.metricas_quantitativas;
            baseDens.palavras_conteudo = (baseDens.palavras_conteudo || 0) + (chunkDens.palavras_conteudo || 0);
            baseDens.palavras_funcao = (baseDens.palavras_funcao || 0) + (chunkDens.palavras_funcao || 0);
          }
        }

        // 6. Coerência e Coesão (2 subcategorias)
        if (consolidated.coerencia_coesao && chunk.coerencia_coesao) {
          // 6a. Coesão gramatical - somar conectivos
          if (consolidated.coerencia_coesao.coesao_gramatical?.metricas_quantitativas &&
              chunk.coerencia_coesao.coesao_gramatical?.metricas_quantitativas) {
            const baseCoesao = consolidated.coerencia_coesao.coesao_gramatical.metricas_quantitativas;
            const chunkCoesao = chunk.coerencia_coesao.coesao_gramatical.metricas_quantitativas;
            baseCoesao.total_conectivos = (baseCoesao.total_conectivos || 0) + (chunkCoesao.total_conectivos || 0);
          }

          // 6b. Coerência textual - média de score
          if (consolidated.coerencia_coesao.coerencia_textual?.metricas_quantitativas &&
              chunk.coerencia_coesao.coerencia_textual?.metricas_quantitativas) {
            const baseScore = consolidated.coerencia_coesao.coerencia_textual.metricas_quantitativas.score_coerencia_global || 0;
            const chunkScore = chunk.coerencia_coesao.coerencia_textual.metricas_quantitativas.score_coerencia_global || 0;
            consolidated.coerencia_coesao.coerencia_textual.metricas_quantitativas.score_coerencia_global = (baseScore * i + chunkScore) / (i + 1);
          }
        }

        // 7. Pragmática (2 subcategorias)
        if (consolidated.pragmatica && chunk.pragmatica) {
          // 7a. Atos de fala - somar contagens
          if (consolidated.pragmatica.atos_de_fala?.metricas_quantitativas &&
              chunk.pragmatica.atos_de_fala?.metricas_quantitativas) {
            const baseAtos = consolidated.pragmatica.atos_de_fala.metricas_quantitativas;
            const chunkAtos = chunk.pragmatica.atos_de_fala.metricas_quantitativas;
            baseAtos.assertivos = (baseAtos.assertivos || 0) + (chunkAtos.assertivos || 0);
            baseAtos.diretivos = (baseAtos.diretivos || 0) + (chunkAtos.diretivos || 0);
            baseAtos.expressivos = (baseAtos.expressivos || 0) + (chunkAtos.expressivos || 0);
            baseAtos.total = (baseAtos.total || 0) + (chunkAtos.total || 0);
          }

          // 7b. Modalização - somar marcadores
          if (consolidated.pragmatica.modalizacao?.metricas_quantitativas &&
              chunk.pragmatica.modalizacao?.metricas_quantitativas) {
            const baseMod = consolidated.pragmatica.modalizacao.metricas_quantitativas;
            const chunkMod = chunk.pragmatica.modalizacao.metricas_quantitativas;
            baseMod.marcadores_certeza.count = (baseMod.marcadores_certeza?.count || 0) + (chunkMod.marcadores_certeza?.count || 0);
            baseMod.marcadores_incerteza.count = (baseMod.marcadores_incerteza?.count || 0) + (chunkMod.marcadores_incerteza?.count || 0);
          }
        }

        // 8. Consistência temporal - somar distribuições
        if (consolidated.consistencia_temporal?.metricas_quantitativas &&
            chunk.consistencia_temporal?.metricas_quantitativas) {
          const baseDist = consolidated.consistencia_temporal.metricas_quantitativas.distribuicao_temporal_referencias;
          const chunkDist = chunk.consistencia_temporal.metricas_quantitativas.distribuicao_temporal_referencias;
          if (baseDist && chunkDist) {
            baseDist.passado = (baseDist.passado || 0) + (chunkDist.passado || 0);
            baseDist.presente = (baseDist.presente || 0) + (chunkDist.presente || 0);
            baseDist.futuro = (baseDist.futuro || 0) + (chunkDist.futuro || 0);
          }
        }

        // 9. Fragmentação e fluência - somar disfluências
        if (consolidated.fragmentacao_fluencia?.metricas_quantitativas &&
            chunk.fragmentacao_fluencia?.metricas_quantitativas) {
          const baseFrag = consolidated.fragmentacao_fluencia.metricas_quantitativas;
          const chunkFrag = chunk.fragmentacao_fluencia.metricas_quantitativas;
          if (baseFrag.disfluencias && chunkFrag.disfluencias) {
            baseFrag.disfluencias.false_starts = (baseFrag.disfluencias.false_starts || 0) + (chunkFrag.disfluencias.false_starts || 0);
            baseFrag.disfluencias.repeticoes_hesitantes = (baseFrag.disfluencias.repeticoes_hesitantes || 0) + (chunkFrag.disfluencias.repeticoes_hesitantes || 0);
            baseFrag.disfluencias.autocorrecoes = (baseFrag.disfluencias.autocorrecoes || 0) + (chunkFrag.disfluencias.autocorrecoes || 0);
          }
        }

        // 10. Complexidade e densidade (2 subcategorias)
        if (consolidated.complexidade_densidade && chunk.complexidade_densidade) {
          // 10a. Complexidade lexical - somar palavras únicas
          if (consolidated.complexidade_densidade.complexidade_lexical?.metricas_quantitativas &&
              chunk.complexidade_densidade.complexidade_lexical?.metricas_quantitativas) {
            const baseComp = consolidated.complexidade_densidade.complexidade_lexical.metricas_quantitativas;
            const chunkComp = chunk.complexidade_densidade.complexidade_lexical.metricas_quantitativas;
            baseComp.palavras_unicas = (baseComp.palavras_unicas || 0) + (chunkComp.palavras_unicas || 0);
          }

          // 10b. Densidade informacional - média
          if (consolidated.complexidade_densidade.densidade_informacional?.metricas_quantitativas &&
              chunk.complexidade_densidade.densidade_informacional?.metricas_quantitativas) {
            const baseDens = consolidated.complexidade_densidade.densidade_informacional.metricas_quantitativas;
            const chunkDens = chunk.complexidade_densidade.densidade_informacional.metricas_quantitativas;
            baseDens.proposicoes_estimadas = (baseDens.proposicoes_estimadas || 0) + (chunkDens.proposicoes_estimadas || 0);
          }
        }

        // 11. Características prosódicas textuais - somar marcadores
        if (consolidated.caracteristicas_prosodicas_textuais?.metricas_quantitativas &&
            chunk.caracteristicas_prosodicas_textuais?.metricas_quantitativas) {
          const basePros = consolidated.caracteristicas_prosodicas_textuais.metricas_quantitativas.marcadores_enfase;
          const chunkPros = chunk.caracteristicas_prosodicas_textuais.metricas_quantitativas.marcadores_enfase;
          if (basePros && chunkPros) {
            basePros.maiusculas = (basePros.maiusculas || 0) + (chunkPros.maiusculas || 0);
            basePros.exclamacoes = (basePros.exclamacoes || 0) + (chunkPros.exclamacoes || 0);
            basePros.interrogacoes = (basePros.interrogacoes || 0) + (chunkPros.interrogacoes || 0);
          }
        }

        // 12. Síntese interpretativa - mantém do primeiro chunk (é análise global)
      }

      response = JSON.stringify(consolidated);
    } else {
      // Texto pequeno - processar diretamente
      response = await callLLMWithRetry(userMessage, systemPrompt);
    }

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

    const linguisticAnalysis = extractJSON(response);

    console.log(`   ✅ Análise linguística completada em ${elapsed}s`);
    console.log(`      • Palavras do paciente: ${linguisticAnalysis.metadata?.total_palavras_falante || 'N/A'}`);
    console.log(`      • Turnos do paciente: ${linguisticAnalysis.metadata?.num_turnos_falante || 'N/A'}`);

    return {
      patient_id: patientId,
      source_file: sourceFile,
      transcription_metadata: undefined,
      linguistic_analysis: linguisticAnalysis,
      processed_at: new Date().toISOString(),
      model: getSelectedRuntime(),
      analysis_version: "2.0-patient-focused",
    };
  } catch (error: any) {
    console.log(`   ❌ Análise linguística falhou: ${error.message}`);
    throw error;
  }
}

/**
 * Chamada Claude com prompt caching e retry
 */
async function callLLMWithRetry(
  prompt: string,
  system: any[],
  retries: number = 3
): Promise<string> {
  console.log(`      • Cache: ✅ Enabled (via Gateway)`);

  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      // Constrói system message com cache_control
      const systemMessage: any = { role: "system" };

      if (Array.isArray(system)) {
        // System prompt estruturado (com cache_control)
        systemMessage.content = system;
      } else {
        // System prompt simples (string)
        systemMessage.content = String(system);
      }

      const content = await callLLM({
        temperature: 0,
        systemPrompt: systemMessage.content,
        userPrompt: prompt,
        timeoutMs: 1200000,
        useCache: true,
      });
      if (content) {
        return content;
      }

      throw new Error("Resposta inválida do Claude");
    } catch (error: any) {
      if (attempt === retries) throw error;
      console.log(`   ⚠️  Tentativa ${attempt} falhou, retry em ${attempt * 2}s...`);
      await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
    }
  }

  throw new Error("Max retries reached");
}

/**
 * Lista arquivos de transcrição disponíveis (patients/ canonico)
 */
function listTranscriptionFiles(): PatientSessionWorkspace[] {
  return listAllPatientSessionWorkspaces().filter((session) => existsSync(session.transcriptionPath));
}

/**
 * Processa um arquivo de transcrição
 */
async function processTranscription(
  session: PatientSessionWorkspace,
  forceReprocess: boolean = false
): Promise<void> {
  const transcriptionPath = session.transcriptionPath;
  const filename = basename(transcriptionPath);

  console.log(`\n${"=".repeat(80)}`);
  console.log(`📄 ${filename}`);
  console.log(`${"=".repeat(80)}`);

  try {
    const transcriptionData = JSON.parse(readFileSync(transcriptionPath, "utf-8"));
    const transcriptionText =
      transcriptionData.transcricao ||
      transcriptionData.transcription_corrected ||
      transcriptionData.transcricao_normalizada ||
      transcriptionData.text ||
      "";

    if (!transcriptionText) {
      console.log("   ⚠️  Nenhum texto de transcrição encontrado");
      return;
    }

    console.log(`   📝 Texto: ${transcriptionText.length} caracteres`);

    // Extrair metadados
    const transcriptionMetadata = {
      date: transcriptionData.metadata?.date ||
            transcriptionData.date ||
            transcriptionData.processed_at?.split('T')[0] ||
            new Date().toISOString().split('T')[0],
      session: transcriptionData.metadata?.session ||
               transcriptionData.metadata?._sessao?.numero ||
               null,
      patient_name: transcriptionData.metadata?.patient_name || null,
      source_file: transcriptionData.arquivo_original ||
                   transcriptionData.source_file ||
                   filename,
    };

    console.log(`   📅 Data da sessão: ${transcriptionMetadata.date}`);
    if (transcriptionMetadata.session) {
      console.log(`   🔢 Sessão: ${transcriptionMetadata.session}`);
    }

    const patientId = session.patientId;
    const outputPath = session.aslPath;

    if (existsSync(outputPath) && !forceReprocess) {
      console.log(`   ⏭️  Já processado - pulando (use --force para reprocessar)`);
      console.log(`   📄 Arquivo: ${outputPath}`);
      return;
    }

    if (existsSync(outputPath) && forceReprocess) {
      console.log(`   🔄 Reprocessando (--force ativado)...`);
    }

    // Análise linguística
    const result = await analyzePatientSpeech(transcriptionText, patientId, filename);
    result.transcription_metadata = transcriptionMetadata;

    // Salvar resultado
    writeFileSync(outputPath, JSON.stringify(result, null, 2), "utf-8");
    refreshPatientSessionStatus(session.patientId, session.id);
    console.log(`   ✅ Salvo em: ${outputPath}`);
  } catch (error: any) {
    console.log(`❌ Erro ao processar ${filename}: ${error.message}`);
    if (error.stack) console.log(error.stack);
    console.log("❌ Erro no processamento, continuando...");
  }
}

/**
 * Menu principal
 */
async function main() {
  // Verificar flag --force
  const forceReprocess = process.argv.includes("--force");

  console.log("\n" + "=".repeat(80));
  console.log("🔬 HEALTHOS ASL - Análise Sistêmica Linguística");
  console.log(`🤖 Runtime LLM: ${getSelectedRuntime()}`);
  if (forceReprocess) {
    console.log("🔄 Modo: REPROCESSAR TUDO (--force ativado)");
  }
  console.log("=".repeat(80));

  const files = listTranscriptionFiles();

  if (files.length === 0) {
    console.log("\n❌ Nenhum arquivo de transcrição encontrado em patients/");
    process.exit(1);
  }

  console.log(`\n📋 Encontradas ${files.length} transcrição(ões):`);
  files.forEach((file, idx) => {
    const relativePath = file.transcriptionPath.replace(PATHS.BASE, "");
    console.log(`   ${idx + 1}. ${relativePath}`);
  });

  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const answer = await new Promise<string>((resolve) => {
    console.log(`\n🎯 Escolha uma opção:`);
    console.log(`   • Digite o número do arquivo (1-${files.length})`);
    console.log(`   • Digite "todos" ou "t" para processar todos`);
    console.log(`   • Digite "sair" ou "s" para cancelar`);
    if (!forceReprocess) {
      console.log(`\n💡 Dica: Use --force para reprocessar: npm run pipeline:asl -- --force`);
    }
    rl.question("\n→ ", resolve);
  });

  rl.close();

  const trimmed = answer.trim().toLowerCase();

  if (trimmed === "sair" || trimmed === "s") {
    console.log("\n👋 Cancelado pelo usuário");
    process.exit(0);
  }

  if (trimmed === "todos" || trimmed === "t") {
    console.log(`\n🚀 Processando ${files.length} arquivo(s)...\n`);
    for (const file of files) {
      await processTranscription(file, forceReprocess);
    }
  } else {
    const num = parseInt(trimmed);
    if (isNaN(num) || num < 1 || num > files.length) {
      console.log("\n❌ Número inválido");
      process.exit(1);
    }
    await processTranscription(files[num - 1], forceReprocess);
  }

  console.log("\n" + "=".repeat(80));
  console.log("✅ Processamento concluído!");
  console.log("=".repeat(80) + "\n");
}

main().catch(console.error);
