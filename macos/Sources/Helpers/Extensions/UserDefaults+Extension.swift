import Foundation

extension UserDefaults {
    enum ClaudeSidebarKey {
        static let importedProjects = "ClaudeSidebar.ImportedProjects"
        static let expandedProjects = "ClaudeSidebar.ExpandedProjects"
        static let isVisible = "ClaudeSidebar.IsVisible"
        static let width = "ClaudeSidebar.Width"
        static let selectedProjectPath = "ClaudeSidebar.SelectedProjectPath"
    }

    static var ghosttySuite: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["GHOSTTY_USER_DEFAULTS_SUITE"]
        #else
        nil
        #endif
    }

    static var ghostty: UserDefaults {
        ghosttySuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
