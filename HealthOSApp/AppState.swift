import SwiftUI
import HealthOSCore

/// Global application state shared across all views.
@MainActor
@Observable
public final class AppState {
    // MARK: - Navigation
    public var selectedSection: SidebarSection = .dashboard
    public var selectedPatientId: String?

    // MARK: - Workspace
    public var workspaceManager: WorkspaceManager
    public var isLoading = true
    public var errorMessage: String?

    // MARK: - Runtime
    public var selectedRuntime: LLMRuntimeType = .claudeAPI

    // MARK: - Init

    public init() {
        // Detect workspace base directory
        let base = Self.detectBaseDirectory()
        self.workspaceManager = WorkspaceManager(baseDir: base)
    }

    // MARK: - Initialization

    public func initialize() {
        Task { @MainActor in
            isLoading = true
            do {
                try workspaceManager.loadActiveProfessional()
                try workspaceManager.loadAllPatients()
            } catch {
                errorMessage = "Erro ao carregar workspace: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    // MARK: - Workspace Detection

    private static func detectBaseDirectory() -> URL {
        let fileManager = FileManager.default

        // 1. Environment variable
        if let envBase = ProcessInfo.processInfo.environment["HEALTHOS_BASE"] {
            return URL(fileURLWithPath: envBase).standardizedFileURL
        }

        // 2. Walk up from current directory when launched from Xcode/SwiftPM.
        var current = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL
        for _ in 0..<8 {
            if isHealthOSSwiftWorkspace(current, fileManager: fileManager)
                || isHealthOSDataWorkspace(current, fileManager: fileManager) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current.deleteLastPathComponent()
        }

        // 3. Check common locations
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/mentalhealthos"),
            home.appendingPathComponent("HealthOS"),
            home.appendingPathComponent("Desktop/healthos"),
        ]
        for candidate in candidates {
            if isHealthOSSwiftWorkspace(candidate, fileManager: fileManager)
                || isHealthOSDataWorkspace(candidate, fileManager: fileManager) {
                return candidate
            }
        }

        // 4. Default
        return home.appendingPathComponent("Documents/mentalhealthos")
    }

    private static func isHealthOSSwiftWorkspace(_ url: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("Packages/HealthOSCore/Package.swift").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("Packages/HealthOSPipeline/Package.swift").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("Packages/HealthOSUI/Package.swift").path)
            && isDirectory(url.appendingPathComponent("HealthOSApp"), fileManager: fileManager)
    }

    private static func isHealthOSDataWorkspace(_ url: URL, fileManager: FileManager) -> Bool {
        isDirectory(url.appendingPathComponent("patients"), fileManager: fileManager)
            || isDirectory(url.appendingPathComponent("professionals"), fileManager: fileManager)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

// MARK: - Sidebar Sections

public enum SidebarSection: String, CaseIterable, Hashable {
    case dashboard
    case chat
    case consultation
    case patients
    case pipeline
    case terminal
    case agents
    case settings

    public var displayName: String {
        switch self {
        case .dashboard: "Dashboard"
        case .chat: "Conversa"
        case .consultation: "Nova Consulta"
        case .patients: "Pacientes"
        case .pipeline: "Pipeline"
        case .terminal: "Terminal"
        case .agents: "Agentes"
        case .settings: "Configurações"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .consultation: "waveform.badge.plus"
        case .patients: "person.2.fill"
        case .pipeline: "arrow.triangle.branch"
        case .terminal: "terminal.fill"
        case .agents: "cpu.fill"
        case .settings: "gearshape.fill"
        }
    }
}
