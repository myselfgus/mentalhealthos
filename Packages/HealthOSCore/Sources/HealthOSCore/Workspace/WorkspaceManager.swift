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
        if let index = patients.firstIndex(where: { $0.patientId == profile.patientId }) {
            patients[index] = profile
        } else {
            patients.append(profile)
        }
        patients.sort { $0.patientId < $1.patientId }
    }

    public func sessionWorkspace(patientId: String, sessionId: String) -> PatientSessionWorkspace {
        PatientSessionWorkspace(patientId: patientId, sessionId: sessionId, patientsBaseDir: patientsDir)
    }

    @discardableResult
    public func createPatient(displayName: String, status: PatientStatus = .active) throws -> PatientProfile {
        let now = ISO8601DateFormatter().string(from: Date())
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let patientId = nextPatientId()
        let initials = Self.initials(for: trimmed, fallback: patientId)
        let profile = PatientProfile(
            schemaVersion: "1.0",
            patientId: patientId,
            identity: PatientIdentity(
                fullName: trimmed.isEmpty ? nil : trimmed,
                preferredName: nil,
                initials: initials,
                aliases: nil
            ),
            patientName: trimmed.isEmpty ? patientId : trimmed,
            patientInitials: initials,
            aliases: nil,
            status: status,
            demographics: nil,
            careTeam: nil,
            clinicalSummary: nil,
            sessions: [],
            artifacts: [],
            privacy: PatientPrivacy(),
            createdAt: now,
            lastUpdated: now,
            source: "healthos-swift-consultation",
            extendedMetadata: nil
        )
        try savePatientProfile(profile)
        try loadAllPatients()
        return profile
    }

    @discardableResult
    public func createConsultationSession(
        patientId: String,
        date: Date = Date(),
        sourceFile: String? = nil,
        tags: [String] = ["consulta"]
    ) throws -> PatientSessionIndex {
        guard var profile = try loadPatientProfile(patientId) else {
            throw WorkspaceManagerError.patientNotFound(patientId)
        }

        let sessionId = nextSessionId(date: date)
        let workspace = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        try ensureSessionDirectories(workspace)

        let now = ISO8601DateFormatter().string(from: date)
        let session = PatientSessionIndex(
            sessionId: sessionId,
            sessionNumber: (profile.sessions.map { $0.sessionNumber ?? 0 }.max() ?? 0) + 1,
            date: now,
            sourceFile: sourceFile,
            sourceSlug: sourceFile.map { Self.slug($0) },
            tags: tags,
            path: "patients/\(patientId)/sessions/\(sessionId)",
            processedAt: nil,
            status: SessionPipelineStatus(),
            artifacts: [],
            clinicalDelta: nil
        )

        profile.sessions.append(session)
        profile.lastUpdated = now
        try savePatientProfile(profile)
        try writeJSON(session, to: workspace.sessionPath)
        try loadAllPatients()
        return session
    }

    @discardableResult
    public func attachAudio(
        from sourceURL: URL,
        patientId: String,
        sessionId: String,
        suggestedName: String? = nil
    ) throws -> URL {
        let workspace = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        try ensureSessionDirectories(workspace)
        let destinationName = suggestedName ?? sourceURL.lastPathComponent
        let destination = workspace.audioDir.appendingPathComponent(Self.slug(destinationName, preservingExtension: true))
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        try registerRecordedAudio(destination, patientId: patientId, sessionId: sessionId)
        return destination
    }

    public func registerRecordedAudio(_ audioURL: URL, patientId: String, sessionId: String) throws {
        try markSessionAudioAvailable(patientId: patientId, sessionId: sessionId, sourceFile: audioURL.lastPathComponent)
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

    private func ensureSessionDirectories(_ workspace: PatientSessionWorkspace) throws {
        try ensureDirectory(workspace.dir)
        try ensureDirectory(workspace.sourceDir)
        try ensureDirectory(workspace.audioDir)
        try ensureDirectory(workspace.analysisDir)
        try ensureDirectory(workspace.documentsDir)
        try ensureDirectory(workspace.artifactsDir)
        try ensureDirectory(workspace.logsDir)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func loadJSON<T: Decodable>(at path: URL) throws -> T? {
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try decoder.decode(T.self, from: data)
    }

    private func nextPatientId() -> String {
        let used = Set(patients.map(\.patientId))
        var index = 1
        while true {
            let candidate = String(format: "PAT_%06d", index)
            if !used.contains(candidate) { return candidate }
            index += 1
        }
    }

    private func nextSessionId(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "SESSION_\(formatter.string(from: date))"
    }

    private func markSessionAudioAvailable(patientId: String, sessionId: String, sourceFile: String) throws {
        guard var profile = try loadPatientProfile(patientId) else {
            throw WorkspaceManagerError.patientNotFound(patientId)
        }
        guard let index = profile.sessions.firstIndex(where: { $0.sessionId == sessionId }) else {
            throw WorkspaceManagerError.sessionNotFound(patientId: patientId, sessionId: sessionId)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        profile.sessions[index].sourceFile = sourceFile
        profile.sessions[index].status.audio = true
        profile.sessions[index].processedAt = now
        profile.lastUpdated = now
        try savePatientProfile(profile)

        let workspace = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        try writeJSON(profile.sessions[index], to: workspace.sessionPath)
        try loadAllPatients()
    }

    private static func initials(for value: String, fallback: String) -> String {
        let pieces = value
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .prefix(2)
            .compactMap(\.first)
        let initials = String(pieces).uppercased()
        return initials.isEmpty ? String(fallback.prefix(3)) : initials
    }

    private static func slug(_ value: String, preservingExtension: Bool = false) -> String {
        let url = URL(fileURLWithPath: value)
        let base = preservingExtension ? url.deletingPathExtension().lastPathComponent : value
        let ext = preservingExtension ? url.pathExtension : ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slugBase = base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var slug = String(slugBase)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
        if slug.isEmpty { slug = "audio-\(UUID().uuidString)" }
        return ext.isEmpty ? slug : "\(slug).\(ext.lowercased())"
    }
}

public enum WorkspaceManagerError: Error, LocalizedError, Sendable {
    case patientNotFound(String)
    case sessionNotFound(patientId: String, sessionId: String)

    public var errorDescription: String? {
        switch self {
        case .patientNotFound(let patientId):
            "Paciente \(patientId) nao encontrado no workspace."
        case .sessionNotFound(let patientId, let sessionId):
            "Sessao \(sessionId) nao encontrada para \(patientId)."
        }
    }
}
