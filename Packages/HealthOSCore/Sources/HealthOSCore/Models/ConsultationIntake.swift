import Foundation

// MARK: - Consultation Intake

public enum ConsultationIntakeError: Error, LocalizedError, Sendable {
    case missingPatientId
    case patientNotFound(String)
    case invalidPatientName
    case sessionNotFound(patientId: String, sessionId: String)
    case missingAudioFile(URL)

    public var errorDescription: String? {
        switch self {
        case .missingPatientId:
            "Selecione um paciente existente ou crie um novo paciente."
        case .patientNotFound(let patientId):
            "Paciente \(patientId) nao encontrado no workspace atual."
        case .invalidPatientName:
            "Informe um nome ou identificador para o novo paciente."
        case .sessionNotFound(let patientId, let sessionId):
            "Sessao \(sessionId) nao encontrada para o paciente \(patientId)."
        case .missingAudioFile(let url):
            "Arquivo de audio nao encontrado: \(url.path)"
        }
    }
}

public struct ConsultationIntakeRecord: Sendable {
    public let patientId: String
    public let sessionId: String
    public let patient: PatientProfile
    public let session: PatientSessionIndex
    public let workspace: PatientSessionWorkspace

    public init(
        patientId: String,
        sessionId: String,
        patient: PatientProfile,
        session: PatientSessionIndex,
        workspace: PatientSessionWorkspace
    ) {
        self.patientId = patientId
        self.sessionId = sessionId
        self.patient = patient
        self.session = session
        self.workspace = workspace
    }
}

public struct ConsultationAudioImport: Sendable {
    public let patientId: String
    public let sessionId: String
    public let sourceURL: URL
    public let destinationURL: URL
    public let didCopy: Bool
    public let artifact: PatientArtifactIndex

    public init(
        patientId: String,
        sessionId: String,
        sourceURL: URL,
        destinationURL: URL,
        didCopy: Bool,
        artifact: PatientArtifactIndex
    ) {
        self.patientId = patientId
        self.sessionId = sessionId
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.didCopy = didCopy
        self.artifact = artifact
    }
}
