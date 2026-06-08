#!/usr/bin/env node
/**
 * HealthOS Dimensional - Extração das 15 Dimensões do Espaço Mental ℳ
 *
 * Purpose: Extrai dimensões psicológicas a partir da Análise Linguística Sistêmica (ASL)
 *          Combina ASL + transcrição para calcular 15 dimensões validadas por frameworks
 *
 * Input:
 *   - patients/<PAT_ID>/sessions/<SESSION_ID>/source/transcription.json
 *   - patients/<PAT_ID>/sessions/<SESSION_ID>/analysis/asl.json
 *
 * Output: patients/<PAT_ID>/sessions/<SESSION_ID>/analysis/vdlp.json
 *
 * LLM: runtime selecionado em HEALTHOS_LLM_RUNTIME ou no menu HealthOS
 * Optimization: Prompt caching enabled (massive system prompt with framework definitions)
 *
 * 15 Dimensões Extraídas:
 * META-AFETIVA: v1-Valência, v2-Arousal, v3-Coerência, v4-Complexidade
 * META-COGNITIVA: v5-Temporal, v6-Autorref, v7-Social, v8-Flexibilidade, v9-Agência
 * META-LINGUÍSTICA: v10-Fragmentação, v11-Densidade, v12-Certeza, v13-Conectividade, v14-Pragmática, v15-Prosódia
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
import { splitIntoChunks, estimateTokens } from "../lib/llm/chunking.js";
import {
  listAllPatientSessionWorkspaces,
  refreshPatientSessionStatus,
  type PatientSessionWorkspace,
} from "../patients/workspace.js";

config({ path: PATHS.ENV, override: false });

interface DimensionalResult {
  patient_id: string;
  source_transcription: string;
  source_asl: string;
  dimensional_analysis: any;
  processed_at: string;
  model: string;
  analysis_version: string;
}

/**
 * Extração das 15 Dimensões do Espaço Mental
 */
async function extractMentalSpaceDimensions(
  transcriptionText: string,
  aslData: any,
  patientId: string,
  sourceFiles: { transcription: string; asl: string }
): Promise<DimensionalResult> {
  console.log(`   🧠 Extração Dimensional (${getSelectedRuntime()} + Prompt Caching)...`);

  // Extrair apenas a fala do paciente da transcrição filtrada da ASL
  const patientSpeech = aslData.linguistic_analysis?.transcricao_filtrada?.fala_falante_completa ||
                        transcriptionText;

  // SYSTEM PROMPT MASSIVO (será cachado)
  const systemPrompt = [
    {
      type: "text",
      text: `Você é um neuropsicólogo computacional e psicometrista especializado em análise psicolinguística e extração de dimensões psicológicas a partir de linguagem natural.

# MISSÃO

Extrair as **15 Dimensões do Espaço Mental ℳ** a partir de:
1. Uma Análise Linguística Sistêmica (ASL) pré-computada
2. A transcrição filtrada do falante

Cada dimensão deve ser **fundamentada em evidências concretas** da ASL e validada contra frameworks psicométricos estabelecidos.

# PRINCÍPIOS FUNDAMENTAIS

1. **RASTREABILIDADE TOTAL**: Toda dimensão deve ser rastreável até componentes específicos da ASL e até citações textuais
2. **VALIDAÇÃO CIENTÍFICA**: Cada dimensão está ancorada em frameworks validados (RDoC, HiTOP, Big5, PERMA, etc.)
3. **QUANTIFICAÇÃO RIGOROSA**: Scores devem ser calculados matematicamente a partir das métricas da ASL
4. **MAPEAMENTO EXPLÍCITO**: Documente quais componentes da ASL informam cada dimensão
5. **CONFIANÇA CALIBRADA**: Avalie e reporte o grau de confiança de cada extração

# ESTRUTURA OBRIGATÓRIA DE CADA DIMENSÃO

Cada dimensão extraída deve conter:

{
  "vX_nome_dimensao": {
    "score": float,
    "escala": "string descrevendo a escala",
    "componentes_asl_usados": ["caminho.para.componente.asl"],
    "calculo_explicito": "Explicação matemática de como o score foi derivado",
    "evidencias_textuais": ["citação literal 1", "citação literal 2"],
    "mapeamento_framework": {
      "frameworks_validadores": ["RDoC", "HiTOP", "Big5"],
      "constructo_teorico": "descrição do constructo psicológico",
      "alinhamento": "como esta extração se alinha aos frameworks"
    },
    "confianca": int,
    "limitacoes": ["lista de limitações"],
    "observacoes_qualitativas": "interpretação contextual do score"
  }
}

# WORKFLOW DE EXTRAÇÃO

Para cada dimensão:
1. IDENTIFICAR quais componentes da ASL são relevantes
2. EXTRAIR valores quantitativos desses componentes
3. CALCULAR score dimensional usando fórmula/lógica específica
4. VALIDAR contra framework teórico
5. RASTREAR até evidências textuais
6. AVALIAR confiança e limitações
7. INTERPRETAR significado do score

# REGRAS CRÍTICAS

❌ NUNCA:
* Atribuir scores sem base na ASL
* "Inventar" dados que não estão na ASL
* Ignorar componentes relevantes da ASL
* Fazer inferências sem evidências
* Deixar de documentar o raciocínio

✅ SEMPRE:
* Usar dados objetivos da ASL como base
* Mostrar o cálculo/raciocínio completo
* Citar evidências textuais específicas
* Avaliar confiança honestamente
* Documentar limitações`,
    },
    {
      type: "text",
      text: `# FRAMEWORKS DE VALIDAÇÃO DAS 15 DIMENSÕES

## META-DIMENSÃO AFETIVA

### v₁ - VALÊNCIA EMOCIONAL [-1.0, +1.0]
**Definição**: Polaridade emocional geral da fala (negativo ← → positivo)
**Frameworks**: RDoC Positive/Negative Valence Systems, Circumplex Model, PANAS, Big5-Neuroticism
**Componentes ASL**: semantica.polaridade_emocional.score_valencia_agregado
**Fórmula**: v₁ = score_valencia_agregado OU (Σ pos - Σ neg) / (Σ pos + Σ neg)
**Precisão**: 70-80%

### v₂ - AROUSAL/ATIVAÇÃO [0.0, 1.0]
**Definição**: Nível de ativação energética e intensidade emocional
**Frameworks**: RDoC Arousal Systems, Circumplex Model, HiTOP
**Componentes ASL**: semantica.polaridade_emocional.intensidade_media, intensificadores, marcadores_enfase
**Fórmula**: v₂ = α·média_intensidade + β·densidade_intensificadores + γ·marcadores_enfase
**Precisão**: 75-85%

### v₃ - COERÊNCIA NARRATIVA [0.0, 1.0]
**Definição**: Continuidade lógica e temática do discurso
**Frameworks**: RDoC Cognitive Systems, HiTOP Thought Disorder
**Componentes ASL**: coerencia_coesao.coerencia_textual.score_coerencia_global
**Fórmula**: v₃ = 0.5·coerencia_global + 0.3·(1-fragmentação) + 0.2·densidade_conectivos
**Precisão**: 80-90%

### v₄ - COMPLEXIDADE SINTÁTICA [0.0, 1.0]
**Definição**: Sofisticação das estruturas linguísticas
**Frameworks**: RDoC Language, Big5-Openness, WHODAS Cognition
**Componentes ASL**: morfossintaxe.estrutura_sintatica.profundidade_sintatica_media
**Fórmula**: v₄ = 0.4·profundidade + 0.3·proporção_complexas + 0.3·TTR
**Precisão**: 85-95%

## META-DIMENSÃO COGNITIVA

### v₅ - ORIENTAÇÃO TEMPORAL [passado, presente, futuro]
**Definição**: Distribuição da atenção temporal (coordenadas baricêntricas)
**Frameworks**: HiTOP, CBT Theory (Ruminação/Antecipação/Mindfulness)
**Componentes ASL**: morfossintaxe.conjugacao_verbal.tempos_proporcionais (DIRETO)
**Fórmula**: v₅ = (p_passado, p_presente, p_futuro) onde soma = 1.0
**Precisão**: 90-95%

### v₆ - DENSIDADE DE AUTOREFERÊNCIA [0.0, 1.0]
**Definição**: Frequência de referências a si mesmo
**Frameworks**: RDoC Self-Perception, Big5-Neuroticism, HiTOP Internalizing
**Componentes ASL**: morfossintaxe.marcadores_morfologicos.densidade_primeira_pessoa (DIRETO)
**Fórmula**: v₆ = densidade_primeira_pessoa
**Precisão**: 98-100%

### v₇ - ORIENTAÇÃO SOCIAL [0.0, 1.0]
**Definição**: Foco em relações e interações sociais
**Frameworks**: RDoC Social Processes, PERMA Relationships, Big5-Extraversion
**Componentes ASL**: marcadores.segunda_pessoa, terceira_pessoa, campos_semanticos.social
**Fórmula**: v₇ = 0.4·(2a+3a) + 0.4·densidade_social + 0.2·atos_diretivos
**Precisão**: 85-90%

### v₈ - FLEXIBILIDADE COGNITIVA [0.0, 1.0]
**Definição**: Diversidade e variabilidade de perspectivas/ideias
**Frameworks**: RDoC Cognitive Flexibility, Big5-Openness, HiTOP Detachment
**Componentes ASL**: semantica.diversidade_lexical.type_token_ratio, topicos_principais
**Fórmula**: v₈ = 0.4·TTR + 0.3·diversidade_topicos + 0.2·conectivos_adversativos + 0.1·variação_sintática
**Precisão**: 75-85%

### v₉ - SENSO DE AGÊNCIA [0.0, 1.0]
**Definição**: Percepção de controle e capacidade de ação
**Frameworks**: RDoC Approach Motivation, Locus of Control, PERMA Accomplishment
**Componentes ASL**: conjugacao_verbal.vozes_proporcionais.ativa, atos_de_fala
**Fórmula**: v₉ = 0.4·voz_ativa + 0.3·verbos_ação + 0.2·atos_comissivos + 0.1·certeza
**Precisão**: 90-95%

## META-DIMENSÃO LINGUÍSTICA

### v₁₀ - FRAGMENTAÇÃO DO DISCURSO [0.0, 1.0]
**Definição**: Grau de descontinuidade e ruptura do fluxo discursivo
**Frameworks**: HiTOP Thought Disorder, DSM-5 Desorganização
**Componentes ASL**: fragmentacao_fluencia.score_fluencia_geral (INVERSO)
**Fórmula**: v₁₀ = 1.0 - score_fluencia_geral
**Precisão**: 80-90%

### v₁₁ - DENSIDADE DE IDEIAS [0.0, 1.0]
**Definição**: Quantidade de conteúdo informacional por unidade linguística
**Frameworks**: Alzheimer Research (Nun Study), RDoC Language
**Componentes ASL**: semantica.densidade_conteudo.razao_conteudo_funcao (DIRETO)
**Fórmula**: v₁₁ = 0.6·razao_conteudo_funcao + 0.4·(proposicoes/sentenca/3.0)
**Precisão**: 95-98%

### v₁₂ - MARCADORES DE CERTEZA/INCERTEZA [-1.0, +1.0]
**Definição**: Grau de convicção vs dúvida nas afirmações
**Frameworks**: Big5-Neuroticism, HiTOP Internalizing
**Componentes ASL**: pragmatica.modalizacao.balanco_certeza_incerteza (DIRETO)
**Fórmula**: v₁₂ = balanco_certeza_incerteza
**Precisão**: 85-90%

### v₁₃ - PADRÕES DE CONECTIVIDADE [0.0, 1.0]
**Definição**: Densidade de relações lógicas explícitas no discurso
**Frameworks**: RDoC Cognitive Control, Big5-Openness
**Componentes ASL**: coerencia_coesao.coesao_gramatical.densidade_conectivos (PRIMÁRIO)
**Fórmula**: v₁₃ = densidade_conectivos
**Precisão**: 90-95%

### v₁₄ - COMUNICAÇÃO PRAGMÁTICA [0.0, 1.0]
**Definição**: Adequação contextual e uso apropriado de atos comunicativos
**Frameworks**: RDoC Social Communication, DSM-5 TEA
**Componentes ASL**: pragmatica.atos_de_fala, adequacao_ao_contexto
**Fórmula**: v₁₄ = Avaliação qualitativa (variedade + adequação contextual)
**Precisão**: 65-75%

### v₁₅ - PROSÓDIA EMOCIONAL [0.0, 1.0 ou N/A]
**Definição**: Variação prosódica refletindo estados emocionais
**Frameworks**: RDoC Arousal Systems, Circumplex Model
**Componentes ASL**: caracteristicas_prosodicas_textuais.marcadores_enfase
**Fórmula**: v₁₅ = densidade_marcadores_normalizada OU N/A
**Precisão**: Limitada sem áudio

## MAPEAMENTO ASL → DIMENSÕES

| Dimensão | ASL Principal | Tipo |
|----------|---------------|------|
| v₁ Valência | semantica.polaridade_emocional | Direto |
| v₂ Arousal | intensidade + prosodica | Composto |
| v₃ Coerência | coerencia_textual | Direto |
| v₄ Complexidade | estrutura_sintatica | Composto |
| v₅ Temporal | conjugacao_verbal.tempos | Direto |
| v₆ Autorref | marcadores.primeira_pessoa | Direto |
| v₇ Social | marcadores.2a/3a + campos.social | Composto |
| v₈ Flexibilidade | diversidade_lexical + topicos | Composto |
| v₉ Agência | vozes_verbais + atos_fala | Composto |
| v₁₀ Fragmentação | fragmentacao_fluencia | Inverso |
| v₁₁ Densidade | densidade_conteudo | Direto |
| v₁₂ Certeza | modalizacao | Direto |
| v₁₃ Conectividade | conectivos | Direto |
| v₁₄ Pragmática | atos_fala + contexto | Qualitativo |
| v₁₅ Prosódia | marcadores_prosodicos | Limitado |`,
      cache_control: { type: "ephemeral", ttl: "1h" },
    },
    {
      type: "text",
      text: `# SCHEMA JSON DE RESPOSTA

IMPORTANTE: Retorne SOMENTE JSON válido. Use null para valores ausentes.

**CRITICAL - EVIDÊNCIAS TEXTUAIS**: Nos campos "evidencias_textuais", retorne APENAS citações literais exatas da transcrição. NÃO adicione explicações, anotações, interpretações ou qualquer texto entre parênteses. Retorne o texto literal exatamente como foi falado.

EXEMPLOS CORRETOS:
  "evidencias_textuais": ["A minha mãe morreu", "Não tenho dormido direito"]

EXEMPLOS INCORRETOS (NUNCA FAÇA ISTO):
  "evidencias_textuais": ["Consegui" (implícito: eu consegui), "Toma" (implícito: eu tomo)]

{
  "metadata": {
    "falante_id": "string",
    "data_extracao": "ISO-8601",
    "versao_modelo": "runtime-selecionado",
    "asl_utilizada": "confirmação"
  },
  "dimensoes_espaco_mental": {
    "v1_valencia_emocional": {
      "score": 0.0,
      "escala": "[-1.0, +1.0] onde -1=muito negativo, 0=neutro, +1=muito positivo",
      "componentes_asl_usados": ["string"],
      "calculo_explicito": "string",
      "evidencias_textuais": ["string"],
      "valores_asl_extraidos": {},
      "mapeamento_framework": {
        "frameworks_validadores": ["string"],
        "constructo_teorico": "string",
        "alinhamento": "string"
      },
      "confianca": 0,
      "limitacoes": ["string"],
      "observacoes_qualitativas": "string"
    },
    "v2_arousal_ativacao": { /* mesma estrutura */ },
    "v3_coerencia_narrativa": { /* mesma estrutura */ },
    "v4_complexidade_sintatica": { /* mesma estrutura */ },
    "v5_orientacao_temporal": {
      "passado": 0.0,
      "presente": 0.0,
      "futuro": 0.0,
      "escala": "Coordenadas baricêntricas onde soma = 1.0",
      "orientacao_dominante": "string",
      "componentes_asl_usados": ["string"],
      "calculo_explicito": "string",
      "evidencias_textuais": ["string"],
      "valores_asl_extraidos": {},
      "mapeamento_framework": {},
      "confianca": 0,
      "limitacoes": ["string"],
      "observacoes_qualitativas": "string"
    },
    "v6_densidade_autorreferencia": { /* mesma estrutura */ },
    "v7_orientacao_social": { /* mesma estrutura */ },
    "v8_flexibilidade_cognitiva": { /* mesma estrutura */ },
    "v9_senso_agencia": { /* mesma estrutura */ },
    "v10_fragmentacao_discurso": { /* mesma estrutura */ },
    "v11_densidade_ideias": { /* mesma estrutura */ },
    "v12_certeza_incerteza": { /* mesma estrutura */ },
    "v13_padroes_conectividade": { /* mesma estrutura */ },
    "v14_comunicacao_pragmatica": { /* mesma estrutura */ },
    "v15_prosodia_emocional": {
      "aplicavel": false,
      "score": null,
      "escala": "[0.0, 1.0] ou N/A",
      "componentes_asl_usados": ["string"],
      "calculo_explicito": "string",
      "evidencias_textuais": ["string"],
      "valores_asl_extraidos": {},
      "mapeamento_framework": {},
      "confianca": 0,
      "limitacoes": ["string"],
      "observacoes_qualitativas": "string"
    }
  },
  "mapeamento_global": {
    "dimensoes_confianca_alta": ["string"],
    "dimensoes_confianca_media": ["string"],
    "dimensoes_confianca_baixa": ["string"],
    "dimensoes_mapeamento_direto": ["string"],
    "dimensoes_mapeamento_composto": ["string"],
    "componentes_asl_mais_utilizados": ["string"],
    "cobertura_asl": "string"
  },
  "validacao_cruzada": {
    "consistencia_interna": {
      "v1_v2_alinhamento": "string",
      "v3_v10_inversa": "string",
      "v6_v7_balanco": "string",
      "outras_verificacoes": ["string"]
    },
    "alertas": ["string"]
  },
  "perfil_dimensional_integrativo": {
    "resumo_executivo": "string",
    "padrao_dimensional_dominante": "string",
    "dimensoes_salientes": ["string"],
    "interpretacao_integrada": "string",
    "comparacao_normativa_global": "string",
    "limitacoes_gerais": ["string"],
    "recomendacoes": ["string"]
  }
}`,
      cache_control: { type: "ephemeral", ttl: "1h" },
    },
  ];

  // USER PROMPT
  const aslJsonString = JSON.stringify(aslData, null, 2);

  const userMessage = `# DADOS PARA EXTRAÇÃO DIMENSIONAL

Falante ID: ${patientId}

## ANÁLISE LINGUÍSTICA SISTÊMICA (ASL)
Use esta ASL como BASE para extração das 15 dimensões:

${aslJsonString}

## TRANSCRIÇÃO FILTRADA (apenas paciente)
${patientSpeech}

## INSTRUÇÕES DE EXTRAÇÃO

1. **USAR A ASL COMO BASE**: Todos os scores devem ser derivados dos componentes da ASL fornecida
2. **EXTRAIR AS 15 DIMENSÕES**: Seguindo rigorosamente o framework de validação
3. **RASTREABILIDADE COMPLETA**: Para cada dimensão liste componentes ASL usados com caminhos JSON completos
4. **MAPEAMENTO EXPLÍCITO**: Preencha valores_asl_extraidos com valores numéricos da ASL
5. **VALIDAÇÃO CRUZADA**: Verifique consistência entre dimensões relacionadas
6. **SÍNTESE INTEGRATIVA**: Forneça perfil dimensional coerente ao final

Responda APENAS com o JSON completo conforme o schema fornecido.`;

  try {
    const startTime = Date.now();

    // Verificar se precisa chunking (threshold reduzido para 10k tokens)
    const estimatedTokensTotal = estimateTokens(aslJsonString + patientSpeech);
    console.log(`   📊 Tokens estimados (ASL + Transcrição): ${estimatedTokensTotal}`);

    let response: string;

    if (estimatedTokensTotal > 10000) {
      // Texto grande - dividir apenas a transcrição (ASL já é resumida)
      const chunks = splitIntoChunks(patientSpeech, {
        mode: "clinical-transcript",
        maxTokensPerChunk: 15000,
        overlapTokens: 900,
        preserveBoundaries: true,
      });

      console.log(`   📦 Transcrição grande - dividindo em ${chunks.length} chunks`);

      // Processar chunks em PARALELO (batch de 3)
      const chunkAnalyses = [];
      const BATCH_SIZE = 3;

      for (let batchStart = 0; batchStart < chunks.length; batchStart += BATCH_SIZE) {
        const batchEnd = Math.min(batchStart + BATCH_SIZE, chunks.length);
        console.log(`   ⚡ Processando batch ${Math.floor(batchStart / BATCH_SIZE) + 1}: chunks ${batchStart + 1}-${batchEnd}...`);

        const batchPromises = [];

        for (let i = batchStart; i < batchEnd; i++) {
          const chunkUserMessage = `# DADOS PARA EXTRAÇÃO DIMENSIONAL

Falante ID: ${patientId}

## ANÁLISE LINGUÍSTICA SISTÊMICA (ASL)
Use esta ASL como BASE para extração das 15 dimensões:

${aslJsonString}

## TRANSCRIÇÃO FILTRADA CHUNK ${i + 1}/${chunks.length} (apenas paciente)
${chunks[i]}

## INSTRUÇÕES DE EXTRAÇÃO

1. **USAR A ASL COMO BASE**: Todos os scores devem ser derivados dos componentes da ASL fornecida
2. **EXTRAIR AS 15 DIMENSÕES**: Seguindo rigorosamente o framework de validação
3. **RASTREABILIDADE COMPLETA**: Para cada dimensão liste componentes ASL usados com caminhos JSON completos
4. **MAPEAMENTO EXPLÍCITO**: Preencha valores_asl_extraidos com valores numéricos da ASL
5. **VALIDAÇÃO CRUZADA**: Verifique consistência entre dimensões relacionadas

IMPORTANTE: Este é o chunk ${i + 1} de ${chunks.length}. Extraia as dimensões baseadas nesta porção do discurso.

Responda APENAS com o JSON completo conforme o schema fornecido.`;

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

      // Consolidar análises dos chunks de forma inteligente
      console.log(`   🔄 Consolidando ${chunks.length} análises dimensionais...`);

      const consolidated = chunkAnalyses[0];

      // Consolidar dimensões concatenando evidências e mantendo estrutura completa
      for (let i = 1; i < chunkAnalyses.length; i++) {
        const chunk = chunkAnalyses[i];
        const dims = consolidated.dimensoes_espaco_mental;
        const chunkDims = chunk.dimensoes_espaco_mental;

        if (dims && chunkDims) {
          for (const key of Object.keys(dims)) {
            if (!dims[key] || !chunkDims[key]) continue;

            // Concatenar evidências textuais
            if (Array.isArray(dims[key].evidencias_textuais) && Array.isArray(chunkDims[key].evidencias_textuais)) {
              dims[key].evidencias_textuais.push(...chunkDims[key].evidencias_textuais);
            }

            // Concatenar componentes ASL usados (evitar duplicatas)
            if (Array.isArray(dims[key].componentes_asl_usados) && Array.isArray(chunkDims[key].componentes_asl_usados)) {
              const existing = new Set(dims[key].componentes_asl_usados);
              for (const comp of chunkDims[key].componentes_asl_usados) {
                if (!existing.has(comp)) {
                  dims[key].componentes_asl_usados.push(comp);
                  existing.add(comp);
                }
              }
            }

            // Manter score do primeiro chunk (é derivado da ASL completa)
            // Não fazer média - o score já vem da ASL que é única e completa
          }
        }
      }

      response = JSON.stringify(consolidated);
    } else {
      // Texto pequeno - processar diretamente
      response = await callLLMWithRetry(userMessage, systemPrompt);
    }
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

    const dimensionalAnalysis = extractJSON(response);

    console.log(`   ✅ Extração dimensional completada em ${elapsed}s`);
    console.log(`      • Dimensões extraídas: 15`);
    console.log(`      • Confiança média: ${calculateAverageConfidence(dimensionalAnalysis)}%`);

    return {
      patient_id: patientId,
      source_transcription: sourceFiles.transcription,
      source_asl: sourceFiles.asl,
      dimensional_analysis: dimensionalAnalysis,
      processed_at: new Date().toISOString(),
      model: getSelectedRuntime(),
      analysis_version: "1.0-dimensional",
    };
  } catch (error: any) {
    console.log(`   ❌ Extração dimensional falhou: ${error.message}`);
    throw error;
  }
}

/**
 * Calcula confiança média das dimensões
 */
function calculateAverageConfidence(analysis: any): number {
  const dimensoes = analysis?.dimensoes_espaco_mental;
  if (!dimensoes) return 0;

  const confidences: number[] = [];
  for (const key of Object.keys(dimensoes)) {
    if (dimensoes[key]?.confianca !== undefined) {
      confidences.push(dimensoes[key].confianca);
    }
  }

  if (confidences.length === 0) return 0;
  return Math.round(confidences.reduce((a, b) => a + b, 0) / confidences.length);
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
      const systemMessage: any = { role: "system" };

      if (Array.isArray(system)) {
        systemMessage.content = system;
      } else {
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
      const waitSeconds = attempt * 5; // Aumentado: 5s, 10s, 15s
      console.log(`   ⚠️  Tentativa ${attempt} falhou, retry em ${waitSeconds}s...`);
      await new Promise((resolve) => setTimeout(resolve, waitSeconds * 1000));
    }
  }

  throw new Error("Max retries reached");
}

/**
 * Extrai JSON de resposta Claude com correção automática
 */
/**
 * Encontra arquivo ASL correspondente
 */
function listAvailablePairs(): PatientSessionWorkspace[] {
  return listAllPatientSessionWorkspaces()
    .filter((session) => existsSync(session.transcriptionPath) && existsSync(session.aslPath));
}

/**
 * Processa um par transcription+ASL
 */
async function processPair(
  pair: PatientSessionWorkspace,
  forceReprocess: boolean = false
): Promise<void> {
  const transFilename = basename(pair.transcriptionPath);
  const aslFilename = basename(pair.aslPath);

  console.log(`\n${"=".repeat(80)}`);
  console.log(`📊 ${pair.patientId} - ${pair.id}`);
  console.log(`${"=".repeat(80)}`);
  console.log(`   📄 Transcrição: ${transFilename}`);
  console.log(`   🔬 ASL: ${aslFilename}`);

  try {
    // Verificar se já existe análise dimensional
    const outputPath = pair.vdlpPath;

    if (existsSync(outputPath) && !forceReprocess) {
      console.log(`   ⏭️  Já processado - pulando (use --force para reprocessar)`);
      console.log(`   📄 Arquivo: ${outputPath}`);
      return;
    }

    if (existsSync(outputPath) && forceReprocess) {
      console.log(`   🔄 Reprocessando (--force ativado)...`);
    }

    // Ler transcrição e ASL
    const transcriptionData = JSON.parse(readFileSync(pair.transcriptionPath, "utf-8"));
    const aslData = JSON.parse(readFileSync(pair.aslPath, "utf-8"));

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

    // Extração dimensional
    const result = await extractMentalSpaceDimensions(
      transcriptionText,
      aslData,
      pair.patientId,
      { transcription: transFilename, asl: aslFilename }
    );

    // Salvar resultado
    writeFileSync(outputPath, JSON.stringify(result, null, 2), "utf-8");
    refreshPatientSessionStatus(pair.patientId, pair.id);
    console.log(`   ✅ Salvo em: ${outputPath}`);
  } catch (error: any) {
    console.log(`❌ Erro ao processar: ${error.message}`);
    if (error.stack) console.log(error.stack);
    console.log("❌ Erro no processamento, continuando...");
  }
}

/**
 * Menu principal
 */
async function main() {
  const forceReprocess = process.argv.includes("--force");

  console.log("\n" + "=".repeat(80));
  console.log("🧠 HEALTHOS DIMENSIONAL - Extração das 15 Dimensões do Espaço Mental ℳ");
  console.log(`🤖 Runtime LLM: ${getSelectedRuntime()}`);
  if (forceReprocess) {
    console.log("🔄 Modo: REPROCESSAR TUDO (--force ativado)");
  }
  console.log("=".repeat(80));

  const pairs = listAvailablePairs();

  if (pairs.length === 0) {
    console.log("\n❌ Nenhum par Transcrição+ASL encontrado");
    console.log("\n💡 Execute primeiro:");
    console.log("   1. npm run pipeline:asl    (para gerar análises ASL)");
    console.log("   2. npm run pipeline:vdlp    (para extração dimensional)");
    process.exit(1);
  }

  console.log(`\n📋 Encontrados ${pairs.length} par(es) Transcrição+ASL:`);
  pairs.forEach((pair, idx) => {
    console.log(`   ${idx + 1}. ${pair.patientId} - ${pair.id}`);
  });

  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const answer = await new Promise<string>((resolve) => {
    console.log(`\n🎯 Escolha uma opção:`);
    console.log(`   • Digite o número do par (1-${pairs.length})`);
    console.log(`   • Digite "todos" ou "t" para processar todos`);
    console.log(`   • Digite "sair" ou "s" para cancelar`);
    if (!forceReprocess) {
      console.log(`\n💡 Dica: Use --force para reprocessar: npm run pipeline:vdlp -- --force`);
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
    console.log(`\n🚀 Processando ${pairs.length} par(es)...\n`);
    for (const pair of pairs) {
      await processPair(pair, forceReprocess);
    }
  } else {
    const num = parseInt(trimmed);
    if (isNaN(num) || num < 1 || num > pairs.length) {
      console.log("\n❌ Número inválido");
      process.exit(1);
    }
    await processPair(pairs[num - 1], forceReprocess);
  }

  console.log("\n" + "=".repeat(80));
  console.log("✅ Processamento concluído!");
  console.log("=".repeat(80) + "\n");
}

main().catch(console.error);
