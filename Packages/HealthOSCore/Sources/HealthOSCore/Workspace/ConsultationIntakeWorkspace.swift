import Foundation

// MARK: - Consultation Intake Workspace

public extension WorkspaceManager {
    @discardableResult
    func createConsultationIntake(
        existingPatientId: String? = nil,
        patientName: String? = nil,
        sessionDate: Date = Date(),
        now: Date = Date()
    ) throws -> ConsultationIntakeRecord {
        try? loadAllPatients()

        let timestamp = Self.intakeTimestampString(from: now)
        let patientId: String
        var profile: PatientProfile

        if let existingPatientId, !existingPatientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            patientId = existingPatientId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let loaded = try loadPatientProfile(patientId) else {
                throw ConsultationIntakeError.patientNotFound(patientId)
            }
            profile = loaded
        } else {
            let name = patientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else {
                throw ConsultationIntakeError.invalidPatientName
            }
            patientId = try nextPatientId()
            profile = PatientProfile(
                schemaVersion: "healthos.patient.v1",
                patientId: patientId,
                identity: PatientIdentity(
                    fullName: name,
                    preferredName: nil,
                    initials: Self.initials(for: name, fallback: patientId),
                    aliases: nil
                ),
                patientName: name,
                patientInitials: Self.initials(for: name, fallback: patientId),
                aliases: nil,
                status: .active,
                demographics: nil,
                careTeam: nil,
                clinicalSummary: nil,
                sessions: [],
                artifacts: [],
                privacy: PatientPrivacy(),
                createdAt: timestamp,
                lastUpdated: timestamp,
                source: "native_intake",
                extendedMetadata: nil
            )
        }

        let sessionId = try uniqueSessionId(for: patientId, date: sessionDate)
        let workspace = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        try ensureSessionDirectories(workspace)

        let session = PatientSessionIndex(
            sessionId: sessionId,
            sessionNumber: nextSessionNumber(in: profile),
            date: Self.intakeDateString(from: sessionDate),
            sourceFile: nil,
            sourceSlug: Self.slug(from: patientName ?? profile.displayName),
            tags: ["native_intake"],
            path: relativePath(for: workspace.dir),
            processedAt: nil,
            status: SessionPipelineStatus(),
            artifacts: [],
            clinicalDelta: nil
        )

        profile.sessions.append(session)
        profile.sessions.sort { ($0.date ?? "") > ($1.date ?? "") }
        profile.lastUpdated = timestamp
        try writeSessionIndex(session, to: workspace.sessionPath)
        try savePatientProfile(profile)

        return ConsultationIntakeRecord(
            patientId: patientId,
            sessionId: sessionId,
            patient: profile,
            session: session,
            workspace: workspace
        )
    }

    @discardableResult
    func importAudioForSession(
        from sourceURL: URL,
        patientId: String,
        sessionId: String,
        recordedAt: Date = Date(),
        removeOriginal: Bool = false
    ) throws -> ConsultationAudioImport {
        let standardizedSource = sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedSource.path) else {
            throw ConsultationIntakeError.missingAudioFile(sourceURL)
        }

        guard var profile = try loadPatientProfile(patientId) else {
            throw ConsultationIntakeError.patientNotFound(patientId)
        }
        guard let sessionIndex = profile.sessions.firstIndex(where: { $0.sessionId == sessionId }) else {
            throw ConsultationIntakeError.sessionNotFound(patientId: patientId, sessionId: sessionId)
        }

        let workspace = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        try ensureSessionDirectories(workspace)
        let destination = try destinationURL(forAudio: standardizedSource, in: workspace.audioDir)
        let didCopy = standardizedSource.path != destination.standardizedFileURL.path

        if didCopy {
            try FileManager.default.copyItem(at: standardizedSource, to: destination)
            if removeOriginal {
                try? FileManager.default.removeItem(at: standardizedSource)
            }
        }

        let timestamp = Self.intakeTimestampString(from: recordedAt)
        let existingAudioCount = profile.sessions[sessionIndex].artifacts?
            .filter { $0.kind == .audio }
            .count ?? 0
        let artifact = PatientArtifactIndex(
            artifactId: "ART_AUDIO_\(sessionId)_\(String(format: "%03d", existingAudioCount + 1))",
            kind: .audio,
            sessionId: sessionId,
            path: relativePath(for: destination),
            format: destination.pathExtension.isEmpty ? "audio" : destination.pathExtension.lowercased(),
            source: didCopy ? "imported_audio" : "native_recording",
            createdAt: timestamp
        )

        profile.sessions[sessionIndex].sourceFile = destination.lastPathComponent
        profile.sessions[sessionIndex].sourceSlug = Self.slug(from: destination.deletingPathExtension().lastPathComponent)
        profile.sessions[sessionIndex].status.audio = true
        profile.sessions[sessionIndex].artifacts = upserting(artifact, into: profile.sessions[sessionIndex].artifacts)
        profile.artifacts = upserting(artifact, into: profile.artifacts)
        profile.lastUpdated = timestamp

        try writeSessionIndex(profile.sessions[sessionIndex], to: workspace.sessionPath)
        try savePatientProfile(profile)

        return ConsultationAudioImport(
            patientId: patientId,
            sessionId: sessionId,
            sourceURL: standardizedSource,
            destinationURL: destination,
            didCopy: didCopy,
            artifact: artifact
        )
    }

    func markSessionTranscription(
        patientId: String,
        sessionId: String,
        transcriptionURL: URL,
        source: String = "swift_pipeline",
        createdAt: Date = Date()
    ) throws {
        guard var profile = try loadPatientProfile(patientId) else {
            throw ConsultationIntakeError.patientNotFound(patientId)
        }
        guard let sessionIndex = profile.sessions.firstIndex(where: { $0.sessionId == sessionId }) else {
            throw ConsultationIntakeError.sessionNotFound(patientId: patientId, sessionId: sessionId)
        }

        let timestamp = Self.intakeTimestampString(from: createdAt)
        let workspace = sessionWorkspace(patientId: patientId, sessionId: sessionId)
        let artifact = PatientArtifactIndex(
            artifactId: "ART_TRANSCRIPTION_\(sessionId)",
            kind: .transcription,
            sessionId: sessionId,
            path: relativePath(for: transcriptionURL),
            format: "json",
            source: source,
            createdAt: timestamp
        )

        profile.sessions[sessionIndex].processedAt = timestamp
        profile.sessions[sessionIndex].status.transcription = true
        profile.sessions[sessionIndex].artifacts = upserting(artifact, into: profile.sessions[sessionIndex].artifacts)
        profile.artifacts = upserting(artifact, into: profile.artifacts)
        profile.lastUpdated = timestamp

        try writeSessionIndex(profile.sessions[sessionIndex], to: workspace.sessionPath)
        try savePatientProfile(profile)
    }
}

private extension WorkspaceManager {
    static func intakeTimestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func intakeDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func intakeSessionIdString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy_MM_dd_HHmmss"
        return formatter.string(from: date)
    }

    func ensureSessionDirectories(_ workspace: PatientSessionWorkspace) throws {
        for directory in [
            workspace.sourceDir,
            workspace.audioDir,
            workspace.analysisDir,
            workspace.documentsDir,
            workspace.artifactsDir,
            workspace.logsDir,
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func nextPatientId() throws -> String {
        var ids = Set(patients.map(\.patientId))
        if FileManager.default.fileExists(atPath: patientsDir.path) {
            let directoryIds = try FileManager.default.contentsOfDirectory(atPath: patientsDir.path)
            ids.formUnion(directoryIds)
        }

        let maxNumber = ids.compactMap(Self.patientNumber).max() ?? 0
        return "PAT_\(String(format: "%06d", maxNumber + 1))"
    }

    static func patientNumber(from id: String) -> Int? {
        guard id.hasPrefix("PAT_") else { return nil }
        let suffix = id.dropFirst(4)
        guard suffix.count == 6 else { return nil }
        return Int(suffix)
    }

    func uniqueSessionId(for patientId: String, date: Date) throws -> String {
        let base = "SESSION_\(Self.intakeSessionIdString(from: date))"
        let patientSessionsDir = patientsDir
            .appendingPathComponent(patientId)
            .appendingPathComponent("sessions")
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: patientSessionsDir.appendingPathComponent(candidate).path) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    func nextSessionNumber(in profile: PatientProfile) -> Int {
        (profile.sessions.compactMap(\.sessionNumber).max() ?? 0) + 1
    }

    func destinationURL(forAudio sourceURL: URL, in audioDir: URL) throws -> URL {
        let sourceParent = sourceURL.deletingLastPathComponent().standardizedFileURL.path
        if sourceParent == audioDir.standardizedFileURL.path {
            return sourceURL.standardizedFileURL
        }

        let baseName = Self.slug(from: sourceURL.deletingPathExtension().lastPathComponent)
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        var candidate = audioDir.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = audioDir.appendingPathComponent("\(baseName)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    func writeSessionIndex(_ session: PatientSessionIndex, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url)
    }

    func relativePath(for url: URL) -> String {
        let basePath = baseDir.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return path }
        let start = path.index(path.startIndex, offsetBy: basePath.count)
        return String(path[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func upserting(
        _ artifact: PatientArtifactIndex,
        into artifacts: [PatientArtifactIndex]?
    ) -> [PatientArtifactIndex] {
        var values = artifacts ?? []
        if let index = values.firstIndex(where: { $0.path == artifact.path && $0.kind == artifact.kind }) {
            values[index] = artifact
        } else {
            values.append(artifact)
        }
        return values
    }

    static func initials(for name: String, fallback: String) -> String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .compactMap(\.first)
        let initials = String(parts.prefix(2)).uppercased()
        return initials.isEmpty ? String(fallback.prefix(3)) : initials
    }

    static func slug(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "consulta" : collapsed
    }
}
