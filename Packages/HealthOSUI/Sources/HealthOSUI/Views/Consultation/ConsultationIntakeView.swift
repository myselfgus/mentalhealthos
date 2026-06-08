import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import HealthOSCore
import HealthOSPipeline

public struct ConsultationIntakeView: View {
    @Environment(WorkspaceManager.self) private var workspace

    @State private var mode: IntakePatientMode = .newPatient
    @State private var patientName = ""
    @State private var selectedPatientId = ""
    @State private var sessionDate = Date()
    @State private var intake: ConsultationIntakeRecord?
    @State private var audioImport: ConsultationAudioImport?
    @State private var isImporterPresented = false
    @State private var isPreparing = false
    @State private var isTranscribing = false
    @State private var transcriptionResult: PipelineStageResult?
    @State private var recorder = ConsultationAudioRecorder()
    @State private var notice: IntakeNotice?

    private let engine = PipelineEngine()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                patientPanel
                recorderPanel
                transcriptionPanel
            }
            .padding(28)
        }
        .navigationTitle("Nova consulta")
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
            Task { await importSelectedAudio(result) }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if selectedPatientId.isEmpty {
                selectedPatientId = workspace.patients.first?.patientId ?? ""
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nova consulta")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Crie a sessão, salve o áudio em source/audio e envie para a transcrição nativa.")
                .font(.healthCallout)
                .foregroundStyle(.secondary)
        }
    }

    private var patientPanel: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Paciente e sessão", subtitle: intakeSummary, systemImage: "person.badge.plus")

                Picker("Tipo", selection: $mode) {
                    ForEach(IntakePatientMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .onChange(of: mode) { resetPreparedSession() }

                if mode == .newPatient {
                    TextField("Nome do paciente", text: $patientName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 440)
                        .onChange(of: patientName) { resetPreparedSession() }
                } else if workspace.patients.isEmpty {
                    EmptyStateView(
                        title: "Nenhum paciente",
                        message: "Crie um paciente novo para iniciar a consulta.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                    .frame(height: 180)
                } else {
                    Picker("Paciente", selection: $selectedPatientId) {
                        ForEach(workspace.patients) { patient in
                            Text("\(patient.displayName) · \(patient.patientId)").tag(patient.patientId)
                        }
                    }
                    .frame(maxWidth: 520)
                    .onChange(of: selectedPatientId) { resetPreparedSession() }
                }

                DatePicker("Data", selection: $sessionDate, displayedComponents: [.date])
                    .frame(maxWidth: 260)
                    .onChange(of: sessionDate) { resetPreparedSession() }

                HStack(spacing: 10) {
                    Button {
                        prepareSession()
                    } label: {
                        Label(intake == nil ? "Criar consulta" : "Consulta criada", systemImage: intake == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing || recorder.isRecording)

                    if let intake {
                        Text("\(intake.patientId) · \(intake.sessionId)")
                            .font(.healthCaption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var recorderPanel: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Áudio", subtitle: audioSummary, systemImage: "waveform")

                HStack(spacing: 10) {
                    Button {
                        Task { await toggleRecording() }
                    } label: {
                        Label(recorder.isRecording ? "Parar" : "Gravar", systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.isRecording ? .red : nil)
                    .disabled(isPreparing || isTranscribing)

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Importar áudio", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(recorder.isRecording || isTranscribing)

                    if recorder.isRecording {
                        ProgressView()
                            .controlSize(.small)
                        Text(recordingDuration)
                            .font(.healthCaption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let audioImport {
                    Label(audioImport.destinationURL.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .font(.healthCallout)
                        .foregroundStyle(Color.healthPositive)
                        .textSelection(.enabled)
                } else if let intake {
                    Text(intake.workspace.audioDir.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var transcriptionPanel: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Transcrição", subtitle: "Pipeline Swift", systemImage: "text.bubble")
                    Spacer()
                    Button {
                        Task { await runTranscription() }
                    } label: {
                        Label(isTranscribing ? "Transcrevendo" : "Transcrever", systemImage: isTranscribing ? "hourglass" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTranscribing || recorder.isRecording || intake == nil)
                }

                if isTranscribing {
                    ProgressView()
                } else if let transcriptionResult {
                    transcriptionStatus(transcriptionResult)
                } else {
                    Text("Aguardando áudio da consulta.")
                        .font(.healthCallout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var intakeSummary: String? {
        guard let intake else { return "Nenhuma sessão preparada" }
        return intake.workspace.sessionPath.path
    }

    private var audioSummary: String? {
        guard let intake else { return "Prepare a consulta antes de gravar ou importar" }
        let count = audioFiles(in: intake.workspace.audioDir).count
        return "\(count) arquivo(s) em source/audio"
    }

    private var recordingDuration: String {
        guard let startedAt = recorder.startedAt else { return "00:00" }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func transcriptionStatus(_ result: PipelineStageResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.message, systemImage: result.status == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.status == .completed ? Color.healthPositive : Color.healthWarning)
            if let error = result.error {
                Text("\(error.code): \(error.details ?? error.message)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(result.artifacts, id: \.path) { artifact in
                Text(artifact.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func prepareSession() {
        isPreparing = true
        defer { isPreparing = false }
        do {
            intake = try createOrReuseIntake()
            try workspace.loadAllPatients()
        } catch {
            notice = IntakeNotice(title: "Consulta nao criada", message: error.localizedDescription)
        }
    }

    private func toggleRecording() async {
        do {
            if recorder.isRecording {
                let recordingURL = try recorder.stopRecording()
                let intake = try createOrReuseIntake()
                audioImport = try workspace.importAudioForSession(
                    from: recordingURL,
                    patientId: intake.patientId,
                    sessionId: intake.sessionId,
                    removeOriginal: true
                )
                self.intake = try workspace.createConsultationIntakeIfNeeded(from: intake)
                try workspace.loadAllPatients()
                transcriptionResult = nil
            } else {
                _ = try createOrReuseIntake()
                try await recorder.startRecording()
            }
        } catch {
            notice = IntakeNotice(title: "Audio nao salvo", message: error.localizedDescription)
        }
    }

    private func importSelectedAudio(_ result: Result<URL, Error>) async {
        do {
            let sourceURL = try result.get()
            let needsStop = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if needsStop { sourceURL.stopAccessingSecurityScopedResource() }
            }
            let intake = try createOrReuseIntake()
            audioImport = try workspace.importAudioForSession(
                from: sourceURL,
                patientId: intake.patientId,
                sessionId: intake.sessionId
            )
            self.intake = try workspace.createConsultationIntakeIfNeeded(from: intake)
            try workspace.loadAllPatients()
            transcriptionResult = nil
        } catch {
            notice = IntakeNotice(title: "Audio nao importado", message: error.localizedDescription)
        }
    }

    private func runTranscription() async {
        do {
            let intake = try createOrReuseIntake()
            isTranscribing = true
            defer { isTranscribing = false }
            let result = await engine.run(
                stage: .transcribe,
                baseDir: workspace.baseDir,
                patientId: intake.patientId,
                sessionId: intake.sessionId
            )
            transcriptionResult = result
            try? workspace.loadAllPatients()
        } catch {
            notice = IntakeNotice(title: "Transcricao nao iniciada", message: error.localizedDescription)
        }
    }

    private func createOrReuseIntake() throws -> ConsultationIntakeRecord {
        if let intake { return intake }
        let existingId = mode == .existingPatient ? selectedPatientId : nil
        let created = try workspace.createConsultationIntake(
            existingPatientId: existingId,
            patientName: patientName,
            sessionDate: sessionDate
        )
        intake = created
        return created
    }

    private func resetPreparedSession() {
        guard !recorder.isRecording else { return }
        intake = nil
        audioImport = nil
        transcriptionResult = nil
    }

    private func audioFiles(in directory: URL) -> [URL] {
        let supported = Set(["m4a", "mp3", "wav", "aac", "mp4", "caf"])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { supported.contains($0.pathExtension.lowercased()) }
    }
}

private enum IntakePatientMode: String, CaseIterable, Identifiable {
    case newPatient
    case existingPatient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newPatient: "Novo paciente"
        case .existingPatient: "Paciente existente"
        }
    }
}

private struct IntakeNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
private final class ConsultationAudioRecorder {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    var isRecording = false
    var startedAt: Date?

    func startRecording() async throws {
        guard !isRecording else { return }
        guard await Self.requestMicrophoneAccess() else {
            throw ConsultationRecorderError.microphoneDenied
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthOSNativeRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("consulta-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw ConsultationRecorderError.couldNotStart
        }

        self.recorder = recorder
        self.recordingURL = url
        self.startedAt = Date()
        self.isRecording = true
    }

    func stopRecording() throws -> URL {
        guard isRecording, let recorder, let recordingURL else {
            throw ConsultationRecorderError.noActiveRecording
        }
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        self.startedAt = nil
        self.isRecording = false
        return recordingURL
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

private enum ConsultationRecorderError: Error, LocalizedError {
    case microphoneDenied
    case couldNotStart
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Permissao de microfone negada para o HealthOS."
        case .couldNotStart:
            "Nao foi possivel iniciar a gravacao nativa."
        case .noActiveRecording:
            "Nenhuma gravacao ativa para salvar."
        }
    }
}

private extension WorkspaceManager {
    func createConsultationIntakeIfNeeded(from record: ConsultationIntakeRecord) throws -> ConsultationIntakeRecord {
        guard let profile = try loadPatientProfile(record.patientId),
              let session = profile.sessions.first(where: { $0.sessionId == record.sessionId }) else {
            return record
        }
        return ConsultationIntakeRecord(
            patientId: record.patientId,
            sessionId: record.sessionId,
            patient: profile,
            session: session,
            workspace: sessionWorkspace(patientId: record.patientId, sessionId: record.sessionId)
        )
    }
}
