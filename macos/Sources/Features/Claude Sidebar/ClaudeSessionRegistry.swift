import Foundation
import GhosttyKit

final class ClaudeSessionRegistry: ObservableObject {
    private final class Entry {
        let sessionId: String
        let projectPath: String
        weak var surface: Ghostty.SurfaceView?
        weak var controller: BaseTerminalController?

        init(
            sessionId: String,
            projectPath: String,
            surface: Ghostty.SurfaceView,
            controller: BaseTerminalController
        ) {
            self.sessionId = sessionId
            self.projectPath = projectPath
            self.surface = surface
            self.controller = controller
        }
    }

    private var entries: [String: Entry] = [:]

    func register(
        sessionId: String,
        projectPath: String,
        surface: Ghostty.SurfaceView,
        controller: BaseTerminalController
    ) {
        entries[sessionId] = Entry(
            sessionId: sessionId,
            projectPath: projectPath,
            surface: surface,
            controller: controller
        )
        objectWillChange.send()
    }

    func unregister(surface: Ghostty.SurfaceView) {
        let before = entries.count
        entries = entries.filter { $0.value.surface !== surface }
        if entries.count != before {
            objectWillChange.send()
        }
    }

    func unregister(surfaces: [Ghostty.SurfaceView]) {
        guard !surfaces.isEmpty else { return }

        let targetIds = Set(surfaces.map { ObjectIdentifier($0) })
        let before = entries.count
        entries = entries.filter { _, entry in
            guard let surface = entry.surface else { return false }
            return !targetIds.contains(ObjectIdentifier(surface))
        }
        if entries.count != before {
            objectWillChange.send()
        }
    }

    func surface(for sessionId: String) -> Ghostty.SurfaceView? {
        compact()
        return entries[sessionId]?.surface
    }

    func controller(for sessionId: String) -> BaseTerminalController? {
        compact()
        return entries[sessionId]?.controller
    }

    func isOpen(_ sessionId: String) -> Bool {
        compact()
        return entries[sessionId]?.surface != nil
    }

    func openSessionIds() -> Set<String> {
        compact()
        return Set(entries.keys)
    }

    func compact() {
        let before = entries.count
        entries = entries.filter { _, entry in
            entry.surface != nil && entry.controller != nil
        }
        if entries.count != before {
            objectWillChange.send()
        }
    }
}
