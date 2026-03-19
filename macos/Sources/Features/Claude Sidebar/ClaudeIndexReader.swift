import Foundation

final class ClaudeIndexReader: ClaudeIndexReading {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let dateFormatter: ISO8601DateFormatter
    private let fallbackDateFormatter: ISO8601DateFormatter

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()

        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        self.fallbackDateFormatter = ISO8601DateFormatter()
        self.fallbackDateFormatter.formatOptions = [.withInternetDateTime]
    }

    func hasClaudeData(forProjectPath projectPath: String) -> Bool {
        if (try? findMatchingIndex(forProjectPath: projectPath)) != nil {
            return true
        }

        if let projectDirectories = try? findMatchingProjectDirectories(forProjectPath: projectPath) {
            return !projectDirectories.isEmpty
        }

        return false
    }

    func discoverProjectPaths() throws -> [String] {
        var result: Set<String> = []

        for projectDir in try findProjectDirectories() {
            let projectPath = normalizePath(resolveProjectPath(fromProjectDirectory: projectDir))
            if !projectPath.isEmpty {
                result.insert(projectPath)
            }
        }

        return Array(result).sorted()
    }

    func findSessions(forProjectPath projectPath: String) throws -> [ClaudeSessionSummary] {
        if let indexURL = try findMatchingIndex(forProjectPath: projectPath) {
            return try findSessionsFromIndex(projectPath: projectPath, indexURL: indexURL)
        }

        let summaries = try findSessionsFromProjectDirectories(projectPath: projectPath)
        guard !summaries.isEmpty else {
            throw ClaudeDataError.noSessionsIndex
        }
        return summaries
    }

    private func findSessionsFromIndex(projectPath: String, indexURL: URL) throws -> [ClaudeSessionSummary] {
        let index = try loadIndex(at: indexURL)
        let normalizedProjectPath = normalizePath(projectPath)

        let result: [ClaudeSessionSummary] = index.entries.compactMap { entry in
            let entryProjectPath = normalizePath(entry.projectPath ?? index.originalPath ?? projectPath)
            guard entryProjectPath == normalizedProjectPath else { return nil }

            let transcriptPath: String = if let fullPath = entry.fullPath {
                fullPath
            } else {
                indexURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("\(entry.sessionId).jsonl")
                    .path
            }

            return ClaudeSessionSummary(
                sessionId: entry.sessionId,
                projectPath: entryProjectPath,
                transcriptPath: transcriptPath,
                firstPrompt: entry.firstPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                gitBranch: entry.gitBranch,
                messageCount: entry.messageCount,
                createdAt: parseDate(entry.created),
                modifiedAt: parseDate(entry.modified) ?? dateFromMtime(entry.fileMtime),
                isSidechain: entry.isSidechain ?? false
            )
        }

        return result.sorted { lhs, rhs in
            compareSession(lhs, rhs)
        }
    }

    private func findSessionsFromProjectDirectories(projectPath: String) throws -> [ClaudeSessionSummary] {
        let matchedDirs = try findMatchingProjectDirectories(forProjectPath: projectPath)
        let normalizedProjectPath = normalizePath(projectPath)
        var summaries: [ClaudeSessionSummary] = []

        for projectDir in matchedDirs {
            for jsonlURL in try findSessionFiles(in: projectDir) {
                if let summary = makeSessionSummaryFromJsonl(
                    fileURL: jsonlURL,
                    projectPath: normalizedProjectPath
                ) {
                    summaries.append(summary)
                }
            }
        }

        return summaries.sorted { lhs, rhs in
            compareSession(lhs, rhs)
        }
    }

    private func compareSession(_ lhs: ClaudeSessionSummary, _ rhs: ClaudeSessionSummary) -> Bool {
        let lhsDate = lhs.modifiedAt ?? lhs.createdAt ?? Date.distantPast
        let rhsDate = rhs.modifiedAt ?? rhs.createdAt ?? Date.distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.sessionId > rhs.sessionId
    }

    private func findMatchingProjectDirectories(forProjectPath projectPath: String) throws -> [URL] {
        let normalizedProjectPath = normalizePath(projectPath)
        guard !normalizedProjectPath.isEmpty else { return [] }

        var matched: [URL] = []
        for projectDir in try findProjectDirectories() {
            let detectedPath = normalizePath(resolveProjectPath(fromProjectDirectory: projectDir))
            if detectedPath == normalizedProjectPath {
                matched.append(projectDir)
            }
        }

        return matched
    }

    private func findMatchingIndex(forProjectPath projectPath: String) throws -> URL? {
        let normalizedProjectPath = normalizePath(projectPath)
        for indexURL in try findIndexFiles() {
            guard let index = try? loadIndex(at: indexURL) else { continue }

            if normalizePath(index.originalPath) == normalizedProjectPath {
                return indexURL
            }

            if index.entries.contains(where: { normalizePath($0.projectPath) == normalizedProjectPath }) {
                return indexURL
            }
        }

        return nil
    }

    private func findProjectDirectories() throws -> [URL] {
        let root = projectsRoot()
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func findIndexFiles() throws -> [URL] {
        let root = projectsRoot()
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "sessions-index.json" {
            result.append(url)
        }

        return result
    }

    private func findSessionFiles(in projectDirectory: URL) throws -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files.filter { url in
            url.pathExtension == "jsonl"
        }
    }

    private func detectProjectPath(fromProjectDirectory projectDirectory: URL) -> String? {
        guard let sessionFiles = try? findSessionFiles(in: projectDirectory) else { return nil }

        for sessionFile in sessionFiles {
            guard let content = try? String(contentsOf: sessionFile, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true).prefix(10) {
                guard let data = line.data(using: .utf8) else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                guard let cwd = json["cwd"] as? String, !cwd.isEmpty else { continue }
                return cwd
            }
        }

        return nil
    }

    private func resolveProjectPath(fromProjectDirectory projectDirectory: URL) -> String? {
        if let detected = detectProjectPath(fromProjectDirectory: projectDirectory) {
            return detected
        }

        let decoded = decodeProjectPath(fromDirectoryName: projectDirectory.lastPathComponent)
        return decoded.isEmpty ? nil : decoded
    }

    private func decodeProjectPath(fromDirectoryName name: String) -> String {
        name.replacingOccurrences(of: "-", with: "/")
    }

    private func makeSessionSummaryFromJsonl(fileURL: URL, projectPath: String) -> ClaudeSessionSummary? {
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        guard !sessionId.isEmpty else { return nil }

        let fileAttributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let createdAt = fileAttributes?[.creationDate] as? Date
        let modifiedAt = fileAttributes?[.modificationDate] as? Date

        let parsed = parseJsonlMetadata(fileURL: fileURL)

        return ClaudeSessionSummary(
            sessionId: sessionId,
            projectPath: projectPath,
            transcriptPath: fileURL.path,
            firstPrompt: parsed.firstPrompt,
            gitBranch: parsed.gitBranch,
            messageCount: parsed.messageCount,
            createdAt: parsed.createdAt ?? createdAt,
            modifiedAt: parsed.modifiedAt ?? modifiedAt,
            isSidechain: parsed.isSidechain
        )
    }

    private func parseJsonlMetadata(fileURL: URL) -> (
        firstPrompt: String?,
        createdAt: Date?,
        modifiedAt: Date?,
        messageCount: Int?,
        gitBranch: String?,
        isSidechain: Bool
    ) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return (nil, nil, nil, nil, nil, false)
        }

        var firstPrompt: String?
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var messageCount = 0
        var gitBranch: String?
        var isSidechain = false

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let timestamp = json["timestamp"] as? String, let date = parseDate(timestamp) {
                if firstTimestamp == nil { firstTimestamp = date }
                lastTimestamp = date
            }

            if gitBranch == nil, let branch = json["gitBranch"] as? String, !branch.isEmpty {
                gitBranch = branch
            }

            if !isSidechain, let sidechain = json["isSidechain"] as? Bool {
                isSidechain = sidechain
            }

            if let type = json["type"] as? String, type == "assistant" || type == "user" {
                messageCount += 1
            }

            if firstPrompt == nil,
               let message = json["message"] as? [String: Any],
               let role = message["role"] as? String,
               role == "user" {
                let text = extractMessageContentText(message["content"])
                if isValidPromptText(text) {
                    firstPrompt = text
                }
            }
        }

        return (
            firstPrompt,
            firstTimestamp,
            lastTimestamp,
            messageCount > 0 ? messageCount : nil,
            gitBranch,
            isSidechain
        )
    }

    private func extractMessageContentText(_ content: Any?) -> String? {
        if let content = content as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let contentArray = content as? [[String: Any]] {
            for item in contentArray {
                guard let type = item["type"] as? String else { continue }
                guard type == "text" else { continue }
                guard let text = item["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    private func isValidPromptText(_ text: String?) -> Bool {
        guard let text else { return false }
        if text.contains("Caveat: The messages below were generated by the user while running local commands") {
            return false
        }
        if text.hasPrefix("<command-name>") { return false }
        if text.hasPrefix("<local-command-stdout>") { return false }
        return true
    }

    private func projectsRoot() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    private func loadIndex(at url: URL) throws -> ClaudeSessionsIndexFile {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ClaudeSessionsIndexFile.self, from: data)
        } catch {
            throw ClaudeDataError.malformedIndex
        }
    }

    private func normalizePath(_ path: String?) -> String {
        guard let path else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        return dateFormatter.date(from: dateString) ?? fallbackDateFormatter.date(from: dateString)
    }

    private func dateFromMtime(_ mtime: Double?) -> Date? {
        guard let mtime else { return nil }
        return Date(timeIntervalSince1970: mtime / 1000)
    }
}
