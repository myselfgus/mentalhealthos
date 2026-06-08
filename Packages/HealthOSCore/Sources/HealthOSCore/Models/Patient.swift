import Foundation

// MARK: - Patient Identity

/// Core patient profile — maps to `patient.json` in the filesystem workspace.
public struct PatientProfile: Codable, Identifiable, Sendable {
    public var id: String { patientId }

    public let schemaVersion: String?
    public let patientId: String
    public var identity: PatientIdentity?
    public var patientName: String?
    public var patientInitials: String?
    public var aliases: [String]?
    public var status: PatientStatus
    public var demographics: PatientDemographics?
    public var careTeam: [CareTeamMember]?
    public var clinicalSummary: ClinicalSummary?
    public var sessions: [PatientSessionIndex]
    public var artifacts: [PatientArtifactIndex]?
    public var privacy: PatientPrivacy
    public let createdAt: String
    public var lastUpdated: String
    public var source: String?
    public var extendedMetadata: [String: AnyCodable]?

    public var displayName: String {
        identity?.fullName ?? patientName ?? patientId
    }

    public var initials: String {
        identity?.initials ?? patientInitials ?? String(patientId.prefix(3))
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case patientId = "patient_id"
        case identity
        case patientName = "patient_name"
        case patientInitials = "patient_initials"
        case aliases, status, demographics
        case careTeam = "care_team"
        case clinicalSummary = "clinical_summary"
        case sessions, artifacts, privacy
        case createdAt = "created_at"
        case lastUpdated = "last_updated"
        case source
        case extendedMetadata = "extended_metadata"
    }
}

public struct PatientIdentity: Codable, Sendable {
    public var fullName: String?
    public var preferredName: String?
    public var initials: String?
    public var aliases: [String]?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case preferredName = "preferred_name"
        case initials, aliases
    }
}

public enum PatientStatus: String, Codable, Sendable {
    case active, inactive, archived, discharged
}

public struct PatientDemographics: Codable, Sendable {
    public var age: Int?
    public var gender: String?
    public var language: String?
}

public struct CareTeamMember: Codable, Sendable {
    public var role: String
    public var name: String
    public var registro: String?
}

// MARK: - Clinical Summary

public struct ClinicalSummary: Codable, Sendable {
    public var allICDCodes: [ICDCode]?
    public var allMedications: [Medication]?
    public var commonTopics: [String]?
    public var encounterTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case allICDCodes = "all_icd_codes"
        case allMedications = "all_medications"
        case commonTopics = "common_topics"
        case encounterTypes = "encounter_types"
    }
}

public struct ICDCode: Codable, Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public var label: String?
    public var certaintyHistory: [CertaintyLevel]?

    enum CodingKeys: String, CodingKey {
        case code, label
        case certaintyHistory = "certainty_history"
    }
}

public enum CertaintyLevel: String, Codable, Sendable {
    case confirmed, suspected
    case ruleOut = "rule_out"
}

public struct Medication: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public var dosage: String?
    public var contexts: [MedicationContext]?
}

public enum MedicationContext: String, Codable, Sendable {
    case current, past, discussed
}

// MARK: - Patient Privacy

public struct PatientPrivacy: Codable, Sendable {
    public var containsPHI: Bool
    public var directoryPolicy: String?
    public var memoryPolicy: String?
    public var redactionLevel: String?

    enum CodingKeys: String, CodingKey {
        case containsPHI = "contains_phi"
        case directoryPolicy = "directory_policy"
        case memoryPolicy = "memory_policy"
        case redactionLevel = "redaction_level"
    }

    public init(
        containsPHI: Bool = true,
        directoryPolicy: String? = "pseudonymous_id",
        memoryPolicy: String? = "explicit_only",
        redactionLevel: String? = nil
    ) {
        self.containsPHI = containsPHI
        self.directoryPolicy = directoryPolicy
        self.memoryPolicy = memoryPolicy
        self.redactionLevel = redactionLevel
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for dynamic JSON fields.
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map(\.value)
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int: try container.encode(intVal)
        case let doubleVal as Double: try container.encode(doubleVal)
        case let boolVal as Bool: try container.encode(boolVal)
        case let stringVal as String: try container.encode(stringVal)
        default: try container.encodeNil()
        }
    }
}
