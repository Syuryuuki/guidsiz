import Foundation

final class ClaudeProjectsStore: ObservableObject {
    @Published private(set) var projects: [ImportedClaudeProject] = []
    @Published private(set) var sessionsByProject: [String: [ClaudeSessionSummary]] = [:]
    @Published private(set) var stateByProject: [String: ClaudeProjectLoadState] = [:]
    @Published var searchText: String = ""
    @Published var expandedProjectPaths: Set<String> = []

    private let reader: ClaudeIndexReading
    private let defaults: UserDefaults
    private var didBootstrap = false

    private static let projectsKey = UserDefaults.ClaudeSidebarKey.importedProjects
    private static let expandedProjectsKey = UserDefaults.ClaudeSidebarKey.expandedProjects

    init(
        reader: ClaudeIndexReading = ClaudeIndexReader(),
        defaults: UserDefaults = .ghostty
    ) {
        self.reader = reader
        self.defaults = defaults
        restoreImportedProjects()
        restoreExpandedProjects()
    }

    func importProject(at path: String) async throws {
        let normalized = normalizePath(path)
        guard FileManager.default.fileExists(atPath: normalized) else {
            throw ClaudeDataError.projectNotFound
        }
        guard reader.hasClaudeData(forProjectPath: normalized) else {
            throw ClaudeDataError.noSessionsIndex
        }

        if projects.contains(where: { normalizePath($0.projectPath) == normalized }) {
            return
        }

        let project = ImportedClaudeProject(
            id: UUID(),
            projectPath: normalized,
            displayName: URL(fileURLWithPath: normalized).lastPathComponent,
            importedAt: Date()
        )

        projects.append(project)
        expandedProjectPaths.insert(project.projectPath)
        sortProjectsByActivity()
        persistImportedProjects()
        persistExpandedProjects()
        await refreshProject(project)
    }

    func bootstrapOnLaunch() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        removeUnreasonableAutoImportedProjects()
        autoImportProjectsFromClaudeIndex()
        await refreshAll()
    }

    func removeProject(_ project: ImportedClaudeProject) {
        projects.removeAll { $0.id == project.id }
        sessionsByProject.removeValue(forKey: project.projectPath)
        stateByProject.removeValue(forKey: project.projectPath)
        expandedProjectPaths.remove(project.projectPath)
        persistImportedProjects()
        persistExpandedProjects()
    }

    func refreshAll() async {
        for project in projects {
            await refreshProject(project)
        }
        sortProjectsByActivity()
        persistImportedProjects()
    }

    func refreshProject(_ project: ImportedClaudeProject) async {
        stateByProject[project.projectPath] = .loading

        guard FileManager.default.fileExists(atPath: project.projectPath) else {
            stateByProject[project.projectPath] = .unavailable
            sessionsByProject[project.projectPath] = []
            return
        }

        do {
            let sessions = try reader.findSessions(forProjectPath: project.projectPath)
            sessionsByProject[project.projectPath] = sessions
            stateByProject[project.projectPath] = sessions.isEmpty ? .empty : .loaded
            sortProjectsByActivity()
            persistImportedProjects()
        } catch let error as ClaudeDataError {
            if case .noSessionsIndex = error {
                stateByProject[project.projectPath] = .unavailable
                sessionsByProject[project.projectPath] = []
                sortProjectsByActivity()
                persistImportedProjects()
            } else {
                stateByProject[project.projectPath] = .error(error.localizedDescription)
            }
        } catch {
            stateByProject[project.projectPath] = .error(error.localizedDescription)
        }
    }

    func filteredSessions(for projectPath: String) -> [ClaudeSessionSummary] {
        let sessions = sessionsByProject[projectPath] ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }

        return sessions.filter { session in
            let prompt = session.firstPrompt ?? ""
            let branch = session.gitBranch ?? ""
            return prompt.localizedCaseInsensitiveContains(query) ||
                branch.localizedCaseInsensitiveContains(query) ||
                session.sessionId.localizedCaseInsensitiveContains(query)
        }
    }

    func setExpanded(_ expanded: Bool, for projectPath: String) {
        if expanded {
            expandedProjectPaths.insert(projectPath)
        } else {
            expandedProjectPaths.remove(projectPath)
        }
        persistExpandedProjects()
    }

    private func restoreImportedProjects() {
        guard let data = defaults.data(forKey: Self.projectsKey) else { return }
        guard let decoded = try? JSONDecoder().decode([ImportedClaudeProject].self, from: data) else { return }
        projects = decoded
    }

    private func autoImportProjectsFromClaudeIndex() {
        guard let discovered = try? reader.discoverProjectPaths() else { return }
        guard !discovered.isEmpty else { return }

        var didChange = false
        let existingPaths = Set(projects.map { normalizePath($0.projectPath) })

        for path in discovered {
            let normalized = normalizePath(path)
            guard !normalized.isEmpty else { continue }
            guard isReasonableAutoImportPath(normalized) else { continue }
            guard !existingPaths.contains(normalized) else { continue }
            guard FileManager.default.fileExists(atPath: normalized) else { continue }

            let project = ImportedClaudeProject(
                id: UUID(),
                projectPath: normalized,
                displayName: URL(fileURLWithPath: normalized).lastPathComponent,
                importedAt: Date()
            )
            projects.append(project)
            expandedProjectPaths.insert(project.projectPath)
            didChange = true
        }

        guard didChange else { return }
        sortProjectsByActivity()
        persistImportedProjects()
        persistExpandedProjects()
    }

    private func removeUnreasonableAutoImportedProjects() {
        let before = projects.count
        projects.removeAll { !isReasonableAutoImportPath(normalizePath($0.projectPath)) }

        guard projects.count != before else { return }
        let validPaths = Set(projects.map { normalizePath($0.projectPath) })
        sessionsByProject = sessionsByProject.filter { validPaths.contains(normalizePath($0.key)) }
        stateByProject = stateByProject.filter { validPaths.contains(normalizePath($0.key)) }
        expandedProjectPaths = Set(expandedProjectPaths.filter { validPaths.contains(normalizePath($0)) })
        persistImportedProjects()
        persistExpandedProjects()
    }

    private func isReasonableAutoImportPath(_ path: String) -> Bool {
        let normalized = normalizePath(path)
        let homePath = normalizePath(FileManager.default.homeDirectoryForCurrentUser.path)
        if normalized == homePath { return false }
        if normalized == "/" { return false }
        return true
    }

    private func persistImportedProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: Self.projectsKey)
    }

    private func restoreExpandedProjects() {
        if let values = defaults.array(forKey: Self.expandedProjectsKey) as? [String] {
            expandedProjectPaths = Set(values)
        }
    }

    private func sortProjectsByActivity() {
        projects.sort { lhs, rhs in
            let lhsRecent = latestActivityDate(for: lhs)
            let rhsRecent = latestActivityDate(for: rhs)
            if lhsRecent != rhsRecent { return lhsRecent > rhsRecent }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func latestActivityDate(for project: ImportedClaudeProject) -> Date {
        let sessions = sessionsByProject[project.projectPath] ?? []
        let mostRecentSession = sessions.compactMap { $0.modifiedAt ?? $0.createdAt }.max()
        return mostRecentSession ?? project.importedAt
    }

    private func persistExpandedProjects() {
        defaults.set(Array(expandedProjectPaths), forKey: Self.expandedProjectsKey)
    }

    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
