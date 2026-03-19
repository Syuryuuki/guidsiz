import Foundation
import AppKit
import GhosttyKit

final class ClaudeSessionLauncher {
    private let registry: ClaudeSessionRegistry

    init(registry: ClaudeSessionRegistry) {
        self.registry = registry
    }

    func activate(
        session: ClaudeSessionSummary,
        preferredController: TerminalController?,
        target: ClaudeSessionOpenTarget = .automatic
    ) -> ClaudeActivationResult {
        registry.compact()

        if let existingSurface = registry.surface(for: session.sessionId),
           let existingController = registry.controller(for: session.sessionId) {
            existingController.window?.makeKeyAndOrderFront(nil)
            Ghostty.moveFocus(to: existingSurface)
            return .focusedExisting
        }

        guard isClaudeExecutableAvailable() else {
            return .failed(.claudeCliNotFound)
        }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = session.projectPath
        config.initialInput = "claude -r \(session.sessionId)\n"

        let openedController: TerminalController? = {
            switch target {
            case .automatic:
                if let preferredController, let window = preferredController.window {
                    return TerminalController.newTab(
                        preferredController.ghostty,
                        from: window,
                        withBaseConfig: config
                    )
                }

                guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
                    return nil
                }
                return TerminalController.newWindow(appDelegate.ghostty, withBaseConfig: config)

            case .currentWindow:
                guard let preferredController, let window = preferredController.window else {
                    return nil
                }

                return TerminalController.newTab(
                    preferredController.ghostty,
                    from: window,
                    withBaseConfig: config
                )

            case .newWindow:
                guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
                    return nil
                }
                return TerminalController.newWindow(appDelegate.ghostty, withBaseConfig: config)
            }
        }()

        guard let openedController else {
            return .failed(.terminalCreateFailed)
        }

        guard let surface = openedController.surfaceTree.first else {
            return .failed(.surfaceUnavailable)
        }

        let context = ClaudeSessionContext(
            sessionId: session.sessionId,
            projectPath: session.projectPath,
            openedAt: Date()
        )
        surface.claudeSessionContext = context
        registry.register(
            sessionId: session.sessionId,
            projectPath: session.projectPath,
            surface: surface,
            controller: openedController
        )

        openedController.window?.makeKeyAndOrderFront(nil)
        Ghostty.moveFocus(to: surface)
        return .openedNew
    }

    private func isClaudeExecutableAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
