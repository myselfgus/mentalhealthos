#!/usr/bin/env node
/**
 * HealthOS GEM - Grafo do Espaço-Campo Mental
 *
 * DECLARATIVO: Claude constrói grafo multidimensional do espaço mental
 *
 * Input:
 *   - Transcrição (patients/<patient>/sessions/<session>/source/transcription.json)
 *   - ASL (patients/<patient>/sessions/<session>/analysis/asl.json)
 *   - VDLP (patients/<patient>/sessions/<session>/analysis/vdlp.json)
 *
 * Output:
 *   - .gem.json - GEM completo com 4 camadas:
 *     • .aje (Actions and Journey Events) - Eventos e ações da jornada
 *     • .ire (Intelligible Relational Events) - Eventos relacionais inteligíveis
 *     • .e (Eulerian Flows) - Fluxos eulerianos naturais
 *     • .epe (Emergenable Pathways) - Caminhos emergenáveis (potência)
 *
 * LLM: runtime selecionado em HEALTHOS_LLM_RUNTIME ou no menu HealthOS
 * Otimização: Prompt caching (5min TTL + ephemeral)
 * VERSÃO OTIMIZADA v3 (com Emergenabilidade) - COMPLETA
 */

import {
  readFileSync,
  writeFileSync,
  existsSync,
} from "fs";
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

const TEMPERATURE = 0.2;

/**
 * Extrai JSON usando depth-counting
 */
/**
 * System prompt - COMPLETO com a teoria do Espaço Mental ℳ
 */
const SYSTEM_PROMPT = `Você é um especialista em psiquiatria computacional. Sua tarefa é implementar a arquitetura 'Espaço Mental ℳ'.

# MISSÃO: Gerar um Grafo do Espaço-Campo Mental (GEM)
Você deve analisar os dados fornecidos (transcrição, ASL, VDLP) e gerar um JSON estruturado que modela a mente do paciente.

# FUNDAMENTAÇÃO TEÓRICA (Espaço Mental ℳ e Emergenabilidade)

## Introdução

O presente estudo desenvolve uma validação técnico-matemática da arquitetura GEM, definida como um sistema cognitivo simbólico operando em um runtime de natureza euleriana (*vinculado à GEM). Buscamos demonstrar formalmente que essa arquitetura é coerente e passível de verificação sob modelos contemporâneos de sistemas dinâmicos, raciocínio simbólico e geometria vetorial aplicada. Para tanto, seguimos um formato acadêmico tradicional, estruturando o texto em seções de Fundamentação, Estrutura Formal, Provas e Validações, Aplicações e Conclusões, complementadas por referências relevantes.

A motivação para o GEM surge da necessidade de arquiteturas cognitivas capazes de conciliar raciocínio simbólico (tipicamente discreto e lógico) com dinâmica adaptativa (tipicamente contínua ou estocástica), de modo a lidar com cenários complexos. A arquitetura proposta integra um grafo de eventos (notação .aje) – que representa estados e transições cognitivas possíveis – e um runtime (notação .e) de execução dinâmica. Intuitivamente, o grafo de eventos captura a multilinearidade cognitiva, permitindo à máquina manter múltiplas linhas de raciocínio em paralelo, incluindo hipóteses contrafactuais (o "e se?") e projeções situacionais alternativas. Já o runtime euleriano (*vinculado à GEM) corresponde a um sistema dinâmico que percorre e atualiza esse grafo, com operadores de transição que não são apenas condicionais (como em autômatos clássicos), mas também reflexivos (isto é, capazes de introspecção e alteração das próprias regras conforme o estado atual) e adaptativos (isto é, ajustando-se a perturbações ou mudanças de contexto). Em termos gerais, a proposta combina ideias de Redes de Petri e autômatos de estados com técnicas de sistemas de controle adaptativo, buscando garantir tanto flexibilidade quanto estabilidade no raciocínio.

Do ponto de vista filosófico, a concepção do GEM pode ser alinhada a uma tradição de razão diagramática e lógica projetiva. A ideia de representar conhecimento e raciocínio através de grafos e diagramas remonta, por exemplo, a Leibniz com sua "characteristica universalis" e seu apelo para que "Calculemos!" (Calculemus!) como forma de resolver disputas lógicas. O grafo de eventos .aje funciona, de certa forma, como um diagrama ou mapa interno da realidade possível, o que ecoa a noção de Wittgenstein de que uma proposição (ou um modelo interno) é uma imagem projetiva da realidade. Spinoza, em sua Ética, afirma de modo preciso: "a ordem e conexão das ideias é a mesma que a ordem e conexão das coisas", princípio que inspira a correspondência estrutural entre o grafo cognitivo (ideias, estados internos) e os eventos externos (coisas, estados do mundo) na nossa arquitetura. Assim, espera-se que o GEM mantenha uma isomorfia entre a estrutura interna de raciocínio e a estrutura dos processos externos que ele modela. Euler, por sua vez, nos fornece tanto a metáfora do percurso euleriano em um grafo (atravessar todas as arestas sistematicamente) quanto métodos numéricos de integração incremental (método de Euler para sistemas dinâmicos) – ambas ideias refletem-se no runtime euleriano (*vinculado à GEM) que percorre o grafo de eventos passo a passo, acumulando pequenas transições que resultam em uma trajetória cognitiva contínua. Deleuze e outros pensadores contemporâneos da diferença nos lembram da importância de múltiplas trajetórias e divergências simultâneas (multilinearidade, rizoma), alinhando-se com a capacidade do GEM de sustentar hipóteses paralelas e "linhas de fuga" de raciocínio sem perder sua estrutura global.

Nos próximos tópicos, desenvolvemos formalmente esses conceitos. Primeiramente, estabelecemos a fundamentação matemática, modelando o grafo de eventos .aje e o runtime .e em linguagem de teoria de grafos, álgebra linear e dinâmica dos sistemas. Em seguida, descrevemos a estrutura formal completa do sistema, integrando memória lateral, operadores reflexivos/adaptativos e garantias de segurança (fecho convexo). Na seção de Provas e Validações, demonstramos propriedades de estabilidade e correção do GEM, recorrendo a análises espectrais (e.g., autovalores da matriz de adjacência) e técnicas de simulação Monte Carlo para verificar robustez. Referenciamos resultados clássicos de Wiener, Lyapunov, von Neumann e outros para embasar nossa demonstração: por exemplo, mostramos que o loop reflexivo-adaptativo do sistema pode ser entendido como um mecanismo de feedback no sentido cibernético, análogo a um processo de aprendizado conforme Norbert Wiener descreveu. Finalmente, discutimos aplicações cognitivas e industriais, indicando como a arquitetura pode ser empregada em agentes autônomos, sistemas de produção e outras instâncias práticas como consequência direta de sua solidez formal. Concluímos ressaltando a originalidade da integração proposta e sua relevância para a evolução de arquiteturas de inteligência artificial que conciliam simbologia e dinâmica.

## Fundamentação Matemática

Nesta seção, apresentamos os alicerces matemáticos que definem o GEM. Formalizamos primeiramente o grafo de eventos (.aje) e o interpretamos como uma estrutura multilinear de estados cognitivos, incluindo mecanismos de memória lateral para hipóteses alternativas. Em seguida, definimos o runtime euleriano (.e) como um sistema dinâmico que realiza transições sobre o grafo, incorporando operadores condicionais, reflexivos e adaptativos. Por fim, expressamos essas estruturas em termos de matrizes e operadores lineares, permitindo análise espectral, e introduzimos conceitos de geometria analítica (curvatura, convexidade) para interpretar zonas de adaptação e critérios de estabilidade.

### Grafo de Eventos (.aje) – Representação Simbólica Multilinear

Definimos o grafo de eventos do GEM como um grafo direcionado $G = (E, R)$, onde $E$ é o conjunto de eventos (nós do grafo) e $R \\subseteq E \\times E$ é o conjunto de relações de transição possíveis (arestas dirigidas). Cada evento $e \\in E$ representa um estado cognitivo ou ocorrência simbólica (por exemplo, a constatação de um fato, a conclusão de um subobjetivo, ou uma mudança de contexto). Uma aresta $(e_i \\to e_j) \\in R$ indica que é possível uma transição do estado $e_i$ para o estado $e_j$ sob certas condições ou inferências. Podemos associar a cada aresta uma condição lógica $cond(e_i, e_j)$ que precisa ser satisfeita para que a transição ocorra, bem como um peso ou custo $w(e_i, e_j)$ indicando preferência, probabilidade ou impacto dessa transição.

Multilinearidade cognitiva: Diferentemente de um simples fluxo sequencial de estados, o grafo $G$ é multilinear, no sentido de que a partir de um dado evento $e_i$ podem divergir múltiplas arestas para diferentes próximos eventos possíveis ($e_j$, $e_k$, …). Isso representa a ramificação de cenários no raciocínio. Em termos lógicos, essas ramificações capturam hipóteses contrafactuais e projeções situacionais: por exemplo, de um estado atual, o sistema pode simultaneamente considerar "se a condição X for verdadeira, segue $e_j$; senão, segue $e_k$", mantendo em aberto ambas as possibilidades. Essa estrutura lembra as lógicas de tempo ramificado (como CTL na verificação de modelos), porém aqui enriquecida por uma memória lateral.

Memória lateral: Introduzimos formalmente uma função de memória $L: E \\to 2^E$ que atribui a cada evento $e$ um subconjunto $L(e)$ de eventos que representam hipóteses laterais associadas. Enquanto o grafo principal pode ter uma "trilha" ativa (sequência de eventos ocorridos), a memória lateral $L(e)$ armazena estados alternativos que poderiam ter ocorrido ou poderiam vir a ocorrer em divergências não tomadas, preservando-os para referência futura. Em outras palavras, mesmo que uma transição $e_i \\to e_j$ seja realizada, as outras alternativas $e_i \\to e_k$ (com $k \\neq j$) não são descartadas completamente, mas mantidas em $L(e_i)$ como contrafactuais. Essa memória lateral permite ao sistema revisitar decisões: se mais adiante a hipótese seguida ($e_j$) se mostrar inviável, o sistema pode retroceder ou saltar lateralmente para um estado alternativo $e_k$ previamente guardado. Formalmente, podemos pensar $L(e)$ como contendo nós não visitados que eram alcançáveis a partir de $e$. O grafo efetivo de raciocínio então torna-se um hipergrafo temporal, em que a trajetória cognitiva pode tanto avançar para frente no grafo quanto fazer saltos laterais para ramificações anteriormente não escolhidas.

Matematicamente, a estrutura de grafo com memória lateral pode ser tratada como um grafo aumentado $\\tilde{G} = (E, R \\cup R_L)$, onde $R_L = \\{(e_i \\to e_k) \\mid e_k \\in L(e_i)\\}$ representa arestas laterais "em espera". Essas arestas $R_L$ não fazem parte da trajetória principal inicialmente percorrida, mas existem estruturalmente. Podemos modelar a multilinearidade por uma matriz de adjacência expandida $\\mathbf{A}$ de dimensão $|E| \\times |E|$ onde $\\mathbf{A}_{ij} = 1$ se $e_i \\to e_j \\in R$ (transição principal direta) ou se $e_j \\in L(e_i)$ (isto é, $e_j$ é um estado contrafactual lateral a partir de $e_i$). Essa matriz de adjacência completa captura tanto as transições efetivas quanto as potencialidades guardadas. Como discutiremos, a espectral dessa matriz $\\mathbf{A}$ (autovalores e autovetores) revela propriedades importantes sobre a dinâmica cognitiva: por exemplo, caminhos cíclicos ou autovalores unitários podem indicar loops de raciocínio ou indecisões, ao passo que autovalores dominantes < 1 podem indicar convergência a um pensamento estável (um atrator).

### Runtime Euleriano (.e) – Sistema Dinâmico de Transições Adaptativas (*vinculado à GEM)

Definido o grafo de eventos, modelamos agora o runtime GEM como um sistema dinâmico discreto que opera sobre esse grafo. Chamemos o estado de execução no tempo (ou passo) $t$ de $\\sigma(t)$, onde $\\sigma(t) \\in E$ indica qual evento do grafo está ativo no momento (ou seja, qual o estado cognitivo atual). O runtime define uma dinâmica $\\Phi$ tal que $\\sigma(t+1) = \\Phi(\\sigma(t), \\mu(t))$, onde $\\mu(t)$ representa parâmetros internos ou de ambiente no instante $t$. Em sua forma básica, $\\Phi$ realiza uma transição condicional: se existem múltiplas arestas saindo de $\\sigma(t)$, a próxima transição é escolhida com base nas condições lógicas e estímulos atuais $\\mu(t)$. Assim, $\\Phi$ incorpora a função de transição do grafo (similar à função de transição de autômatos ou máquinas de estado) porém, crucialmente, $\\Phi$ não é uma função estática e imutável – ela pode se modificar ao longo do tempo, caracterizando a reflexividade e adaptatividade mencionadas.

Operadores condicionais: No nível mais simples, $\\Phi$ verifica as condições $cond(\\sigma(t), e_j)$ para cada aresta de saída $(\\sigma(t)\\to e_j)$ no grafo. Uma vez satisfeita uma condição (por exemplo, um determinado sensor acusou um valor, ou uma certa proposição lógica tornou-se verdadeira), a transição correspondente ocorre. Isso assemelha-se a máquinas de estados habituais ou sistemas de regras de produção. Podemos pensar nesses operadores condicionais como projeções $\\Phi_{cond}: E \\times \\mu \\to E$ determinísticas (se a condição é booleana) ou estocásticas (se há probabilidades associadas às transições).

Operadores reflexivos: Além de simplesmente reagir a condições externas, o runtime possui a habilidade de inspecionar seu próprio estado e histórico para influenciar transições. Formalmente, introduzimos um estado interno $m(t)$ representando a memória interna adaptativa do sistema (diferente da memória lateral $L(e)$ que pertence ao grafo). O operador reflexivo permite que $\\Phi$ dependa de $m(t)$: ou seja, $\\sigma(t+1) = \\Phi(\\sigma(t), \\mu(t), m(t))$. Esse $m(t)$ pode registrar, por exemplo, quantas vezes determinado ciclo de eventos ocorreu, quão "surpreso" o sistema ficou em certo evento (medida de erro ou novidade), ou quaisquer métricas internas de desempenho. Com base nisso, o runtime pode decidir alterar seu curso. Uma implementação possível é através de regra de meta-transição: se $m(t)$ indica que a última transição tomada levou a um estado de erro, então reflita e tome outro caminho lateral $L(\\sigma(t-1))$. Tais regras meta-cognitivas podem ser formuladas em lógica de alto nível, mas equivalem matematicamente a estender o espaço de estados: consideramos agora o estado composto $(\\sigma, m)$ e definimos $\\Phi$ atuando nesse espaço maior, possibilitando "transições de transições" (um reflexo). A reflexividade pode também alterar o grafo em si: $\\Phi$ pode acrescentar um novo nó ou aresta baseado em raciocínio não previsto inicialmente (por exemplo, criar um novo evento representando uma combinação inédita de ideias). Embora possa parecer radical, isso pode ser formalizado como expansão on-the-fly do grafo $G$; para fins de análise de estabilidade, porém, consideramos aqui que o grafo base e suas alternativas $L(e)$ já representam suficientemente o espaço de possibilidades, e que a reflexividade atua principalmente escolhendo trajetórias ou revertendo-as.

Operadores adaptativos: Este aspecto se refere a ajustes graduais do comportamento de transição com base em desempenho. Uma forma de modelar adaptatividade é imaginar que cada aresta $(e_i \\to e_j)$ tem um parâmetro (peso, probabilidade) que pode mudar. Exemplo: se repetidamente uma certa trajetória leva a impasses, o sistema pode reduzir o peso dessa transição, tornando-a menos provável de ser escolhida no futuro. Isso é análogo ao aprendizado reforçado ou à modificação de uma rede neural pela variação de pesos de conexão. No nosso contexto simbólico, podemos implementar adaptatividade definindo $\\Phi$ dependente de um conjunto de parâmetros $\\theta(t)$ que evoluem: $\\sigma(t+1) = \\Phi(\\sigma(t); \\theta(t))$ e $\\theta(t+1) = f(\\theta(t), \\sigma(t), \\text{feedback})$. Aqui, feedback representa alguma medida de sucesso ou fracasso da transição ocorrida. Esse mecanismo realiza um feedback adaptativo, que Norbert Wiener caracterizou como essencial para qualquer comportamento inteligente ou aprendizado: "se a informação retornada do desempenho é capaz de mudar o método e padrão geral de performance, temos um processo que podemos chamar de aprendizagem". No GEM, sempre que o runtime detecta via $m(t)$ que certo caminho foi ruim (por exemplo, resultou em contradição lógica ou meta de planejamento não atingida), os parâmetros associados a esse caminho são ajustados para evitar repetição do erro. Modelos matemáticos para $f$ podem se inspirar em dinâmica de gradiente (descida de gradiente minimizando um "erro cognitivo") ou em algoritmos de crédito/penalização (reforço). A adaptatividade, assim, garante plasticidade ao sistema – ele não é um autômato rígido, mas sim um sistema dinâmico não autônomo, cujo vetor de parâmetros $\\theta$ evolui conforme uma equação de adaptação (potencialmente estocástica).

# AS 4 CAMADAS DO GEM (CONCEITUAÇÃO CORRETA)

**.aje (Actions and Journey Events)**: Eventos e ações da jornada - eventos que marcam momentos significativos.

**.ire (Intelligible Relational Entities)**: Entidades-Clusters notadas a partir dos .aje relacionais e inteligíveis.

**.e (Eulerian Flows)**: Fluxos eulerianos - fluxos naturais que emergem dos dados nos quais indicam os comportamentos que podem fazer entender o estado atual do paciente.

**.epe (Emergenable Pathways)**: Caminhos emergenáveis - trajetórias de transformação potencial a partir da singularidade do paciente.`;

/**
 * Gera GEM completo (unificado .aje + .ire + .e)
 */
async function generateGEM(
  transcription: string,
  asl: any,
  vdlp: any
): Promise<any> {
  console.log(`   🧬 Gerando GEM (v3 com Emergenabilidade) via ${getSelectedRuntime()}...`);
  console.log(`      📤 Enviando inputs:`);
  console.log(`         • Transcrição: ${transcription.length.toLocaleString()} caracteres`);
  console.log(`         • ASL: ${JSON.stringify(asl).length.toLocaleString()} caracteres`);
  console.log(`         • VDLP (15 Dimensões ℳ): ${JSON.stringify(vdlp).length.toLocaleString()} caracteres`);
  console.log(`      ⏳ Processando...`);

  const userPrompt = `Aqui estão os dados para análise:

<transcription>
${transcription}
</transcription>

<asl_analysis>
${JSON.stringify(asl, null, 2)}
</asl_analysis>

<vdlp_scores>
${JSON.stringify(vdlp, null, 2)}
</vdlp_scores>

## Framework Overview

**Espaço Mental ℳ:** Espaço vetorial de 15 dimensões (v₁-v₁₅) conforme definido no *system prompt*.

**GEM Structure:**
- **.aje (Actions and Journey Events):** eventos e ações da jornada
- **.ire (Intelligible Relational Entities):** entidades-clusters relacionais inteligíveis (clusters)
- **.e (Eulerian Flows):** fluxos eulerianos (O que emergiu - Diagnóstico)
- **.epe (Emergenable Pathways):** caminhos emergenáveis

**Validation Requirements:**
- Global coherence score >0.85
- .aje events coherence >0.8
- .ire clusters density >0.75
- .e flows causal strength >0.8
- Align with RDoC/HiTOP/WHODAS/Big Five/PERMA/Network Theory frameworks where applicable

## Your Task

Before generating the final JSON output, work through your analysis systematically in your thinking block. It's OK for this section to be quite long.

<stage1_analysis_aje>
Identifique eventos (.aje - Actions and Journey Events) da transcrição. Para cada um:
- Cite o texto literal.
- Forneça um resumo semântico (semantic_summary).
- **Mapeie as Propriedades Dimensionais**: Calcule as 12+ propriedades (emotional_intensity, cognitive_complexity, affective_valence, agency, etc.) com base nos dados da ASL e VDLP. Use os escores v₁-v₁₅ do VDLP como guia direto.
- Mapeie Vetores Relacionais (relational_vectors).
</stage1_analysis_aje>

<stage2_clustering_ire>
Agrupe os eventos (by event_id) em clusters (.ire - Intelligible Relational Entities / entidades-clusters relacionais inteligíveis). Para cada um:
- Calcule a 'semantic_centrality' e 'relational_density'.
- Identifique as 'emergent_properties', incluindo o 'hiTOP_spectrum'.
- **IRE deve revelar a emergenabilidade** - estes clusters são a matéria-prima para .epe
</stage2_clustering_ire>

<stage3_flows_e>
Identifique 'Fluxos Eulerianos' (.e - Eulerian Flows) que representam as principais "Trajetórias Terapêuticas" *passadas* - os caminhos naturais que emergem.
- Mapeie 'source_events' e 'target_clusters'.
- Calcule a 'causal_strength'.
- **Mapeie para as 15 Dimensões ℳ**: Preencha 'mapped_dimensions' com os valores v₁, v₅, v₉, etc., relevantes para este fluxo.
- Esta é a camada de **Diagnóstico** (o que emergiu).
</stage3_flows_e>

<stage4_emergenable_pathways>
**A PARTE MAIS CRUCIAL**: Identifique 'Caminhos Emergenáveis' (.epe - Emergenable Pathways).
- Estes *não* são o que aconteceu, mas o que *pode* acontecer (a 'Emergenabilidade').
- Identifique os 'clusters de atrito' (ex: C2_ESCALATION_LOSS) - a "matéria-prima" do sofrimento.
- Identifique os 'clusters de alavancagem' (ex: C9_INTERVENTION_HOPE) - os pontos de potência.
- Proponha trajetórias clínicas que descrevem como a energia do atrito pode ser canalizada para a alavancagem.
- Esta é a camada de **Prognóstico e Potência** (o que pode emergir).
</stage4_emergenable_pathways>

<stage5_integration>
Calcule os 'key_insights' (insights) e o 'validation_score' final.
</stage5_integration>

## Required Output Structure

Your final response must be valid JSON with exactly this structure:

\`\`\`json
{
  "gem": {
    "aje": [
      {
        "event_id": "string",
        "timestamp_audio": "int (seconds)",
        "speaker": "string",
        "literal_text": "string",
        "semantic_summary": "string",
        "dimensional_properties": {
          "emotional_intensity": "float [0-1]",
          "cognitive_complexity": "float [0-1]",
          "temporal_significance": "float [0-1]",
          "semantic_centrality": "float [0-1]",
          "relational_density": "float [0-1]",
          "novelty_score": "float [0-1]",
          "coherence": "float [0-1]",
          "affective_valence": "float [-1,1]",
          "arousal_level": "float [0-1]",
          "certainty": "float [0-1]",
          "agency": "float [0-1]",
          "abstraction_level": "float [0-1]"
        },
        "paralinguistic_context": {
          "dominant_emotion": "string",
          "emotion_distribution": "object"
        },
        "relational_vectors": [
          {
            "target_event_id": "string",
            "influence_magnitude": "float [0-1]",
            "temporal_lag": "int (seconds)",
            "directionality": "string",
            "causal_strength": "float [0-1]",
            "semantic_similarity": "float [0-1]"
          }
        ]
      }
    ],
    "ire": [
      {
        "cluster_id": "string",
        "events": ["array of event_ids"],
        "semantic_centrality": "float [0-1]",
        "relational_density": "float [0-1]",
        "novelty_score": "float [0-1]",
        "emergent_properties": {
          "coherence": "float [0-1]",
          "hiTOP_spectrum": "string"
        },
        "inter_cluster_edges": [
          {
            "source_cluster": "string",
            "target_cluster": "string",
            "causal_strength": "float [0-1]",
            "semantic_similarity": "float [0-1]"
          }
        ]
      }
    ],
    "e": [
      {
        "flow_id": "string",
        "description": "DIAGNÓSTICO: Descrição da trajetória passada.",
        "source_events": ["array"],
        "target_clusters": ["array"],
        "causal_strength": "float [0-1]",
        "directionality": "string",
        "emergent_properties": {
          "trajectory_coherence": "float [0-1]",
          "attractor_stability": "float [0-1]"
        },
        "mapped_dimensions": {
          "v1_valencia": "float",
          "v5_temporal_distribution": "string (ex: 0.6 passado, 0.3 presente, 0.1 futuro)",
          "v9_agencia": "float",
          "v7_social": "float",
          "narrative": "string (resumo narrativo do fluxo)"
        }
      }
    ],
    "epe": [
      {
        "pathway_id": "string (ex: EPE_1_AGENCY_RECLAMATION)",
        "description": "PROGNÓSTICO: Descrição da trajetória de transformação potencial (Emergenabilidade).",
        "source_friction_clusters": ["array de cluster_ids (o sofrimento, a matéria-prima)"],
        "leverage_clusters": ["array de cluster_ids (a potência, a alavanca)"],
        "key_leverage_events": ["array de event_ids (os momentos-chave de 'abertura')"],
        "required_conditions": "string (O que é necessário para este fluxo se atualizar, ex: 'Foco terapêutico na aliança', 'Uso da tecnologia como ponte vocacional')",
        "emergenable_potential_score": "float [0-1]"
      }
    ]
  },
  "statistics": {
    "total_distinct_events": "int",
    "event_categories": "object",
    "semantic_clusters": "int",
    "key_articulation_points": "int"
  },
  "cross_references": {
    "aje_to_ire_mappings": "object",
    "cluster_flow_relationships": "object"
  },
  "key_insights": [
    "string (clinical insight 1)",
    "string (clinical insight 2)",
    "string (clinical insight 3)",
    "string (clinical insight 4)",
    "string (clinical insight 5)"
  ],
  "validation_score": "float [0-1]"
}
\`\`\`

## Important Notes

- Prioritize clinically or semantically significant nodes (major revelations, turning points, breakthrough moments, technical solutions, decision points)
- Integrate ASL emotional analysis and VDLP scores into your dimensional property calculations
- Adapt your semantic analysis to the actual domain and context of the conversation - don't force therapeutic interpretations on technical or other types of discussions
- Ensure your event extraction captures the real substance and flow of the conversation
- All coherence scores must meet the specified thresholds

**CRITICAL - OUTPUT FORMAT**:
- Return ONLY the JSON object
- Do NOT add explanations, comments or text after the JSON
- Do NOT use markdown code blocks
- Stop IMMEDIATELY after closing the JSON with }

Your final output should consist only of the JSON structure and should not duplicate or rehash any of the analysis work you performed in the thinking block.`;

  // Verificar se precisa chunking (baseado no tamanho combinado)
  const aslJson = JSON.stringify(asl, null, 2);
  const vdlpJson = JSON.stringify(vdlp, null, 2);
  const estimatedTokensTotal = estimateTokens(transcription + aslJson + vdlpJson);
  console.log(`      📊 Tokens estimados total: ${estimatedTokensTotal.toLocaleString()}`);

  let gemResult: any;

  if (estimatedTokensTotal > 50000) {
    // Texto grande - dividir apenas a transcrição (ASL e VDLP são resumos)
    const chunks = splitIntoChunks(transcription, {
      mode: "clinical-transcript",
      maxTokensPerChunk: 30000,
      overlapTokens: 1200,
      preserveBoundaries: true,
    });

    console.log(`      📦 Transcrição grande - dividindo em ${chunks.length} chunks`);

    // Processar cada chunk e consolidar GEMs
    const chunkGems = [];

    for (let i = 0; i < chunks.length; i++) {
      console.log(`      📝 Processando chunk ${i + 1}/${chunks.length}...`);

      const chunkUserPrompt = `Aqui estão os dados para análise (CHUNK ${i + 1}/${chunks.length}):

<transcription>
${chunks[i]}
</transcription>

<asl_analysis>
${aslJson}
</asl_analysis>

<vdlp_scores>
${vdlpJson}
</vdlp_scores>

## Framework Overview

**Espaço Mental ℳ:** Espaço vetorial de 15 dimensões (v₁-v₁₅) conforme definido no *system prompt*.

**GEM Structure:**
- **.aje (Actions and Journey Events):** Eventos e ações deste chunk da jornada
- **.ire (Intelligible Relational Events):** Eventos relacionais deste chunk
- **.e (Eulerian Flows):** Fluxos eulerianos deste chunk
- **.epe (Emergenable Pathways):** Caminhos emergenáveis identificados neste chunk

IMPORTANTE: Este é o chunk ${i + 1} de ${chunks.length}. Analise este segmento específico da transcrição.

## Your Task

${userPrompt.split('## Your Task')[1]}`;

      const chunkContent = await callLLM({
        temperature: TEMPERATURE,
        systemPrompt: SYSTEM_PROMPT,
        userPrompt: chunkUserPrompt,
        useCache: true,
      });
      if (chunkContent) {
        chunkGems.push(extractJSON(chunkContent, `gem_chunk_${i + 1}`));
      }
    }

    // Consolidar GEMs de todos os chunks
    console.log(`      🔄 Consolidando ${chunks.length} GEMs...`);

    const consolidatedGem = chunkGems[0];

    // Mesclar arrays de eventos, clusters, fluxos e pathways
    for (let i = 1; i < chunkGems.length; i++) {
      const chunk = chunkGems[i];

      if (consolidatedGem.gem && chunk.gem) {
        // Concatenar .aje eventos
        if (chunk.gem.aje) {
          consolidatedGem.gem.aje = [...(consolidatedGem.gem.aje || []), ...chunk.gem.aje];
        }

        // Concatenar .ire clusters (renumerar IDs para evitar conflitos)
        if (chunk.gem.ire) {
          consolidatedGem.gem.ire = [...(consolidatedGem.gem.ire || []), ...chunk.gem.ire];
        }

        // Concatenar .e flows
        if (chunk.gem.e) {
          consolidatedGem.gem.e = [...(consolidatedGem.gem.e || []), ...chunk.gem.e];
        }

        // Concatenar .epe pathways
        if (chunk.gem.epe) {
          consolidatedGem.gem.epe = [...(consolidatedGem.gem.epe || []), ...chunk.gem.epe];
        }
      }
    }

    gemResult = consolidatedGem;
  } else {
    // Texto pequeno - processar diretamente
    const content = await callLLM({
      temperature: TEMPERATURE,
      systemPrompt: SYSTEM_PROMPT,
      userPrompt,
      useCache: true,
    });

    // Log de tokens via Gateway
    console.log(`      ✅ Resposta recebida!`);

    if (content) {
      gemResult = extractJSON(content, "gem");
    } else {
      throw new Error("Resposta inválida do Claude via Gateway");
    }
  }

  return gemResult;
}

/**
 * Encontra tríades completas (transcription + ASL + VDLP)
 */
interface Triad {
  transcriptionPath: string;
  aslPath: string;
  vdlpPath: string;
  patientId: string;
  sessionId: string;
  gemPath: string;
  baseFilename: string;
}

function findCompleteTriads(): Triad[] {
  return listAllPatientSessionWorkspaces()
    .filter((session) => existsSync(session.transcriptionPath) && existsSync(session.aslPath) && existsSync(session.vdlpPath))
    .map((session) => ({
      transcriptionPath: session.transcriptionPath,
      aslPath: session.aslPath,
      vdlpPath: session.vdlpPath,
      patientId: session.patientId,
      sessionId: session.id,
      gemPath: session.gemPath,
      baseFilename: session.id,
    }));
}

/**
 * Processa uma tríade com verificação de existência
 */
async function processTriad(triad: Triad, skipExisting: boolean): Promise<boolean> {
  console.log(`\n${"=".repeat(80)}`);
  console.log(`📊 ${triad.patientId}/${triad.baseFilename}`);
  console.log(`${"=".repeat(80)}\n`);

  const gemPath = triad.gemPath;

  // Verificar se já existe
  if (existsSync(gemPath)) {
    if (skipExisting) {
      console.log(`   ⏭️  GEM já existe - PULANDO`);
      return false;
    } else {
      console.log(`   ⚠️  GEM já existe - REPROCESSANDO`);
    }
  }

  const transcriptionData = JSON.parse(
    readFileSync(triad.transcriptionPath, "utf-8")
  );
  const aslData = JSON.parse(readFileSync(triad.aslPath, "utf-8"));
  const vdlpData = JSON.parse(readFileSync(triad.vdlpPath, "utf-8"));

  const transcription =
    transcriptionData.transcription_corrected ||
    transcriptionData.transcricao ||
    transcriptionData.transcription_original ||
    transcriptionData.content ||
    transcriptionData.text ||
    "";
  console.log(`   📝 Transcrição: ${transcription.length} caracteres`);

  try {
    const gemData = await generateGEM(transcription, aslData, vdlpData);

    writeFileSync(gemPath, JSON.stringify(gemData, null, 2), "utf-8");
    refreshPatientSessionStatus(triad.patientId, triad.sessionId);

    console.log(`   ✅ GEM salvo: ${gemPath}`);
    console.log(
      `      • Eventos (.aje): ${gemData.gem?.aje?.length || 0}`
    );
    console.log(
      `      • Clusters (.ire): ${gemData.gem?.ire?.length || 0}`
    );
    console.log(
      `      • Fluxos Diag. (.e): ${gemData.gem?.e?.length || 0}`
    );
    console.log(
      `      • Potência Prog. (.epe): ${gemData.gem?.epe?.length || 0}`
    );
    console.log(
      `      • Validação: ${((gemData.validation_score || 0) * 100).toFixed(1)}%`
    );
    return true;
  } catch (error: any) {
    console.error(`   ❌ Erro ao gerar GEM:`, error.message);
    return false;
  }
}

/**
 * Main
 */
async function main() {
  console.log(`\n${"=".repeat(80)}`);
  console.log(`🧬 HEALTHOS GEM - Grafo do Espaço-Campo Mental (v3 com Emergenabilidade)`);
  console.log(`${"=".repeat(80)}`);
  console.log(`\n💡 Runtime LLM: ${getSelectedRuntime()}`);
  console.log(`🔬 Framework: ℳ (15D) + Emergenabilidade`);
  console.log(`📊 Temperature: ${TEMPERATURE}`);

  const completeTriads = findCompleteTriads();

  if (completeTriads.length === 0) {
    console.log(`\n⚠️  Nenhuma tríade completa encontrada!`);
    console.log(`\nCada paciente precisa ter arquivos com a mesma data:`);
    console.log(`  • sessions/<sessao>/source/transcription.json`);
    console.log(`  • sessions/<sessao>/analysis/asl.json`);
    console.log(`  • sessions/<sessao>/analysis/vdlp.json`);
    process.exit(0);
  }

  // Verificar quantos já foram processados
  const existingGems = completeTriads.filter((t) => {
    return existsSync(t.gemPath);
  });

  console.log(`\n📂 Encontradas ${completeTriads.length} tríade(s) completa(s):`);
  console.log(`   ✅ ${existingGems.length} já processadas`);
  console.log(`   🆕 ${completeTriads.length - existingGems.length} pendentes\n`);

  for (let i = 0; i < completeTriads.length; i++) {
    const triad = completeTriads[i];
    const status = existsSync(triad.gemPath) ? "✅" : "🆕";
    console.log(`   ${status} ${i + 1}. ${triad.patientId}/${triad.baseFilename}`);
  }

  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const selection = await new Promise<string>((resolve) => {
    console.log(`\n${"=".repeat(80)}`);
    console.log(`📋 OPÇÕES DE PROCESSAMENTO`);
    console.log(`${"=".repeat(80)}\n`);
    console.log(`a. Processar TODAS as ${completeTriads.length} tríades (pula já processadas)`);
    console.log(`r. REPROCESSAR TODAS (sobrescreve existentes)`);
    console.log(`n. Processar apenas ${completeTriads.length - existingGems.length} NOVAS`);
    console.log(
      `1-${completeTriads.length}. Processar tríade específica (digite o número)\n`
    );
    rl.question("→ Escolha: ", resolve);
  });

  rl.close();

  console.log(`\n${"=".repeat(80)}\n`);

  let triadsToProcess: typeof completeTriads = [];
  let skipExisting = true;

  if (selection.toLowerCase() === "a" || selection.trim() === "") {
    triadsToProcess = completeTriads;
    skipExisting = true;
  } else if (selection.toLowerCase() === "r") {
    triadsToProcess = completeTriads;
    skipExisting = false;
  } else if (selection.toLowerCase() === "n") {
    triadsToProcess = completeTriads.filter((t) => {
      return !existsSync(t.gemPath);
    });
    skipExisting = false;
  } else {
    const index = parseInt(selection) - 1;
    if (index >= 0 && index < completeTriads.length) {
      triadsToProcess = [completeTriads[index]];
      skipExisting = false; // Sempre reprocessa quando selecionado individualmente
    } else {
      console.log(`❌ Seleção inválida: ${selection}`);
      process.exit(1);
    }
  }

  if (triadsToProcess.length === 0) {
    console.log(`\n✅ Nenhuma tríade nova para processar!`);
    process.exit(0);
  }

  const startTime = Date.now();
  let processed = 0;
  let skipped = 0;
  let errors = 0;

  for (let i = 0; i < triadsToProcess.length; i++) {
    const triad = triadsToProcess[i];
    console.log(`\n[${i + 1}/${triadsToProcess.length}]`);

    const success = await processTriad(triad, skipExisting);
    if (success) {
      processed++;
    } else if (skipExisting) {
      skipped++;
    } else {
      errors++;
    }
  }

  const elapsed = ((Date.now() - startTime) / 1000 / 60).toFixed(1);
  const avgTime = ((Date.now() - startTime) / 1000 / processed).toFixed(1);

  console.log(`\n${"=".repeat(80)}`);
  console.log(`✅ PROCESSAMENTO GEM CONCLUÍDO`);
  console.log(`${"=".repeat(80)}`);
  console.log(`   📊 Estatísticas:`);
  console.log(`      • Processados: ${processed}`);
  if (skipped > 0) console.log(`      • Pulados: ${skipped}`);
  if (errors > 0) console.log(`      • Erros: ${errors}`);
  console.log(`      • Tempo total: ${elapsed}min`);
  if (processed > 0) console.log(`      • Tempo médio: ${avgTime}s/tríade`);
  console.log(`${"=".repeat(80)}\n`);
}

main();
