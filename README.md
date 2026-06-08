# 🧠 MentalHealthOS

> **Ecossistema modular de inteligência clínica para saúde mental** — orquestrado por agentes LLM, com pipelines de processamento, interfaces nativas (macOS + CLI) e runtime multi-modelo.

O **MentalHealthOS** (HealthOS) integra modelos de linguagem (Claude, Codex), fluxos de processamento clínico e interfaces nativas em uma plataforma única, projetada para oferecer a profissionais e pacientes um ambiente seguro e auditável para transcrições, análises linguísticas, revisões clínicas e acompanhamento longitudinal.

---

## 📑 Índice

- [Ecossistema](#-ecossistema-mindmap)
- [Arquitetura do Sistema](#-arquitetura-do-sistema)
- [Pacotes Swift (SwiftPM)](#-estrutura-de-pacotes-swift-swiftpm)
- [Catálogo de Agentes](#-catálogo-de-agentes)
- [Workflow Multiagente](#-workflow-multiagente)
- [Roteamento de Intenções](#-roteamento-de-intenções)
- [Pipeline Clínico](#-pipeline-clínico)
- [Estágios do Pipeline](#-estágios-do-pipeline-gantt)
- [LLM Runtime](#-llm-runtime)
- [Chunking Clínico Adaptativo](#-chunking-clínico-adaptativo)
- [Modelagem de Dados](#-modelagem-de-dados)
- [Workspace do Profissional](#-workspace-do-profissional)
- [Workspace do Paciente](#-workspace-do-paciente)
- [Fluxo de Estado no macOS](#-fluxo-de-estado-no-macos-swiftui)
- [Ciclo de Vida de uma Sessão](#-ciclo-de-vida-de-uma-sessão)
- [Telemetria e Eventos](#-telemetria-e-eventos)
- [Segurança e Privacidade](#-segurança-e-privacidade)
- [Como Executar](#-como-executar)
- [Roadmap](#-roadmap)

---

## 🗺️ Ecossistema (Mindmap)

```mermaid
mindmap
  root((MentalHealthOS))
    Interfaces::br::<i>Pontos de entrada e interação</i>
      HealthOSApp macOS::br::<i>Interface nativa em SwiftUI</i>
      HealthOSCLI::br::<i>Interação rápida via Terminal</i>
      chat‑cli::br::<i>Modo interativo e multiagente</i>
    Motor Clínico::br::<i>Processamento e análise de dados</i>
      PipelineEngine::br::<i>Orquestrador determinístico de jobs</i>
      Transcription Whisper::br::<i>Transcrição local de sessões</i>
      LLM Stage Runners::br::<i>Executores de estágios cognitivos</i>
      Chunking Adaptativo::br::<i>Divisão inteligente mantendo contexto</i>
    Agentes LLM::br::<i>Especialistas cognitivos em loop</i>
      ConversationOrchestrator::br::<i>Roteamento de tarefas e estados</i>
      ContextArchitect::br::<i>Montagem dinâmica de referências</i>
      ClinicalSynthesizer::br::<i>Geração de insights clínicos</i>
      RiskSafetyReviewer::br::<i>Auditoria de segurança e compliance</i>
      PipelineOperator::br::<i>Execução e correção de código/scripts</i>
      PatientAgentBuilder::br::<i>Scaffolding de agentes individuais</i>
      QAValidator::br::<i>Validação de schemas e testes</i>
    Runtimes::br::<i>Abstração de modelos</i>
      ClaudeAPI::br::<i>Chamadas via API da Anthropic</i>
      ClaudeCode::br::<i>Agente com ferramentas locais</i>
      Codex::br::<i>Execução local com ChatGPT</i>
    Dados e Workspaces::br::<i>Estrutura de diretórios e contratos</i>
      Profissionais::br::<i>Config, memórias e logs do terapeuta</i>
      Pacientes::br::<i>Dossiês, index de sessões e artefatos</i>
      Traces e Eventos::br::<i>Logs estruturados de telemetria</i>
```

---

## 🏗️ Arquitetura do Sistema

Arquitetura híbrida e modular: pacotes Swift nativos para UI e orquestração base, runtimes TypeScript/Node.js para agentes e processamento, integração com LLMs via providers intercambiáveis.

```mermaid
graph TD
    subgraph Interfaces ["🖥️ Interfaces de Usuário"]
        A["HealthOSApp<br/>SwiftUI macOS"]
        B["HealthOSCLI<br/>Command Line"]
        CC["chat-cli<br/>Terminal interativo"]
    end

    subgraph CoreSwift ["🔧 Ecossistema Swift"]
        C["HealthOSUI<br/>Componentes de UI"]
        D["HealthOSTerminal<br/>Bridge CLI"]
        E["HealthOSPipeline<br/>Pipeline Engine"]
        F["HealthOSAgents<br/>Orquestração"]
        G["HealthOSCore<br/>Modelos & Config"]
    end

    subgraph TSRuntime ["⚡ Runtimes TypeScript"]
        H["src/lib/llm/runtime.ts<br/>Gateway unificado"]
        I["src/lib/agents/<br/>Orchestrator & Workflows"]
        J["src/agents/catalog.ts<br/>Catálogo HealthOS"]
    end

    subgraph LLMProviders ["🤖 LLM Providers"]
        K["ClaudeAPI<br/>Anthropic SDK"]
        L["ClaudeCode<br/>Agent SDK"]
        M["Codex<br/>codex exec"]
    end

    subgraph DataLayer ["💾 Dados"]
        N["patients/<br/>Dossiês Clínicos"]
        O["professionals/<br/>Workspaces Profissionais"]
        P["runs/<br/>Traces & Telemetria"]
        Q["prompts/<br/>Templates Clínicos"]
    end

    A --> C
    A --> E
    A --> F
    A --> G

    B --> D
    B --> E
    B --> F
    B --> G

    CC --> H
    CC --> I
    CC --> J

    E --> H
    F --> H
    H --> K
    H --> L
    H --> M

    I --> J
    I --> N
    I --> O
    I --> P
    J --> Q
```

---

## 📦 Estrutura de Pacotes Swift (SwiftPM)

Separação de responsabilidades no backend Swift através de pacotes modulares:

```mermaid
classDiagram
    class HealthOSApp {
        +ContentView
        +AppState : ObservableObject
        +HealthOSApp : @main
    }
    class HealthOSCLI {
        +main()
    }
    class HealthOSCore {
        +Session
        +ConsultationIntake
        +WorkspaceManager
        +Defaults config
        +LLMRuntimePreference
    }
    class HealthOSPipeline {
        +PipelineEngine
        +LLMStageRunners
        +TranscriptionProvider
        +ClaudeCodeRunner
    }
    class HealthOSAgents {
        +ConversationOrchestrator
        +AgentRegistry
        +ChatContext
        +ChatCLI
        +WorkflowDetection
        +LocalToolDescriptors
    }
    class HealthOSUI {
        +AgentListView
        +ConversationView
        +MessageBubble
    }
    class HealthOSTerminal {
        +TerminalBridge
        +PipelineStageRunner
    }

    HealthOSApp --> HealthOSUI : usa
    HealthOSApp --> HealthOSPipeline : usa
    HealthOSApp --> HealthOSAgents : usa
    HealthOSApp --> HealthOSCore : usa
    HealthOSCLI --> HealthOSTerminal : usa
    HealthOSCLI --> HealthOSPipeline : usa
    HealthOSCLI --> HealthOSAgents : usa
    HealthOSUI --> HealthOSCore : depende
    HealthOSPipeline --> HealthOSCore : depende
    HealthOSAgents --> HealthOSCore : depende
    HealthOSTerminal --> HealthOSCore : depende
```

---

## 🤖 Catálogo de Agentes

Agentes HealthOS versionados em `src/agents/catalog.ts`, organizados por categoria e disponibilidade:

```mermaid
graph LR
    subgraph Active ["✅ Agentes Ativos"]
        CA["🏗️ context-architect<br/><i>Governança</i>"]
        PO["⚙️ pipeline-operator<br/><i>Pipeline</i>"]
        CS["🩺 clinical-synthesizer<br/><i>Clínico</i>"]
        RS["🛡️ risk-safety-reviewer<br/><i>Segurança Clínica</i>"]
        QA["✅ qa-validator<br/><i>QA</i>"]
    end

    subgraph Scenario ["🔧 Agentes por Cenário"]
        PAB["👤 patient-agent-builder<br/><i>Agentes de Paciente</i>"]
    end

    subgraph External ["🌐 Agentes Externos"]
        direction TB
        EX1["context-architect"]
        EX2["doublecheck"]
        EX3["se-responsible-ai-code"]
        EX4["se-security-reviewer"]
        EX5["project-documenter"]
        EX6["planner"]
        EX7["ai-team-dev / qa / producer"]
    end

    CA -.->|"monta contexto"| CS
    CS -.->|"revisão"| RS
    PO -.->|"executa"| QA
    PAB -.->|"cria"| CS
```

---

## 🔄 Workflow Multiagente

O `ConversationOrchestrator` é o coração da comunicação. Recebe intenções, roteia para agentes especializados, garante revisão de segurança e grava telemetria.

```mermaid
sequenceDiagram
    participant User as 👤 Usuário / Profissional
    participant CLI as chat-cli
    participant Orch as ConversationOrchestrator
    participant Ctx as ContextAgent
    participant Clinical as Agente Clínico<br/>PatientCare / SessionPrep
    participant Safety as SafetyReviewAgent
    participant LLM as LLM Runtime<br/>Claude / Codex
    participant Trace as Telemetria<br/>runs/trace.jsonl

    User->>CLI: Envia mensagem/tarefa
    CLI->>Orch: createTask(input)
    activate Orch

    Orch->>Trace: message.received

    Orch->>Ctx: Solicita contexto (histórico, artefatos)
    activate Ctx
    Ctx->>Ctx: collectContextRefs(patientId, sessionId)
    Ctx-->>Orch: AgentResult + referências
    deactivate Ctx
    Orch->>Trace: agent.completed (context-agent)

    Orch->>Clinical: Roteia intenção (AgentTask)
    activate Clinical
    Clinical->>LLM: Injeta definições + prompt clínico
    LLM-->>Clinical: Rascunho de resposta/análise
    Clinical-->>Orch: AgentResult
    deactivate Clinical
    Orch->>Trace: agent.completed (clinical-agent)

    alt Revisão necessária
        Orch->>Safety: Solicita revisão de risco
        activate Safety
        Safety->>LLM: Valida compliance e segurança
        LLM-->>Safety: Aprovação/Ajustes
        Safety-->>Orch: Resposta validada
        deactivate Safety
        Orch->>Trace: agent.completed (safety-review)
    end

    Orch-->>CLI: Resposta sintetizada
    CLI-->>User: Exibe resposta formatada
    deactivate Orch
```

---

## 🧭 Roteamento de Intenções

O `routeIntentToAgent()` analisa a entrada do usuário e direciona para o agente apropriado:

```mermaid
flowchart TD
    Input["📝 Entrada do Usuário"] --> Normalize["normalize(input)"]
    Normalize --> Check{Classificação}

    Check -->|"memória, /remember"| MA["memory-agent"]
    Check -->|"risco, suicídio, segurança"| RA["risk-check-agent"]
    Check -->|"preparar sessão"| SP["session-prep-agent"]
    Check -->|"longitudinal, evolução"| LR["longitudinal-reviewer-agent"]
    Check -->|"transcrição"| TA["transcription-agent"]
    Check -->|"fala do paciente"| SA["speech-attribution-agent"]
    Check -->|"ASL"| ASL["asl-agent"]
    Check -->|"VDLP"| VDLP["vdlp-agent"]
    Check -->|"GEM"| GEM["gem-agent"]
    Check -->|"pipeline"| TR["tool-runner-agent"]
    Check -->|"QA, teste"| QAA["qa-agent"]
    Check -->|"contexto"| CTX["context-agent"]
    Check -->|"fallback"| CONV["conversation-agent"]

    style Input fill:#4a9eff,color:#fff
    style CONV fill:#6c757d,color:#fff
    style RA fill:#dc3545,color:#fff
    style MA fill:#198754,color:#fff
```

---

## ⚙️ Pipeline Clínico

O módulo `HealthOSPipeline` controla a ingestão e transformação de dados clínicos:

```mermaid
stateDiagram-v2
    [*] --> Intake

    state Intake {
        AudioUpload --> Transcription : Whisper
        TextEntry --> Parsing
    }

    Intake --> Processing

    state Processing {
        Transcription --> DeterministicStage
        Parsing --> DeterministicStage
        DeterministicStage --> SpeechAttribution : Extrai fala do paciente
        SpeechAttribution --> ASL : Análise Sistêmica Linguagem
        ASL --> VDLP : Vetores Dimensões
        VDLP --> GEM : Grafo Espaço Mental
    }

    Processing --> Review

    state Review {
        GEM --> ClinicalSynthesis
        ClinicalSynthesis --> SafetyCheck
    }

    Review --> [*] : Artefatos Gerados
```

---

## 📅 Estágios do Pipeline (Gantt)

Paralelismo e sequenciamento de um fluxo de pipeline completo:

```mermaid
gantt
    title Pipeline Clínica — Fluxo de Execução
    dateFormat  HH:mm
    axisFormat  %H:%M

    section 🎤 Ingestão
    Upload de Áudio              :a1, 00:00, 2m
    Transcrição (Whisper)        :a2, after a1, 5m

    section 📝 Processamento
    Extração Determinística      :b1, after a2, 1m
    Fala do Paciente (speech)    :b2, after b1, 2m

    section 🧠 Análise LLM
    ASL — Análise Sistêmica      :c1, after b2, 4m
    VDLP — Vetores/Dimensões     :c2, after c1, 4m
    GEM — Grafo Espaço Mental    :c3, after c2, 5m

    section ✅ Validação
    Síntese Clínica              :d1, after c3, 2m
    Safety Review                :d2, after d1, 1m
    Geração de Artefatos         :d3, after d2, 1m
```

---

## 🔌 LLM Runtime

O sistema unifica três providers LLM através de `src/lib/llm/runtime.ts`:

```mermaid
graph TB
    subgraph Gateway ["🔌 Runtime Gateway"]
        RT["runtime.ts<br/>generateRuntimeText()"]
    end

    subgraph Providers ["🤖 Providers"]
        CA["claude-api.ts<br/>ClaudeAPI<br/><i>Anthropic SDK</i>"]
        CC["claude-code.ts<br/>ClaudeCode<br/><i>Agent SDK + Tools</i>"]
        CX["codex.ts<br/>Codex<br/><i>codex exec subprocess</i>"]
    end

    subgraph Config ["⚙️ Seleção"]
        ENV["HEALTHOS_LLM_RUNTIME<br/>--runtime flag<br/>/runtime comando"]
        NR["normalizeRuntime()"]
    end

    ENV --> NR
    NR --> RT
    RT -->|"ClaudeAPI"| CA
    RT -->|"ClaudeCode"| CC
    RT -->|"Codex"| CX

    subgraph Features ["📋 Capacidades"]
        CA -.-> F1["API direta, cache, temperatura"]
        CC -.-> F2["SDK com tools MCP, streaming"]
        CX -.-> F3["Subprocess local, herda login ChatGPT"]
    end
```

---

## 📐 Chunking Clínico Adaptativo

O sistema de chunking em `src/lib/llm/chunking.ts` prepara entradas para LLMs preservando contexto clínico:

```mermaid
flowchart LR
    subgraph Input ["📄 Entrada"]
        T["Transcrição<br/>Áudio"]
        A["ASL<br/>Análise"]
        V["VDLP<br/>Vetores"]
        G["GEM<br/>Grafo"]
    end

    subgraph Strategy ["🎯 Estratégia"]
        EST["estimateTokens(text)"]
        SC["splitIntoChunks()<br/><i>overlap zero</i>"]
        CCT["chunkClinicalText()<br/><i>overlap + metadados</i>"]
    end

    subgraph Modes ["📊 Modos"]
        M1["Processamento<br/>overlap: 0<br/>preserva parágrafos"]
        M2["clinical-transcript<br/>overlap: moderado<br/>preserva turnos"]
        M3["GEM Mode<br/>overlap: alto<br/>eventos longitudinais"]
    end

    T --> SC
    A --> CCT
    V --> CCT
    G --> CCT

    SC --> M1
    CCT --> M2
    CCT --> M3

    EST -.->|"planejamento"| SC
    EST -.->|"planejamento"| CCT
```

---

## 🗄️ Modelagem de Dados

Modelos principais mantidos pelo `HealthOSCore`, usados em todos os workspaces:

```mermaid
erDiagram
    PROFESSIONAL ||--o{ SESSION : conduz
    PATIENT ||--o{ SESSION : participa
    PATIENT ||--o{ PATIENT_AGENT : possui
    SESSION ||--|| CONSULTATION_INTAKE : contém
    SESSION ||--o{ TRANSCRIPTION : gera
    SESSION ||--o{ ANALYSIS : produz
    SESSION ||--o{ AGENT_EVENT : dispara
    ANALYSIS ||--|{ ASL_RESULT : inclui
    ANALYSIS ||--|{ VDLP_RESULT : inclui
    ANALYSIS ||--|{ GEM_RESULT : inclui

    PROFESSIONAL {
        UUID id
        String name
        String specialty
        String crp_crm
        JSON config
        Markdown memory
    }

    PATIENT {
        UUID id
        String name
        Date birthDate
        JSON clinicalSummary
        JSON sessionIndex
    }

    SESSION {
        UUID id
        Date startTime
        String status
        String patient_id FK
        String professional_id FK
    }

    CONSULTATION_INTAKE {
        UUID id
        String chiefComplaint
        String clinicalNotes
        JSON metadata
    }

    TRANSCRIPTION {
        UUID id
        String rawText
        String processedText
        String patientSpeech
        Int chunkCount
    }

    ANALYSIS {
        UUID id
        String sessionId FK
        DateTime createdAt
        String stage
    }

    ASL_RESULT {
        UUID id
        JSON systemicAnalysis
        String linguisticPatterns
    }

    VDLP_RESULT {
        UUID id
        JSON dimensions
        JSON vectors
        String thoughtPatterns
    }

    GEM_RESULT {
        UUID id
        JSON mentalSpaceGraph
        JSON nodes
        JSON edges
    }

    PATIENT_AGENT {
        UUID id
        String agentId
        Markdown careAgent
        String scope
    }

    AGENT_EVENT {
        UUID event_id
        String run_id
        String agent_id
        String kind
        String status
        String runtime
        DateTime started_at
    }
```

---

## 👨‍⚕️ Workspace do Profissional

Cada profissional tem um workspace isolado em `professionals/<id>/`:

```mermaid
graph TD
    subgraph ProfWorkspace ["📁 professionals/"]
        AP["active-professional.json"]

        subgraph DrWorkspace ["📁 dr-gustavo-mendes-e-silva/"]
            PC["professional-config.json<br/><i>identidade, registro, CRP</i>"]
            MEM["memory.md<br/><i>memória persistente</i>"]
            CHAT["chat-agent.md<br/><i>perfil conversacional</i>"]
            LOGS["logs/<br/><i>logs operacionais</i>"]
            TEL["telemetry/<br/><i>eventos e métricas</i>"]
            SESS["sessions/<br/><i>histórico de sessões CLI</i>"]
            ART["artifacts/<br/><i>arquivos gerados</i>"]
        end
    end

    AP -->|"active_professional_id"| DrWorkspace

    subgraph ChatCLI ["💬 chat-cli"]
        LOAD["Carrega config + memory + chat-agent"]
        SAVE["Grava resumo em sessions/YYYY-MM-DD.md"]
    end

    PC --> LOAD
    MEM --> LOAD
    CHAT --> LOAD
    LOAD --> SAVE
    SAVE --> SESS
```

---

## 👤 Workspace do Paciente

Dossiês clínicos organizados em `patients/<PAT_ID>/`:

```mermaid
graph TD
    subgraph PatientWorkspace ["📁 patients/"]
        subgraph Patient ["📁 PAT_ID/"]
            PJ["patient.json<br/><i>identidade + metadados + resumo</i>"]
            CA["care-agent.md<br/><i>agente declarativo</i>"]
            PM["patient-memory.md"]

            subgraph Sessions ["📁 sessions/"]
                subgraph S1 ["📁 SESSION_ID/"]
                    SI["session-info.json"]
                    AU["audio/<br/><i>áudio bruto</i>"]
                    TR["transcription/<br/><i>transcrição processada</i>"]

                    subgraph Analysis ["📁 analysis/"]
                        SP["patient-speech.json"]
                        ASL["asl-result.json"]
                        VDLP["vdlp-result.json"]
                        GEM["gem-result.json"]
                    end
                end
            end

            subgraph Agents ["📁 agents/"]
                AG1["risk-check.md"]
                AG2["session-prep.md"]
                AG3["longitudinal-reviewer.md"]
            end
        end
    end

    PJ -.->|"índice de sessões"| Sessions
    CA -.->|"instruções clínicas"| Agents
```

---

## 🔄 Fluxo de Estado no macOS (SwiftUI)

Como as Views do aplicativo macOS conversam com o estado reativo:

```mermaid
flowchart LR
    A(("👤 Eventos<br/>do Usuário")) --> B["ContentView"]
    B --> C{"AppState<br/>ObservableObject"}
    C -->|"Atualiza"| D["ConversationViewModel"]
    C -->|"Atualiza"| E["PipelineView"]
    D --> F["ConversationView"]
    F --> A
    E --> A
    C --> G[("CoreData<br/>Storage")]
    C --> H["AgentRegistry"]
    H --> I["WorkflowDetection"]
    I -->|"detecta workflow"| D
```

---

## 🔁 Ciclo de Vida de uma Sessão

Fluxo completo desde o upload de áudio até a análise final:

```mermaid
stateDiagram-v2
    [*] --> Created : Nova sessão criada

    state Created {
        [*] --> ConfigLoaded : Carrega profissional ativo
        ConfigLoaded --> PatientSelected : Seleciona paciente
    }

    Created --> Recording : Inicia gravação/upload

    state Recording {
        [*] --> AudioCapture
        AudioCapture --> AudioSaved : Salva em sessions/audio/
    }

    Recording --> Transcribing : npm run transcribe

    state Transcribing {
        [*] --> WhisperProcessing
        WhisperProcessing --> RawTranscript
        RawTranscript --> ProcessedTranscript : pipeline:process
    }

    Transcribing --> Analyzing : Pipeline de Análise

    state Analyzing {
        [*] --> SpeechExtraction : pipeline:speech
        SpeechExtraction --> ASLAnalysis : pipeline:asl
        ASLAnalysis --> VDLPAnalysis : pipeline:vdlp
        VDLPAnalysis --> GEMGeneration : pipeline:gem
    }

    Analyzing --> Reviewed : SafetyReview

    state Reviewed {
        [*] --> ClinicalSynthesis
        ClinicalSynthesis --> SafetyValidated
    }

    Reviewed --> Completed : Artefatos gravados
    Completed --> [*]
```

---

## 📊 Telemetria e Eventos

O sistema de telemetria grava todos os eventos de execução dos agentes:

```mermaid
flowchart TD
    subgraph EventTypes ["📋 Tipos de Evento (AgentEventKind)"]
        E1["message.received"]
        E2["agent.planned"]
        E3["agent.started"]
        E4["tool.started"]
        E5["tool.completed"]
        E6["tool.failed"]
        E7["artifact.created"]
        E8["review.requested"]
        E9["memory.proposed"]
        E10["memory.committed"]
        E11["agent.completed"]
        E12["agent.failed"]
    end

    subgraph Lifecycle ["🔄 Ciclo de Vida"]
        direction LR
        L1["planned"] --> L2["running"]
        L2 --> L3["completed"]
        L2 --> L4["failed"]
        L2 --> L5["blocked"]
    end

    subgraph Sinks ["💾 Destinos"]
        S1["runs/RUN_ID/trace.jsonl"]
        S2["professionals/ID/telemetry/"]
        S3["Console / Logs"]
    end

    E1 --> Lifecycle
    E3 --> Lifecycle
    Lifecycle --> S1
    Lifecycle --> S2
    Lifecycle --> S3
```

---

## 🛡️ Segurança e Privacidade

O HealthOS foi arquitetado com foco em segurança clínica e proteção de dados:

```mermaid
flowchart TB
    subgraph Camadas ["🔒 Camadas de Segurança"]
        direction TB
        C1["🛡️ SafetyReviewAgent<br/><i>Revisa toda resposta clínica sensível</i>"]
        C2["🔐 Memória Bloqueada por Padrão<br/><i>Somente /remember grava memória</i>"]
        C3["🏥 LGPD Compliance<br/><i>Dados minimizados por design</i>"]
        C4["🔑 Runtimes Locais<br/><i>Controle fino sobre contexto ingerido</i>"]
        C5["📋 Telemetria Auditável<br/><i>Trace append-only por run</i>"]
    end

    subgraph Revisao ["🔍 Fluxo de Revisão"]
        R1["Resposta do Agente"] --> R2{"Envolve<br/>risco clínico?"}
        R2 -->|"Sim"| R3["SafetyReviewAgent"]
        R3 --> R4["Valida:<br/>• Overclaim<br/>• Evidência<br/>• Privacidade<br/>• Conduta"]
        R4 --> R5["Resposta Ajustada"]
        R2 -->|"Não"| R6["Resposta Direta"]
    end

    subgraph MemPolicy ["💾 Política de Memória"]
        M1["Pedido conversacional"] --> M2{"Tipo"}
        M2 -->|"/remember texto"| M3["✅ Grava memória"]
        M2 -->|"inferência implícita"| M4["❌ Proposta/Confirmação"]
    end
```

---

## 🚀 Como Executar

### Pré-requisitos
- macOS 14+ (Sonoma ou superior)
- Xcode 16+ ou Swift 6 Toolchain
- Node.js 20+ (para dependências em `src/` e `chat-cli`)

### Instalação

```bash
# 1. Clone o repositório
git clone <repo-url>
cd mentalhealthos

# 2. Instale as dependências Node
npm install

# 3. Configure o profissional
npm run pipeline:config

# 4. Para o chat-cli interativo
npm run chat-cli

# 5. Para o menu principal
npm run menu
```

### Aplicação Nativa (Swift)

```bash
# Rodar a aplicação macOS
swift run HealthOSApp
# Ou abra o diretório no Xcode

# Rodar a CLI Swift
swift run HealthOSCLI
```

### Pipeline Clínico

```bash
# Transcrever áudio
npm run transcribe

# Processar transcrição
npm run pipeline:process

# Extrair fala do paciente
npm run pipeline:speech

# Análise Sistêmica da Linguagem
npm run pipeline:asl

# Vetores de Dimensões
npm run pipeline:vdlp

# Grafo Espaço Mental
npm run pipeline:gem
```

---

## 🗺️ Roadmap

```mermaid
timeline
    title MentalHealthOS — Evolução
    section Fundação
        Transcrição e Pipeline : Pipeline sequencial com LLM
        Agentes HealthOS : Catálogo versionado em src/agents
        Chat CLI : Interface conversacional com Claude/Codex
    section Atual
        Orchestrator Multiagente : ConversationOrchestrator com telemetria
        Workspace Profissional : Configuração, memória e sessões
        Chunking Adaptativo : Preservação de contexto clínico
        Runtime Multi-modelo : ClaudeAPI + ClaudeCode + Codex
    section Próximo
        NER Clínico Local : Chunking por entidades clínicas
        Índice Vetorial : Parent-child retrieval
        Patient-Facing Channels : Canais de comunicação com pacientes
        Avaliação de Qualidade : Métricas automáticas de chunk
```

---

## 📄 Licença

Projeto privado — todos os direitos reservados.

**Autor:** Dr. Gustavo Mendes e Silva
