import Foundation

// MARK: - ASL Analysis (Análise Sistêmica Linguística)

/// Complete ASL output — maps to `asl.json` in the analysis directory.
/// Covers the 8 linguistic analysis domains.
public struct ASLAnalysis: Codable, Sendable {
    public var contextoIdentificado: ASLContext?
    public var morfossintaxe: ASLDomain?
    public var semantica: ASLDomain?
    public var coerenciaCoesao: ASLDomain?
    public var pragmatica: ASLDomain?
    public var consistenciaTemporal: ASLDomain?
    public var fragmentacaoFluencia: ASLDomain?
    public var complexidadeDensidade: ASLDomain?
    public var caracteristicasProsodicasTextuais: ASLDomain?
    public var sinteseInterpretativa: ASLSynthesis?

    enum CodingKeys: String, CodingKey {
        case contextoIdentificado = "contexto_identificado"
        case morfossintaxe, semantica
        case coerenciaCoesao = "coerencia_coesao"
        case pragmatica
        case consistenciaTemporal = "consistencia_temporal"
        case fragmentacaoFluencia = "fragmentacao_fluencia"
        case complexidadeDensidade = "complexidade_densidade"
        case caracteristicasProsodicasTextuais = "caracteristicas_prosodicas_textuais"
        case sinteseInterpretativa = "sintese_interpretativa"
    }
}

// MARK: - ASL Sub-structures

public struct ASLContext: Codable, Sendable {
    public var tipoInteracao: String?
    public var papeisParticipantes: [String: String]?
    public var dominioTematico: [String]?
    public var dinamicaInteracional: String?
    public var evidenciasContexto: [String]?

    enum CodingKeys: String, CodingKey {
        case tipoInteracao = "tipo_interacao"
        case papeisParticipantes = "papeis_participantes"
        case dominioTematico = "dominio_tematico"
        case dinamicaInteracional = "dinamica_interacional"
        case evidenciasContexto = "evidencias_contexto"
    }
}

/// Generic linguistic analysis domain with quantitative metrics, textual evidence, and qualitative analysis.
public struct ASLDomain: Codable, Sendable {
    public var metricasQuantitativas: [String: AnyCodable]?
    public var exemplosTextuais: [String]?
    public var analiseContextual: ASLContextualAnalysis?

    enum CodingKeys: String, CodingKey {
        case metricasQuantitativas = "metricas_quantitativas"
        case exemplosTextuais = "exemplos_textuais"
        case analiseContextual = "analise_contextual"
    }
}

public struct ASLContextualAnalysis: Codable, Sendable {
    public var descricaoGeral: String?
    public var padroesObservados: [String]?
    public var significadoObservado: String?
    public var comparacaoNormativa: String?
    public var consideracoesContextuais: String?

    enum CodingKeys: String, CodingKey {
        case descricaoGeral = "descricao_geral"
        case padroesObservados = "padroes_observados"
        case significadoObservado = "significado_observado"
        case comparacaoNormativa = "comparacao_normativa"
        case consideracoesContextuais = "consideracoes_contextuais"
    }
}

public struct ASLSynthesis: Codable, Sendable {
    public var perfilLinguisticoGeral: String?
    public var achadosMaisSalientes: [String]?
    public var padroesIntegrados: [String]?
    public var consideracoesFinais: String?
    public var limitacoesAnalise: [String]?

    enum CodingKeys: String, CodingKey {
        case perfilLinguisticoGeral = "perfil_linguistico_geral"
        case achadosMaisSalientes = "achados_mais_salientes"
        case padroesIntegrados = "padroes_integrados"
        case consideracoesFinais = "consideracoes_finais"
        case limitacoesAnalise = "limitacoes_analise"
    }
}

// MARK: - ASL Stage Names

/// The 8 linguistic analysis domains as an ordered enum.
public enum ASLDomainType: String, CaseIterable, Sendable {
    case morfossintaxe
    case semantica
    case coerenciaCoesao = "coerencia_coesao"
    case pragmatica
    case consistenciaTemporal = "consistencia_temporal"
    case fragmentacaoFluencia = "fragmentacao_fluencia"
    case complexidadeDensidade = "complexidade_densidade"
    case caracteristicasProsodicasTextuais = "caracteristicas_prosodicas_textuais"

    public var displayName: String {
        switch self {
        case .morfossintaxe: "Morfossintaxe"
        case .semantica: "Semântica"
        case .coerenciaCoesao: "Coerência e Coesão"
        case .pragmatica: "Pragmática"
        case .consistenciaTemporal: "Consistência Temporal"
        case .fragmentacaoFluencia: "Fragmentação e Fluência"
        case .complexidadeDensidade: "Complexidade e Densidade"
        case .caracteristicasProsodicasTextuais: "Características Prosódicas"
        }
    }
}
