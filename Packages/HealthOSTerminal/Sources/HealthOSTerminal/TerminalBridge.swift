import SwiftUI
import AppKit

private extension TerminalRGB {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

#if canImport(SwiftTerm)
import SwiftTerm

private extension TerminalRGB {
    var swiftTermColor: SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16(red) * 257,
            green: UInt16(green) * 257,
            blue: UInt16(blue) * 257
        )
    }
}

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
        applyTheme(session.theme, to: terminalView)

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
        session.runtimeStatus = session.runtimeStatus.updating(state: .running, detail: "shell ativo")
        return terminalView
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyTheme(session.theme, to: nsView)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    private func applyTheme(_ theme: TerminalTheme, to terminalView: LocalProcessTerminalView) {
        terminalView.wantsLayer = true
        terminalView.nativeForegroundColor = theme.foreground.nsColor
        terminalView.nativeBackgroundColor = theme.background.nsColor
        terminalView.layer?.backgroundColor = theme.background.nsColor.cgColor
        terminalView.caretColor = theme.caret.nsColor
        terminalView.caretTextColor = theme.background.nsColor
        terminalView.selectedTextBackgroundColor = theme.selection.nsColor.withAlphaComponent(0.92)
        terminalView.useBrightColors = true

        if theme.ansi16.count == 16 {
            terminalView.installColors(theme.ansi16.map(\.swiftTermColor))
        }
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
                session.runtimeStatus = session.runtimeStatus.updating(state: .stopped, detail: "exit \(exitCode ?? -1)")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Terminal nativo indisponivel")
                .font(.headline.monospaced())
                .foregroundStyle(Color(nsColor: session.theme.foreground.nsColor))
            Text("SwiftTerm nao encontrado")
                .font(.callout.monospaced())
                .foregroundStyle(Color(nsColor: session.theme.muted.nsColor))
            Text(session.runtimeStatus.label)
                .font(.caption.monospaced())
                .foregroundStyle(Color(nsColor: session.theme.accent.nsColor))
        }
        .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: session.theme.background.nsColor))
    }
}
#endif
