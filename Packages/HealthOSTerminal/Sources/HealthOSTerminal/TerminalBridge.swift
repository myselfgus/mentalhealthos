import SwiftUI
import AppKit

#if canImport(SwiftTerm)
import SwiftTerm

// MARK: - Terminal Bridge (NSViewRepresentable)

/// Wraps SwiftTerm's `LocalProcessTerminalView` for use in SwiftUI.
public struct TerminalBridgeView: NSViewRepresentable {
    public let session: TerminalSession

    public init(session: TerminalSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        context.coordinator.terminalView = terminalView
        terminalView.processDelegate = context.coordinator

        // Configure appearance
        let fontSize: CGFloat = 13
        if let font = NSFont(name: "SF Mono", size: fontSize)
            ?? NSFont(name: "Menlo", size: fontSize) {
            terminalView.font = font
        }

        // Start shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = session.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"

        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: nil
        )

        session.isRunning = true
        return terminalView
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No dynamic updates needed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var session: TerminalSession
        weak var terminalView: LocalProcessTerminalView?

        init(session: TerminalSession) {
            self.session = session
        }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized
        }

        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            let session = self.session
            Task { @MainActor in
                session.title = title
            }
        }

        public func processTerminated(source: TerminalView, exitCode: Int32?) {
            let session = self.session
            Task { @MainActor in
                session.isRunning = false
            }
        }

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            if let directory {
                let session = self.session
                Task { @MainActor in
                    session.workingDirectory = URL(fileURLWithPath: directory)
                }
            }
        }
    }
}
#else
// Stub when SwiftTerm is not available
public struct TerminalBridgeView: View {
    public let session: TerminalSession
    public init(session: TerminalSession) { self.session = session }
    public var body: some View {
        Text("Terminal não disponível — SwiftTerm não encontrado")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
    }
}
#endif
