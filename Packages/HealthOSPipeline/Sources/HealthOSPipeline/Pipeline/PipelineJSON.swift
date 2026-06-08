import Foundation
import HealthOSCore

enum PipelineJSON {
    static let decoder = JSONDecoder()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func extractObjectData(from response: String) throws -> Data {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstBrace = text.firstIndex(of: "{") else {
            throw PipelineJSONError.noJSONObject
        }

        var depth = 0
        var inString = false
        var isEscaped = false
        var endIndex: String.Index?
        var index = firstBrace

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = text.index(after: index)
                        break
                    }
                }
            }
            index = text.index(after: index)
        }

        guard let endIndex else {
            throw PipelineJSONError.unbalancedJSONObject
        }

        let json = String(text[firstBrace..<endIndex])
        guard let data = json.data(using: .utf8) else {
            throw PipelineJSONError.encodingFailed
        }
        _ = try JSONSerialization.jsonObject(with: data)
        return data
    }

    static func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipelineJSONError.notADictionary
        }
        return object
    }

    static func prettyData(from data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    static func writePrettyObjectData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try prettyData(from: data).write(to: url, options: .atomic)
    }

    static func writeEncodable<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

enum PipelineJSONError: Error, LocalizedError {
    case noJSONObject
    case unbalancedJSONObject
    case encodingFailed
    case notADictionary

    var errorDescription: String? {
        switch self {
        case .noJSONObject:
            "No JSON object was found in the LLM response."
        case .unbalancedJSONObject:
            "The JSON object in the LLM response is not balanced."
        case .encodingFailed:
            "The JSON object could not be encoded as UTF-8."
        case .notADictionary:
            "The JSON payload is not an object."
        }
    }
}

enum ClinicalArtifactValidator {
    static func validateASL(data: Data) throws {
        _ = try PipelineJSON.decoder.decode(ASLAnalysis.self, from: data)
        let object = try PipelineJSON.object(from: data)
        let domains = ASLDomainType.allCases.map(\.rawValue)
        let missingDomains = domains.filter { object[$0] == nil }

        guard object["contexto_identificado"] != nil else {
            throw ClinicalValidationError.missingKey("contexto_identificado")
        }
        guard missingDomains.isEmpty else {
            throw ClinicalValidationError.missingKeys(missingDomains)
        }
        guard object["sintese_interpretativa"] != nil else {
            throw ClinicalValidationError.missingKey("sintese_interpretativa")
        }
    }

    static func validateVDLP(data: Data) throws {
        _ = try PipelineJSON.decoder.decode(VDLPAnalysis.self, from: data)
        let object = try PipelineJSON.object(from: data)
        guard let dimensions = object["dimensions"] as? [String: Any] else {
            throw ClinicalValidationError.missingKey("dimensions")
        }

        let expected = Set(VDLPDimensionType.allCases.map(\.rawValue))
        let actual = Set(dimensions.keys)
        let missing = expected.subtracting(actual).sorted()
        guard missing.isEmpty else {
            throw ClinicalValidationError.missingKeys(missing)
        }
    }

    static func validateGEM(data: Data) throws {
        _ = try PipelineJSON.decoder.decode(GEMAnalysis.self, from: data)
        let object = try PipelineJSON.object(from: data)
        guard let gem = object["gem"] as? [String: Any] else {
            throw ClinicalValidationError.missingKey("gem")
        }

        try requireArray(in: gem, layer: "aje", field: "events")
        try requireArray(in: gem, layer: "ire", field: "clusters")
        try requireArray(in: gem, layer: "e", field: "flows")
        try requireArray(in: gem, layer: "epe", field: "pathways")
    }

    private static func requireArray(in gem: [String: Any], layer: String, field: String) throws {
        guard let object = gem[layer] as? [String: Any] else {
            throw ClinicalValidationError.missingKey("gem.\(layer)")
        }
        guard object[field] is [Any] else {
            throw ClinicalValidationError.missingKey("gem.\(layer).\(field)")
        }
    }
}

enum ClinicalValidationError: Error, LocalizedError {
    case missingKey(String)
    case missingKeys([String])
    case missingAnyKey([String])

    var errorDescription: String? {
        switch self {
        case .missingKey(let key):
            "Missing required clinical JSON key: \(key)"
        case .missingKeys(let keys):
            "Missing required clinical JSON keys: \(keys.joined(separator: ", "))"
        case .missingAnyKey(let keys):
            "Expected at least one of these clinical JSON keys: \(keys.joined(separator: ", "))"
        }
    }
}
