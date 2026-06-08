import SwiftUI
import AppKit
import HealthOSCore
import HealthOSUI

@MainActor
final class HealthOSAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Main entry point for the HealthOS macOS application.
@main
struct HealthOSApp: App {
    @NSApplicationDelegateAdaptor(HealthOSAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(appState.workspaceManager)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear {
                    appState.initialize()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Pipeline") {
                ForEach(PipelineStage.allCases, id: \.self) { stage in
                    Button(stage.displayName) {
                        appState.selectedSection = .pipeline
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(stage.index + 1))),
                        modifiers: [.command, .shift]
                    )
                }
            }
            CommandMenu("Navegação") {
                Button("Dashboard") { appState.selectedSection = .dashboard }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Conversa") { appState.selectedSection = .chat }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Pacientes") { appState.selectedSection = .patients }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Pipeline") { appState.selectedSection = .pipeline }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Terminal") { appState.selectedSection = .terminal }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Agentes") { appState.selectedSection = .agents }
                    .keyboardShortcut("6", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(appState.workspaceManager)
        }
    }
}
