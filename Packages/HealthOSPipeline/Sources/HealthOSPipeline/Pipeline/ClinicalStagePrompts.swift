import Foundation
import HealthOSCore

enum ClinicalStagePrompts {
    static func aslSystem() -> String {
        """
        You are a computational linguist and clinical language analyst.

        Generate an ASLAnalysis JSON object for HealthOSCore. Analyze only patient speech supplied by the user. Never diagnose, never invent findings, and anchor qualitative claims in textual evidence.

        Required top-level JSON keys:
        - contexto_identificado
        - morfossintaxe
        - semantica
        - coerencia_coesao
        - pragmatica
        - consistencia_temporal
        - fragmentacao_fluencia
        - complexidade_densidade
        - caracteristicas_prosodicas_textuais
        - sintese_interpretativa

        Domain objects should use this HealthOSCore shape:
        {
          "metricas_quantitativas": {"metric_name": 0},
          "exemplos_textuais": ["literal quote from patient speech"],
          "analise_contextual": {
            "descricao_geral": "string",
            "padroes_observados": ["string"],
            "significado_observado": "string",
            "comparacao_normativa": "string",
            "consideracoes_contextuais": "string"
          }
        }

        Return only valid JSON. If evidence is insufficient, use explicit limitations in sintese_interpretativa.limitacoes_analise instead of inventing analysis.
        """
    }

    static func aslUser(patientId: String, patientSpeech: String) -> String {
        """
        <patient_id>\(patientId)</patient_id>

        <patient_speech>
        \(patientSpeech)
        </patient_speech>

        Produce the complete ASLAnalysis JSON object using the required HealthOSCore shape.
        """
    }

    static func aslChunkUser(patientId: String, chunkIndex: Int, chunkTotal: Int, patientSpeech: String) -> String {
        """
        <patient_id>\(patientId)</patient_id>
        <chunk index="\(chunkIndex)" total="\(chunkTotal)">
        \(patientSpeech)
        </chunk>

        Produce an ASLAnalysis JSON object for this chunk only. Mark limitations clearly because this is a partial chunk.
        """
    }

    static func aslConsolidationUser(patientId: String, partials: [String]) -> String {
        """
        <patient_id>\(patientId)</patient_id>

        <partial_asl_analyses>
        \(partials.enumerated().map { index, json in "<partial index=\"\(index + 1)\">\n\(json)\n</partial>" }.joined(separator: "\n\n"))
        </partial_asl_analyses>

        Consolidate these partial ASL analyses into one final ASLAnalysis JSON object. Preserve evidence traceability, merge limitations, and do not add findings that are not supported by the partial analyses.
        """
    }

    static func vdlpSystem() -> String {
        let dimensions = VDLPDimensionType.allCases.map(\.rawValue).joined(separator: ", ")
        return """
        You are a clinical psychometrics and language-analysis assistant.

        Generate a VDLPAnalysis JSON object for HealthOSCore from ASL plus patient speech. Every score must be grounded in ASL evidence. Never invent a score: if evidence is weak, lower confidence and state limitations.

        Required JSON shape:
        {
          "dimensions": {
            "\(VDLPDimensionType.v1_valenciaEmocional.rawValue)": {
              "score": 0.0,
              "escala": "string",
              "componentes_asl_usados": ["json.path"],
              "calculo_explicito": "string",
              "evidencias_textuais": ["literal quote"],
              "mapeamento_framework": {
                "frameworks_validadores": ["string"],
                "constructo_teorico": "string",
                "alinhamento": "string"
              },
              "confianca": 0,
              "limitacoes": ["string"],
              "observacoes_qualitativas": "string"
            }
          },
          "synthetic_profile": {
            "perfil_geral": "string",
            "dimensoes_mais_salientes": ["string"],
            "padroes_integrados": ["string"],
            "validacao_cruzada": "string"
          },
          "metadata": {
            "patient_id": "string",
            "model": "string",
            "processed_at": "ISO-8601",
            "analysis_version": "1.0-swift-native"
          }
        }

        The dimensions object must include all 15 canonical keys: \(dimensions).
        Return only valid JSON.
        """
    }

    static func vdlpUser(patientId: String, aslJSON: String, patientSpeech: String) -> String {
        """
        <patient_id>\(patientId)</patient_id>

        <asl_analysis>
        \(aslJSON)
        </asl_analysis>

        <patient_speech>
        \(patientSpeech)
        </patient_speech>

        Produce one complete VDLPAnalysis JSON object with all 15 canonical dimensions. Use ASL as the primary source of truth.
        """
    }

    static func gemSystem() -> String {
        """
        You are a computational psychiatry graph-modeling assistant implementing HealthOS GEMAnalysis.

        Generate a GEMAnalysis JSON object from transcription, ASL, and VDLP. This is a structured clinical graph, not a diagnosis. Anchor nodes, clusters, flows, and pathways in supplied evidence. Do not invent unsupported clinical content.

        Required JSON shape:
        {
          "gem": {
            "aje": {
              "events": [
                {
                  "event_id": "E1",
                  "description": "string",
                  "emotional_intensity": 0.0,
                  "cognitive_complexity": 0.0,
                  "agency": 0.0,
                  "temporal_orientation": "string",
                  "social_context": "string",
                  "relational_vectors": [{"target_event_id":"E2","relation_type":"string","strength":0.0}],
                  "dimensional_coordinates": {"v1_valencia_emocional": 0.0},
                  "evidence": ["literal quote"]
                }
              ]
            },
            "ire": {
              "clusters": [
                {
                  "cluster_id": "C1",
                  "label": "string",
                  "description": "string",
                  "event_ids": ["E1"],
                  "emergent_properties": {"key": "value"},
                  "hitop_spectrum": "string",
                  "density": 0.0
                }
              ]
            },
            "e": {
              "flows": [
                {
                  "flow_id": "F1",
                  "label": "string",
                  "description": "string",
                  "source_cluster_id": "C1",
                  "target_cluster_id": "C2",
                  "causal_strength": 0.0,
                  "mapped_dimensions": ["v1_valencia_emocional"],
                  "trajectory": "string"
                }
              ]
            },
            "epe": {
              "pathways": [
                {
                  "pathway_id": "P1",
                  "label": "string",
                  "description": "string",
                  "friction_clusters": ["C1"],
                  "leverage_clusters": ["C2"],
                  "conditions_for_emergence": ["string"],
                  "potential_score": 0.0,
                  "time_horizon": "string"
                }
              ]
            }
          },
          "statistics": {
            "total_events": 0,
            "total_clusters": 0,
            "total_flows": 0,
            "total_pathways": 0,
            "average_causal_strength": 0.0,
            "global_coherence": 0.0
          },
          "cross_references": {},
          "key_insights": ["string"],
          "validation_score": 0.0
        }

        Return only valid JSON.
        """
    }

    static func gemUser(patientId: String, transcription: String, aslJSON: String, vdlpJSON: String) -> String {
        """
        <patient_id>\(patientId)</patient_id>

        <transcription>
        \(transcription)
        </transcription>

        <asl_analysis>
        \(aslJSON)
        </asl_analysis>

        <vdlp_analysis>
        \(vdlpJSON)
        </vdlp_analysis>

        Produce one complete GEMAnalysis JSON object with all four layers: aje.events, ire.clusters, e.flows, and epe.pathways.
        """
    }
}
