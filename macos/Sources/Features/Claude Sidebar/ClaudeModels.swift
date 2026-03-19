import Foundation
import GhosttyKit

struct ClaudeSessionsIndexFile: Codable {
    let version: Int
    let entries: [ClaudeSessionsIndexEntry]
    let originalPath: String?
}

struct ClaudeSessionsIndexEntry: Codable {
    let sessionId: String
    let fullPath: String?
    let fileMtime: Double?
    let firstPrompt: String?
    let messageCount: Int?
    let created: String?
    let modified: String?
    let gitBranch: String?
    let projectPath: String?
    let isSidechain: Bool?
}

struct ImportedClaudeProject: Identifiable, Codable, Hashable {
    let id: UUID
    let projectPath: String
    let displayName: String
    let importedAt: Date
}

struct ClaudeSessionSummary: Identifiable, Hashable {
    var id: String { sessionId }

    let sessionId: String
    let projectPath: String
    let transcriptPath: String
    let firstPrompt: String?
    let gitBranch: String?
    let messageCount: Int?
    let createdAt: Date?
    let modifiedAt: Date?
    let isSidechain: Bool
}

struct ClaudeSessionContext: Codable, Hashable {
    let sessionId: String
    let projectPath: String
    let openedAt: Date
}

enum ClaudeProjectLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case unavailable
    case error(String)
}

enum ClaudeDataError: LocalizedError {
    case projectNotFound
    case noSessionsIndex
    case malformedIndex
    case claudeCliNotFound
    case terminalCreateFailed
    case surfaceUnavailable

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project path does not exist."
        case .noSessionsIndex:
            return "No Claude sessions index was found for this project."
        case .malformedIndex:
            return "Claude sessions index is malformed."
        case .claudeCliNotFound:
            return "Unable to find `claude` executable in PATH."
        case .terminalCreateFailed:
            return "Unable to create terminal tab/window for this session."
        case .surfaceUnavailable:
            return "Unable to locate the created terminal surface."
        }
    }
}

enum ClaudeActivationResult {
    case focusedExisting
    case openedNew
    case failed(ClaudeDataError)
}

enum ClaudeSessionOpenTarget {
    case automatic
    case currentWindow
    case newWindow
}

protocol ClaudeIndexReading {
    func findSessions(forProjectPath projectPath: String) throws -> [ClaudeSessionSummary]
    func hasClaudeData(forProjectPath projectPath: String) -> Bool
    func discoverProjectPaths() throws -> [String]
}
