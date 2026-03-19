import SwiftUI
import AppKit

struct ClaudeSidebarView: View {
    @ObservedObject var store: ClaudeProjectsStore
    @ObservedObject var registry: ClaudeSessionRegistry

    let preferredController: TerminalController?
    let launcher: ClaudeSessionLauncher
    let onToggleSidebar: () -> Void
    let backgroundColor: Color

    @Binding var selectedProjectPath: String?
    @Binding var selectedSessionId: String?

    @State private var errorMessage: String?
    @State private var visibleStartByProject: [String: Int] = [:]
    @FocusState private var isSidebarFocused: Bool

    private let maxVisibleSessionsPerProject = 10

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.projects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
        }
        .background(backgroundColor)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 1)
        }
        .focusable()
        .focused($isSidebarFocused)
        .modifier(SidebarFocusEffectModifier())
        .alert(
            "Claude Session Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(errorMessage ?? "Unknown error")
            }
        )
        .onMoveCommand(perform: handleMoveCommand)
        .backport.onKeyPress(.return) { _ in
            activateSelectedSession()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label {
                    Text("Claude Sessions")
                        .font(.system(size: 16, weight: .semibold))
                } icon: {
                    Image(systemName: "folder.badge.person.crop")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onToggleSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar")

                Button {
                    importProject()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("Import Project")

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            TextField("Search sessions", text: $store.searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(backgroundColor.opacity(0.98))
    }

    private func projectSection(_ project: ImportedClaudeProject) -> some View {
        VStack(spacing: 0) {
            Button {
                toggleProjectSelection(project)
            } label: {
                projectHeaderRow(project)
            }
            .buttonStyle(.plain)

            if store.expandedProjectPaths.contains(project.projectPath) {
                sessionsView(for: project)
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func sessionsView(for project: ImportedClaudeProject) -> some View {
        let sessions = store.filteredSessions(for: project.projectPath)
        let visible = visibleSessions(for: project.projectPath, sessions: sessions)

        if sessions.isEmpty {
            let state = store.stateByProject[project.projectPath] ?? .idle
            Text(stateText(state))
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            VStack(spacing: 4) {
                ForEach(visible) { session in
                    Button {
                        activate(session: session, project: project)
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open in Current Window") {
                            activate(session: session, project: project, target: .currentWindow)
                        }
                        .disabled(preferredController?.window == nil)

                        Button("Open in New Window") {
                            activate(session: session, project: project, target: .newWindow)
                        }

                        Button("Copy Session ID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(session.sessionId, forType: .string)
                        }
                    }
                }

                if sessions.count > maxVisibleSessionsPerProject {
                    pagingFooter(for: project.projectPath, totalCount: sessions.count)
                }
            }
            .padding(.top, 2)
            .padding(.leading, 16)
        }
    }

    private func pagingFooter(for projectPath: String, totalCount: Int) -> some View {
        let start = clampedVisibleStart(for: projectPath, totalCount: totalCount)
        let end = min(totalCount, start + maxVisibleSessionsPerProject)

        return HStack(spacing: 8) {
            Text("\(start + 1)-\(end) / \(totalCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("↑/↓ Browse")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func projectHeaderRow(_ project: ImportedClaudeProject) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: store.expandedProjectPaths.contains(project.projectPath) ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 10, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.system(size: 14, weight: .semibold))

                Text(project.projectPath)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            let count = store.sessionsByProject[project.projectPath]?.count ?? 0
            Text("\(count)")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selectedProjectPath == project.projectPath ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .contextMenu {
            Button("Refresh") {
                Task { await store.refreshProject(project) }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.projectPath)])
            }
            Button("Remove Project", role: .destructive) {
                store.removeProject(project)
                if selectedProjectPath == project.projectPath {
                    selectedProjectPath = nil
                    selectedSessionId = nil
                }
            }
        }
    }

    private func sessionRow(_ session: ClaudeSessionSummary) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(rowDotColor(for: session).opacity(session.sessionId == selectedSessionId ? 0.28 : 0.16))
                    .frame(width: 16, height: 16)

                Circle()
                    .fill(rowDotColor(for: session))
                    .frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.firstPrompt?.isEmpty == false ? session.firstPrompt! : session.sessionId)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 6) {
                    if let branch = session.gitBranch, !branch.isEmpty {
                        Text(branch)
                    }

                    if session.isSidechain {
                        Text("sidechain")
                    }

                    if let messageCount = session.messageCount {
                        Text("\(messageCount)m")
                    }

                    if let modifiedAt = session.modifiedAt {
                        Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .foregroundStyle(.secondary)
                .font(.system(size: 10, weight: .medium))
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(session.sessionId == selectedSessionId ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(session.sessionId == selectedSessionId ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
        )
    }

    private func rowDotColor(for session: ClaudeSessionSummary) -> Color {
        if session.sessionId == selectedSessionId { return .accentColor }
        if registry.isOpen(session.sessionId) { return .green }
        return .secondary
    }

    private func stateText(_ state: ClaudeProjectLoadState) -> String {
        switch state {
        case .idle:
            return "Not loaded"
        case .loading:
            return "Loading..."
        case .loaded:
            return "Loaded"
        case .empty:
            return "No sessions"
        case .unavailable:
            return "Unavailable"
        case .error(let msg):
            return msg
        }
    }

    private func activate(
        session: ClaudeSessionSummary,
        project: ImportedClaudeProject,
        target: ClaudeSessionOpenTarget = .automatic
    ) {
        isSidebarFocused = true
        selectedProjectPath = project.projectPath
        selectedSessionId = session.sessionId
        let result = launcher.activate(
            session: session,
            preferredController: preferredController,
            target: target
        )
        if case .failed(let err) = result {
            errorMessage = err.localizedDescription
        }
    }

    private func importProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await store.importProject(at: url.path)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            moveSelection(delta: -1)
        case .down:
            moveSelection(delta: 1)
        default:
            break
        }
    }

    private func activateSelectedSession() -> BackportKeyPressResult {
        guard let projectPath = selectedProjectPath else { return .ignored }
        guard let project = store.projects.first(where: { $0.projectPath == projectPath }) else { return .ignored }
        let sessions = store.filteredSessions(for: projectPath)
        guard !sessions.isEmpty else { return .ignored }

        let session: ClaudeSessionSummary
        if let selectedSessionId,
           let matched = sessions.first(where: { $0.sessionId == selectedSessionId }) {
            session = matched
        } else {
            session = sessions[clampedVisibleStart(for: projectPath, totalCount: sessions.count)]
            self.selectedSessionId = session.sessionId
        }

        activate(session: session, project: project)
        return .handled
    }

    private func moveSelection(delta: Int) {
        guard delta != 0 else { return }
        guard let projectPath = selectedProjectPath ?? store.projects.first?.projectPath else { return }
        let sessions = store.filteredSessions(for: projectPath)
        guard !sessions.isEmpty else { return }

        let currentIndex = sessions.firstIndex(where: { $0.sessionId == selectedSessionId }) ?? (delta > 0 ? -1 : 0)
        let targetIndex = max(0, min(sessions.count - 1, currentIndex + delta))
        selectedProjectPath = projectPath
        selectedSessionId = sessions[targetIndex].sessionId
        store.setExpanded(true, for: projectPath)
        isSidebarFocused = true
        ensureVisibleWindowContains(index: targetIndex, for: projectPath, totalCount: sessions.count)
    }

    private func visibleSessions(for projectPath: String, sessions: [ClaudeSessionSummary]) -> [ClaudeSessionSummary] {
        let totalCount = sessions.count
        guard totalCount > maxVisibleSessionsPerProject else { return sessions }

        let start = clampedVisibleStart(for: projectPath, totalCount: totalCount)
        let end = min(totalCount, start + maxVisibleSessionsPerProject)
        return Array(sessions[start..<end])
    }

    private func clampedVisibleStart(for projectPath: String, totalCount: Int) -> Int {
        let maxStart = max(0, totalCount - maxVisibleSessionsPerProject)
        let start = visibleStartByProject[projectPath] ?? 0
        return max(0, min(maxStart, start))
    }

    private func ensureVisibleWindowContains(index: Int, for projectPath: String, totalCount: Int) {
        let maxStart = max(0, totalCount - maxVisibleSessionsPerProject)
        var start = clampedVisibleStart(for: projectPath, totalCount: totalCount)

        if index < start {
            start = index
        } else if index >= start + maxVisibleSessionsPerProject {
            start = index - maxVisibleSessionsPerProject + 1
        }

        visibleStartByProject[projectPath] = max(0, min(maxStart, start))
    }

    private func toggleProjectSelection(_ project: ImportedClaudeProject) {
        let projectPath = project.projectPath
        let isExpanded = store.expandedProjectPaths.contains(projectPath)

        selectedProjectPath = projectPath
        isSidebarFocused = true

        if isExpanded {
            store.setExpanded(false, for: projectPath)
            return
        }

        store.setExpanded(true, for: projectPath)

        let sessions = store.filteredSessions(for: projectPath)
        if let current = selectedSessionId,
           sessions.contains(where: { $0.sessionId == current }) {
            return
        }

        if let firstSession = visibleSessions(for: projectPath, sessions: sessions).first {
            selectedSessionId = firstSession.sessionId
        }
    }
}

private struct SidebarFocusEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}
