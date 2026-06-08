import Foundation

// MARK: - GEM Graph (Grafo Espaço-Campo Mental)

/// Complete GEM output — maps to `gem.json` in the analysis directory.
/// The 4-layer cognitive graph modeling the patient's mental space.
public struct GEMAnalysis: Codable, Sendable {
    public var gem: GEMGraph?
    public var statistics: GEMStatistics?
    public var crossReferences: [String: AnyCodable]?
    public var keyInsights: [String]?
    public var validationScore: Double?

    enum CodingKeys: String, CodingKey {
        case gem, statistics
        case crossReferences = "cross_references"
        case keyInsights = "key_insights"
        case validationScore = "validation_score"
    }
}

// MARK: - GEM Graph Structure (4 Layers)

public struct GEMGraph: Codable, Sendable {
    public var aje: GEMAjeLayer?
    public var ire: GEMIreLayer?
    public var e: GEMEulerianLayer?
    public var epe: GEMEpeLayer?
}

// MARK: - .aje (Actions and Journey Events)

public struct GEMAjeLayer: Codable, Sendable {
    public var events: [GEMAjeEvent]?
}

public struct GEMAjeEvent: Codable, Identifiable, Sendable {
    public var id: String { eventId }

    public let eventId: String
    public var description: String?
    public var emotionalIntensity: Double?
    public var cognitiveComplexity: Double?
    public var agency: Double?
    public var temporalOrientation: String?
    public var socialContext: String?
    public var relationalVectors: [GEMRelation]?
    public var dimensionalCoordinates: [String: Double]?
    public var evidence: [String]?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case description
        case emotionalIntensity = "emotional_intensity"
        case cognitiveComplexity = "cognitive_complexity"
        case agency
        case temporalOrientation = "temporal_orientation"
        case socialContext = "social_context"
        case relationalVectors = "relational_vectors"
        case dimensionalCoordinates = "dimensional_coordinates"
        case evidence
    }
}

public struct GEMRelation: Codable, Sendable {
    public var targetEventId: String?
    public var relationType: String?
    public var strength: Double?

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
        case relationType = "relation_type"
        case strength
    }
}

// MARK: - .ire (Intelligible Relational Entities)

public struct GEMIreLayer: Codable, Sendable {
    public var clusters: [GEMIreCluster]?
}

public struct GEMIreCluster: Codable, Identifiable, Sendable {
    public var id: String { clusterId }

    public let clusterId: String
    public var label: String?
    public var description: String?
    public var eventIds: [String]?
    public var emergentProperties: [String: AnyCodable]?
    public var hitopSpectrum: String?
    public var density: Double?

    enum CodingKeys: String, CodingKey {
        case clusterId = "cluster_id"
        case label, description
        case eventIds = "event_ids"
        case emergentProperties = "emergent_properties"
        case hitopSpectrum = "hitop_spectrum"
        case density
    }
}

// MARK: - .e (Eulerian Flows — Diagnostic)

public struct GEMEulerianLayer: Codable, Sendable {
    public var flows: [GEMEulerianFlow]?
}

public struct GEMEulerianFlow: Codable, Identifiable, Sendable {
    public var id: String { flowId }

    public let flowId: String
    public var label: String?
    public var description: String?
    public var sourceClusterId: String?
    public var targetClusterId: String?
    public var causalStrength: Double?
    public var mappedDimensions: [String]?
    public var trajectory: String?

    enum CodingKeys: String, CodingKey {
        case flowId = "flow_id"
        case label, description
        case sourceClusterId = "source_cluster_id"
        case targetClusterId = "target_cluster_id"
        case causalStrength = "causal_strength"
        case mappedDimensions = "mapped_dimensions"
        case trajectory
    }
}

// MARK: - .epe (Emergenable Pathways — Prognostic)

public struct GEMEpeLayer: Codable, Sendable {
    public var pathways: [GEMEmergPath]?
}

public struct GEMEmergPath: Codable, Identifiable, Sendable {
    public var id: String { pathwayId }

    public let pathwayId: String
    public var label: String?
    public var description: String?
    public var frictionClusters: [String]?
    public var leverageClusters: [String]?
    public var conditionsForEmergence: [String]?
    public var potentialScore: Double?
    public var timeHorizon: String?

    enum CodingKeys: String, CodingKey {
        case pathwayId = "pathway_id"
        case label, description
        case frictionClusters = "friction_clusters"
        case leverageClusters = "leverage_clusters"
        case conditionsForEmergence = "conditions_for_emergence"
        case potentialScore = "potential_score"
        case timeHorizon = "time_horizon"
    }
}

// MARK: - GEM Statistics

public struct GEMStatistics: Codable, Sendable {
    public var totalEvents: Int?
    public var totalClusters: Int?
    public var totalFlows: Int?
    public var totalPathways: Int?
    public var averageCausalStrength: Double?
    public var globalCoherence: Double?

    enum CodingKeys: String, CodingKey {
        case totalEvents = "total_events"
        case totalClusters = "total_clusters"
        case totalFlows = "total_flows"
        case totalPathways = "total_pathways"
        case averageCausalStrength = "average_causal_strength"
        case globalCoherence = "global_coherence"
    }
}

// MARK: - GEM Layer Type

/// The 4 GEM layers as an enum for tab/section navigation.
public enum GEMLayerType: String, CaseIterable, Sendable {
    case aje, ire, e, epe

    public var displayName: String {
        switch self {
        case .aje: "Eventos (.aje)"
        case .ire: "Clusters (.ire)"
        case .e: "Fluxos Eulerianos (.e)"
        case .epe: "Caminhos Emergenáveis (.epe)"
        }
    }

    public var systemImage: String {
        switch self {
        case .aje: "mappin.circle.fill"
        case .ire: "circle.grid.cross.fill"
        case .e: "arrow.triangle.branch"
        case .epe: "sparkles"
        }
    }
}
