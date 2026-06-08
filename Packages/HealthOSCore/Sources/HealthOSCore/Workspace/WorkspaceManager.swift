import Foundation

// MARK: - Workspace Manager

/// Central manager for HealthOS filesystem workspaces.
/// Handles patient and professional directory resolution, profile I/O, and session management.
@Observable
public final class WorkspaceManager: @unchecked Sendable {

    // MARK: - Properties

    public var baseDir: URL
    public var activeProfessional: ProfessionalConfig?
    public var patients: [PatientProfile] = []

    public var patientsDir: URL { baseDir.appendingPathComponent("patients") }
    public var professionalsDir: URL { baseDir.appendingPathComponent("professionals") }
    public var audioDir: URL { baseDir.appendingPathComponent("audio") }
    public var runsDir: URL { baseDir.appendingPathComponent("runs") }

    private let fileManager = FileManager.default
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Init

    public init(baseDir: URL) {
        self.baseDir = baseDir
    }

    // MARK: - Professional Management

    public func loadActiveProfessional() throws {
        let activeFile = professionalsDir.appendingPathComponent("active-professional.json")
        guard fileManager.fileExists(atPath: activeFile.path) else { return }
        let data = try Data(contentsOf: activeFile)
        let active = try decoder.decode(ActiveProfessional.self, from: data)
        let workspace = ProfessionalWorkspace(id: active.activeProfessionalId, baseDir: baseDir)
        guard fileManager.fileExists(atPath: workspace.configPath.path) else { return }
        let configData = try Data(contentsOf: workspace.configPath)
        activeProfessional = try decoder.decode(ProfessionalConfig.self, from: configData)
    }

    public func saveProfessionalConfig(_ config: ProfessionalConfig) throws {
        var config = config
        config.lastUpdated = ISO8601DateFormatter().string(from: Date())
        let workspace = ProfessionalWorkspace(id: config.id, baseDir: baseDir)
        try ensureDirectory(workspace.dir)
        try ensureDirectory(workspace.logsDir)
        try ensureDirectory(workspace.telemetryDir)
        try ensureDirectory(workspace.sessionsDir)
        try ensureDirectory(workspace.artifactsDir)
        let data = try encoder.encode(config)
        try data.write(to: workspace.configPath)
        // Set as active
        let active = ActiveProfessional(activeProfessionalId: config.id)
        let activeData = try encoder.encode(active)
        try activeData.write(to: professionalsDir.appendingPathComponent("active-professional.json"))
        activeProfessional = config
    }

    // MARK: - Patient Management

    public func loadAllPatients() throws {
        patients = []
        guard fileManager.fileExists(atPath: patientsDir.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: patientsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for dir in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let profilePath = dir.appendingPathComponent("patient.json")
            guard fileManager.fileExists(atPath: profilePath.path) else { continue }
            do {
                let data = try Data(contentsOf: profilePath)
                let profile = try decoder.decode(PatientProfile.self, from: data)
                patients.append(profile)
            } catch {
                // Skip malformed patient files
                continue
            }
        }
        patients.sort { $0.patientId < $1.patientId }
    }

    public func loadPatientProfile(_ patientId: String) throws -> PatientProfile? {
        let profilePath = patientsDir
            .appendingPathComponent(patientId)
            .appendingPathComponent("patient.json")
        guard fileManager.fileExists(atPath: profilePath.path) else { return nil }
        let data = try Data(contentsOf: profilePath)
        return try decoder.decode(PatientProfile.self, from: data)
    }

    public func savePatientProfile(_ profile: PatientProfile) throws {
        let dir = patientsDir.appendingPathComponent(profile.patientId)
        try ensureDirectory(dir)
        let data = try encoder.encode(profile)
        try data.write(to: dir.appendingPathComponent("patient.json"))
    }

    public func sessionWorkspace(patientId: String, sessionId: String) -> PatientSessionWorkspace {
        PatientSessionWorkspace(patientId: patientId, sessionId: sessionId, patientsBaseDir: patientsDir)
    }

    // MARK: - Analysis I/O

    public func loadASL(patientId: String, sessionId: String) throws -> ASLAnalysis? {
        let path = sessionWorkspace(patientId: patientId, sessionId: sessionId).aslPath
        return try loadJSON(at: path)
    }

    public func loadVDLP(patientId: String, sessionId: String) throws -> VDLPAnalysis? {
        let path = sessionWorkspace(patientId: patientId, sessionId: sessionId).vdlpPath
        return try loadJSON(at: path)
    }

    public func loadGEM(patientId: String, sessionId: String) throws -> GEMAnalysis? {
        let path = sessionWorkspace(patientId: patientId, sessionId: sessionId).gemPath
        return try loadJSON(at: path)
    }

    public func loadTranscription(patientId: String, sessionId: String) throws -> String? {
        let path = sessionWorkspace(patientId: patientId, sessionId: sessionId).transcriptionPath
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        // Transcription JSON may have a "transcricao" field
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["transcricao"] as? String {
            return text
        }
        return String(data: data, encoding: .utf8)
    }

    public func loadPatientSpeech(patientId: String, sessionId: String) throws -> String? {
        let ws = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        // Try .txt first, then .md
        for path in [ws.patientSpeechTextPath, ws.patientSpeechMarkdownPath] {
            if fileManager.fileExists(atPath: path.path) {
                return try String(contentsOf: path, encoding: .utf8)
            }
        }
        return nil
    }

    // MARK: - Professional Memory

    public func loadProfessionalMemory() throws -> String? {
        guard let prof = activeProfessional else { return nil }
        let workspace = ProfessionalWorkspace(id: prof.id, baseDir: baseDir)
        guard fileManager.fileExists(atPath: workspace.memoryPath.path) else { return nil }
        return try String(contentsOf: workspace.memoryPath, encoding: .utf8)
    }

    public func appendProfessionalMemory(_ note: String) throws {
        guard let prof = activeProfessional else { return }
        let workspace = ProfessionalWorkspace(id: prof.id, baseDir: baseDir)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\n- \(timestamp): \(note)\n"
        if fileManager.fileExists(atPath: workspace.memoryPath.path) {
            let handle = try FileHandle(forWritingTo: workspace.memoryPath)
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try entry.write(to: workspace.memoryPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Statistics

    public struct ProjectStats: Sendable {
        public var patientCount: Int
        public var totalSessions: Int
        public var completedAnalyses: Int
        public var pendingStages: Int
    }

    public func computeStats() -> ProjectStats {
        var totalSessions = 0
        var completed = 0
        var pending = 0
        for patient in patients {
            totalSessions += patient.sessions.count
            for session in patient.sessions {
                if session.status.completedCount == 6 {
                    completed += 1
                } else {
                    pending += (6 - session.status.completedCount)
                }
            }
        }
        return ProjectStats(
            patientCount: patients.count,
            totalSessions: totalSessions,
            completedAnalyses: completed,
            pendingStages: pending
        )
    }

    // MARK: - Helpers

    private func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func loadJSON<T: Decodable>(at path: URL) throws -> T? {
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try decoder.decode(T.self, from: data)
    }
}
