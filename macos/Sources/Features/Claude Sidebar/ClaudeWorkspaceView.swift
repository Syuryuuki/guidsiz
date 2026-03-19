import SwiftUI
import GhosttyKit

struct ClaudeWorkspaceView<Content: View>: View {
    @ObservedObject var ghostty: Ghostty.App
    @ObservedObject var controller: TerminalController
    @ObservedObject var projectsStore: ClaudeProjectsStore
    @ObservedObject var registry: ClaudeSessionRegistry

    let launcher: ClaudeSessionLauncher
    let content: () -> Content

    @State private var sidebarVisible: Bool = true
    @State private var sidebarWidth: CGFloat = 232
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var didRestoreSidebarState: Bool = false
    @State private var selectedProjectPath: String?
    @State private var selectedSessionId: String?

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                ClaudeSidebarView(
                    store: projectsStore,
                    registry: registry,
                    preferredController: controller,
                    launcher: launcher,
                    onToggleSidebar: { sidebarVisible = false },
                    backgroundColor: ghostty.config.backgroundColor,
                    selectedProjectPath: $selectedProjectPath,
                    selectedSessionId: $selectedSessionId
                )
                .frame(width: sidebarWidth)
                .frame(minWidth: 208, maxWidth: 320)

                Color.clear
                    .frame(width: 4)
                    .contentShape(Rectangle())
                    .gesture(sidebarResizeGesture)
                    .overlay(alignment: .center) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1, height: 64)
                    }
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if !sidebarVisible {
                        Button {
                            sidebarVisible = true
                        } label: {
                            Image(systemName: "sidebar.leading")
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
        }
        .onAppear {
            Task { await projectsStore.bootstrapOnLaunch() }
            registerSurfaceContexts()
            syncSelectionFromFocusedSurface()
            restoreSidebarStateIfNeeded()
        }
        .onReceive(controller.$surfaceTree) { _ in
            registerSurfaceContexts()
            syncSelectionFromFocusedSurface()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyTerminalFocusedSurfaceDidChange)) { note in
            guard let source = note.object as? BaseTerminalController, source === controller else { return }
            syncSelectionFromFocusedSurface()
        }
        .onChange(of: sidebarVisible) { visible in
            UserDefaults.ghostty.set(visible, forKey: UserDefaults.ClaudeSidebarKey.isVisible)
        }
        .onChange(of: sidebarWidth) { width in
            UserDefaults.ghostty.set(width, forKey: UserDefaults.ClaudeSidebarKey.width)
        }
        .onChange(of: selectedProjectPath) { path in
            UserDefaults.ghostty.set(path, forKey: UserDefaults.ClaudeSidebarKey.selectedProjectPath)
        }
    }

    private var sidebarResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if sidebarDragStartWidth == nil {
                    sidebarDragStartWidth = sidebarWidth
                }

                let start = sidebarDragStartWidth ?? sidebarWidth
                sidebarWidth = max(208, min(320, start + value.translation.width))
            }
            .onEnded { _ in
                sidebarDragStartWidth = nil
            }
    }

    private func restoreSidebarStateIfNeeded() {
        guard !didRestoreSidebarState else { return }
        didRestoreSidebarState = true

        if UserDefaults.ghostty.object(forKey: UserDefaults.ClaudeSidebarKey.isVisible) != nil {
            sidebarVisible = UserDefaults.ghostty.bool(forKey: UserDefaults.ClaudeSidebarKey.isVisible)
        }

        let savedWidth = UserDefaults.ghostty.double(forKey: UserDefaults.ClaudeSidebarKey.width)
        if savedWidth > 0 {
            sidebarWidth = max(208, min(320, savedWidth))
        }

        if selectedProjectPath == nil {
            selectedProjectPath = UserDefaults.ghostty.string(forKey: UserDefaults.ClaudeSidebarKey.selectedProjectPath)
        }
    }

    private func syncSelectionFromFocusedSurface() {
        selectedSessionId = controller.focusedSurface?.claudeSessionContext?.sessionId
        if let path = controller.focusedSurface?.claudeSessionContext?.projectPath {
            selectedProjectPath = path
        }
    }

    private func registerSurfaceContexts() {
        for surface in controller.surfaceTree {
            guard let context = surface.claudeSessionContext else { continue }
            registry.register(
                sessionId: context.sessionId,
                projectPath: context.projectPath,
                surface: surface,
                controller: controller
            )
        }
    }
}
