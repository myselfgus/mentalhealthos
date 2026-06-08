import Foundation

// MARK: - VDLP Dimensions (Vetores de Dimensões Linguagem-Pensamento)

/// Complete VDLP output — maps to `vdlp.json` in the analysis directory.
/// The 15 dimensions of Mental Space ℳ.
public struct VDLPAnalysis: Codable, Sendable {
    public var dimensions: [String: VDLPDimension]?
    public var syntheticProfile: VDLPSyntheticProfile?
    public var metadata: VDLPMetadata?

    enum CodingKeys: String, CodingKey {
        case dimensions
        case syntheticProfile = "synthetic_profile"
        case metadata
    }
}

// MARK: - Individual Dimension

/// A single VDLP dimension extraction.
public struct VDLPDimension: Codable, Sendable {
    public var score: Double?
    public var escala: String?
    public var componentesASLUsados: [String]?
    public var calculoExplicito: String?
    public var evidenciasTextuais: [String]?
    public var mapeamentoFramework: VDLPFrameworkMapping?
    public var confianca: Int?
    public var limitacoes: [String]?
    public var observacoesQualitativas: String?

    enum CodingKeys: String, CodingKey {
        case score, escala
        case componentesASLUsados = "componentes_asl_usados"
        case calculoExplicito = "calculo_explicito"
        case evidenciasTextuais = "evidencias_textuais"
        case mapeamentoFramework = "mapeamento_framework"
        case confianca, limitacoes
        case observacoesQualitativas = "observacoes_qualitativas"
    }
}

public struct VDLPFrameworkMapping: Codable, Sendable {
    public var frameworksValidadores: [String]?
    public var constructoTeorico: String?
    public var alinhamento: String?

    enum CodingKeys: String, CodingKey {
        case frameworksValidadores = "frameworks_validadores"
        case constructoTeorico = "constructo_teorico"
        case alinhamento
    }
}

public struct VDLPSyntheticProfile: Codable, Sendable {
    public var perfilGeral: String?
    public var dimensoesMaisSalientes: [String]?
    public var padroesIntegrados: [String]?
    public var validacaoCruzada: String?

    enum CodingKeys: String, CodingKey {
        case perfilGeral = "perfil_geral"
        case dimensoesMaisSalientes = "dimensoes_mais_salientes"
        case padroesIntegrados = "padroes_integrados"
        case validacaoCruzada = "validacao_cruzada"
    }
}

public struct VDLPMetadata: Codable, Sendable {
    public var patientId: String?
    public var model: String?
    public var processedAt: String?
    public var analysisVersion: String?

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case model
        case processedAt = "processed_at"
        case analysisVersion = "analysis_version"
    }
}

// MARK: - The 15 Dimension Identifiers

/// Canonical identifiers for the 15 dimensions of Mental Space ℳ.
public enum VDLPDimensionType: String, CaseIterable, Sendable {
    case v1_valenciaEmocional = "v1_valencia_emocional"
    case v2_arousalAtivacao = "v2_arousal_ativacao"
    case v3_coerenciaNarrativa = "v3_coerencia_narrativa"
    case v4_complexidadeSintatica = "v4_complexidade_sintatica"
    case v5_orientacaoTemporal = "v5_orientacao_temporal"
    case v6_densidadeAutoreferencia = "v6_densidade_autoreferencia"
    case v7_orientacaoSocial = "v7_orientacao_social"
    case v8_flexibilidadeCognitiva = "v8_flexibilidade_cognitiva"
    case v9_sensoAgencia = "v9_senso_agencia"
    case v10_fragmentacaoDiscurso = "v10_fragmentacao_discurso"
    case v11_densidadeIdeias = "v11_densidade_ideias"
    case v12_marcadoresCerteza = "v12_marcadores_certeza"
    case v13_padroesConectividade = "v13_padroes_conectividade"
    case v14_comunicacaoPragmatica = "v14_comunicacao_pragmatica"
    case v15_prosodia = "v15_prosodia_afetacao"

    /// Meta-dimension group for this dimension.
    public var metaDimension: VDLPMetaDimension {
        switch self {
        case .v1_valenciaEmocional, .v2_arousalAtivacao,
             .v3_coerenciaNarrativa, .v4_complexidadeSintatica:
            return .affective
        case .v5_orientacaoTemporal, .v6_densidadeAutoreferencia,
             .v7_orientacaoSocial, .v8_flexibilidadeCognitiva,
             .v9_sensoAgencia:
            return .cognitive
        case .v10_fragmentacaoDiscurso, .v11_densidadeIdeias,
             .v12_marcadoresCerteza, .v13_padroesConectividade,
             .v14_comunicacaoPragmatica, .v15_prosodia:
            return .linguistic
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .v1_valenciaEmocional: "Valência Emocional"
        case .v2_arousalAtivacao: "Arousal/Ativação"
        case .v3_coerenciaNarrativa: "Coerência Narrativa"
        case .v4_complexidadeSintatica: "Complexidade Sintática"
        case .v5_orientacaoTemporal: "Orientação Temporal"
        case .v6_densidadeAutoreferencia: "Densidade de Autoreferência"
        case .v7_orientacaoSocial: "Orientação Social"
        case .v8_flexibilidadeCognitiva: "Flexibilidade Cognitiva"
        case .v9_sensoAgencia: "Senso de Agência"
        case .v10_fragmentacaoDiscurso: "Fragmentação do Discurso"
        case .v11_densidadeIdeias: "Densidade de Ideias"
        case .v12_marcadoresCerteza: "Marcadores Certeza/Incerteza"
        case .v13_padroesConectividade: "Padrões de Conectividade"
        case .v14_comunicacaoPragmatica: "Comunicação Pragmática"
        case .v15_prosodia: "Prosódia e Afetação"
        }
    }

    /// Short subscript label for charts (e.g., "v₁").
    public var subscriptLabel: String {
        let index = VDLPDimensionType.allCases.firstIndex(of: self)! + 1
        let subscripts = "₀₁₂₃₄₅₆₇₈₉"
        if index < 10 {
            return "v\(subscripts[subscripts.index(subscripts.startIndex, offsetBy: index)])"
        }
        let tens = subscripts[subscripts.index(subscripts.startIndex, offsetBy: index / 10)]
        let ones = subscripts[subscripts.index(subscripts.startIndex, offsetBy: index % 10)]
        return "v\(tens)\(ones)"
    }
}

/// The 3 meta-dimensional groups.
public enum VDLPMetaDimension: String, CaseIterable, Sendable {
    case affective = "Meta-Dimensão Afetiva"
    case cognitive = "Meta-Dimensão Cognitiva"
    case linguistic = "Meta-Dimensão Linguística"

    public var dimensions: [VDLPDimensionType] {
        VDLPDimensionType.allCases.filter { $0.metaDimension == self }
    }
}
