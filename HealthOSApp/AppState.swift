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
        // 1. Environment variable
        if let envBase = ProcessInfo.processInfo.environment["HEALTHOS_BASE"] {
            return URL(fileURLWithPath: envBase)
        }
        // 2. Walk up from current directory when launched from Xcode/SwiftPM.
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let pkg = current.appendingPathComponent("package.json")
            let patients = current.appendingPathComponent("patients")
            if FileManager.default.fileExists(atPath: pkg.path),
               FileManager.default.fileExists(atPath: patients.path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        // 3. Check common locations
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/mentalhealthos"),
            home.appendingPathComponent("HealthOS"),
            home.appendingPathComponent("Desktop/healthos"),
        ]
        for candidate in candidates {
            let pkg = candidate.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: pkg.path) {
                return candidate
            }
        }
        // 4. Default
        return home.appendingPathComponent("Documents/mentalhealthos")
    }
}

// MARK: - Sidebar Sections

public enum SidebarSection: String, CaseIterable, Hashable {
    case dashboard
    case chat
    case patients
    case pipeline
    case terminal
    case agents
    case settings

    public var displayName: String {
        switch self {
        case .dashboard: "Dashboard"
        case .chat: "Conversa"
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
        case .patients: "person.2.fill"
        case .pipeline: "arrow.triangle.branch"
        case .terminal: "terminal.fill"
        case .agents: "cpu.fill"
        case .settings: "gearshape.fill"
        }
    }
}
