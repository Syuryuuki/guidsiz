import AppKit

/// A terminal window style that provides a transparent titlebar effect. With this effect, the titlebar
/// matches the background color of the window.
class TransparentTitlebarTerminalWindow: TerminalWindow {
    private let claudeSidebarTabBarGap: CGFloat = 64

    /// Stores the last surface configuration to reapply appearance when needed.
    /// This is necessary because various macOS operations (tab switching, tab bar
    /// visibility changes) can reset the titlebar appearance.
    private var lastSurfaceConfig: Ghostty.SurfaceView.DerivedConfig?

    /// KVO observation for tab group window changes.
    private var tabGroupWindowsObservation: NSKeyValueObservation?
    private var tabBarVisibleObservation: NSKeyValueObservation?
    private var focusedSurfaceObservation: NSObjectProtocol?
    private var nativeTabBarUpdateGeneration: UInt = 0
    private var nativeTabBarFrameObservers: [NSObjectProtocol] = []
    private var nativeTabBarObservedViewIDs: [ObjectIdentifier] = []
    private var isApplyingNativeTabBarFrames = false
    private var isQueuedNativeTabBarFrameUpdate = false

    deinit {
        tabGroupWindowsObservation?.invalidate()
        tabBarVisibleObservation?.invalidate()
        if let focusedSurfaceObservation {
            NotificationCenter.default.removeObserver(focusedSurfaceObservation)
        }
        clearNativeTabBarFrameObservers()
    }

    // MARK: NSWindow

    override func awakeFromNib() {
        super.awakeFromNib()

        // Setup all the KVO we will use, see the docs for the respective functions
        // to learn why we need KVO.
        setupKVO()
        setupFocusedSurfaceObservation()
    }

    override func becomeMain() {
        super.becomeMain()

        guard let lastSurfaceConfig else { return }
        syncAppearance(lastSurfaceConfig)
        scheduleNativeTabBarSidebarUpdate()

        // This is a nasty edge case. If we're going from 2 to 1 tab and the tab bar
        // automatically disappears, then we need to resync our appearance because
        // at some point macOS replaces the tab views.
        if tabGroup?.windows.count ?? 0 == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                self?.syncAppearance(self?.lastSurfaceConfig ?? lastSurfaceConfig)
            }
        }
    }

    override func update() {
        super.update()
        applyNativeTabBarForClaudeSidebar()

        // On macOS 13 to 15, we need to hide the NSVisualEffectView in order to allow our
        // titlebar to be truly transparent.
        if #unavailable(macOS 26) {
            if !effectViewIsHidden {
                hideEffectView()
            }
        }
    }

    // MARK: Appearance

    override func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        super.syncAppearance(surfaceConfig)
        // override appearance based on the terminal's background color
        if let preferredBackgroundColor {
            appearance = (preferredBackgroundColor.isLightColor ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua))
        }

        // Save our config in case we need to reapply
        lastSurfaceConfig = surfaceConfig

        // Every time we change appearance, set KVO up again in case any of our
        // references changed (e.g. tabGroup is new).
        setupKVO()

        if #available(macOS 26.0, *) {
            syncAppearanceTahoe(surfaceConfig)
        } else {
            syncAppearanceVentura(surfaceConfig)
        }

        updateForClaudeSidebarInset()
    }

    override func updateForClaudeSidebarInset() {
        super.updateForClaudeSidebarInset()
        scheduleNativeTabBarSidebarUpdate()
    }

    @available(macOS 26.0, *)
    private func syncAppearanceTahoe(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        // When we have transparency, we need to set the titlebar background to match the
        // window background but with opacity. The window background is set using the
        // "preferred background color" property.
        //
        // Even if we aren't transparent, we still set this because this becomes the
        // color of the titlebar in native fullscreen view.
        if let titlebarView = titlebarContainer?.firstDescendant(withClassName: "NSTitlebarView") {
            titlebarView.wantsLayer = true

            // For glass background styles, use a transparent titlebar to let the glass effect show through
            // Only apply this for transparent and tabs titlebar styles
            let isGlassStyle = derivedConfig.backgroundBlur.isGlassStyle
            let isTransparentTitlebar = derivedConfig.macosTitlebarStyle == .transparent ||
            derivedConfig.macosTitlebarStyle == .tabs

            titlebarView.layer?.backgroundColor = (isGlassStyle && isTransparentTitlebar)
                ? NSColor.clear.cgColor
                : preferredBackgroundColor?.cgColor
        }

        // In all cases, we have to hide the background view since this has multiple subviews
        // that force a background color.
        titlebarBackgroundView?.isHidden = true
    }

    @available(macOS 13.0, *)
    private func syncAppearanceVentura(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        guard let titlebarContainer else { return }

        // Setup the titlebar background color to match ours
        titlebarContainer.wantsLayer = true
        titlebarContainer.layer?.backgroundColor = preferredBackgroundColor?.cgColor

        // See the docs for the function that sets this to true on why
        effectViewIsHidden = false

        // Necessary to not draw the border around the title
        titlebarAppearsTransparent = true
    }

    // MARK: View Finders

    private var titlebarBackgroundView: NSView? {
        titlebarContainer?.firstDescendant(withClassName: "NSTitlebarBackgroundView")
    }

    // MARK: Tab Group Observation

    private func setupKVO() {
        // See the docs for the respective setup functions for why.
        setupTabGroupObservation()
        setupTabBarVisibleObservation()
    }

    private func setupFocusedSurfaceObservation() {
        if let focusedSurfaceObservation {
            NotificationCenter.default.removeObserver(focusedSurfaceObservation)
        }

        focusedSurfaceObservation = NotificationCenter.default.addObserver(
            forName: .ghosttyTerminalFocusedSurfaceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let source = note.object as? BaseTerminalController else { return }
            guard source === self.windowController as? BaseTerminalController else { return }

            // AppKit may restyle and relayout the native tab bar asynchronously after
            // focus/tab changes, so we re-apply our inset over the next few turns.
            self.scheduleNativeTabBarSidebarUpdate()
        }
    }

    private func clearNativeTabBarFrameObservers() {
        let center = NotificationCenter.default
        for observer in nativeTabBarFrameObservers {
            center.removeObserver(observer)
        }
        nativeTabBarFrameObservers.removeAll()
        nativeTabBarObservedViewIDs.removeAll()
    }

    /// Monitors the tabGroup windows value for any changes and resyncs the appearance on change.
    /// This is necessary because when the windows change, the tab bar and titlebar are recreated
    /// which breaks our changes.
    private func setupTabGroupObservation() {
        // Remove existing observation if any
        tabGroupWindowsObservation?.invalidate()
        tabGroupWindowsObservation = nil
        clearNativeTabBarFrameObservers()

        // Check if tabGroup is available
        guard let tabGroup else { return }

        // Set up KVO observation for the windows array. Whenever it changes
        // we resync the appearance because it can cause macOS to redraw the
        // tab bar.
        tabGroupWindowsObservation = tabGroup.observe(
            \.windows,
             options: [.new]
        ) { [weak self] _, _ in
            // NOTE: At one point, I guarded this on only if we went from 0 to N
            // or N to 0 under the assumption that the tab bar would only get
            // replaced on those cases. This turned out to be false (Tahoe).
            // It's cheap enough to always redraw this so we should just do it
            // unconditionally.

            guard let self else { return }
            guard let lastSurfaceConfig else { return }
            self.syncAppearance(lastSurfaceConfig)
            self.scheduleNativeTabBarSidebarUpdate()
        }
    }

    /// Monitors the tab bar for visibility. This lets the "Show/Hide Tab Bar" manual menu item
    /// to not break our appearance.
    private func setupTabBarVisibleObservation() {
        // Remove existing observation if any
        tabBarVisibleObservation?.invalidate()
        tabBarVisibleObservation = nil

        // Set up KVO observation for isTabBarVisible
        tabBarVisibleObservation = tabGroup?.observe(
            \.isTabBarVisible,
             options: [.new]
        ) { [weak self] _, _ in
            guard let self else { return }
            guard let lastSurfaceConfig else { return }
            self.syncAppearance(lastSurfaceConfig)
            self.scheduleNativeTabBarSidebarUpdate()
        }
    }

    // MARK: macOS 13 to 15

    // We only need to set this once, but need to do it after the window has been created in order
    // to determine if the theme is using a very dark background, in which case we don't want to
    // remove the effect view if the default tab bar is being used since the effect created in
    // `updateTabsForVeryDarkBackgrounds` creates a confusing visual design.
    private var effectViewIsHidden = false

    private func hideEffectView() {
        guard !effectViewIsHidden else { return }

        // By hiding the visual effect view, we allow the window's (or titlebar's in this case)
        // background color to show through. If we were to set `titlebarAppearsTransparent` to true
        // the selected tab would look fine, but the unselected ones and new tab button backgrounds
        // would be an opaque color. When the titlebar isn't transparent, however, the system applies
        // a compositing effect to the unselected tab backgrounds, which makes them blend with the
        // titlebar's/window's background.
        if let effectView = titlebarContainer?.descendants(withClassName: "NSVisualEffectView").first {
            effectView.isHidden = true
        }

        effectViewIsHidden = true
    }

    private func scheduleNativeTabBarSidebarUpdate() {
        nativeTabBarUpdateGeneration &+= 1
        let generation = nativeTabBarUpdateGeneration

        applyNativeTabBarForClaudeSidebar()

        DispatchQueue.main.async { [weak self] in
            self?.applyScheduledNativeTabBarUpdate(generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            self?.applyScheduledNativeTabBarUpdate(generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
            self?.applyScheduledNativeTabBarUpdate(generation: generation)
        }
    }

    private func applyScheduledNativeTabBarUpdate(generation: UInt) {
        guard generation == nativeTabBarUpdateGeneration else { return }
        applyNativeTabBarForClaudeSidebar()
    }

    private func queueNativeTabBarSidebarUpdate() {
        guard !isQueuedNativeTabBarFrameUpdate else { return }
        isQueuedNativeTabBarFrameUpdate = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isQueuedNativeTabBarFrameUpdate = false
            self.scheduleNativeTabBarSidebarUpdate()
        }
    }

    private func nativeTabBarComponents() -> (
        titlebarView: NSView,
        containerView: NSView,
        clipView: NSView,
        tabHost: NSView,
        tabBar: NSView
    )? {
        guard
            let titlebarView = titlebarContainer?.firstDescendant(withClassName: "NSTitlebarView"),
            let tabBar = titlebarView.firstDescendant(withClassName: "NSTabBar"),
            let clipView = tabBar.firstSuperview(withClassName: "NSTitlebarAccessoryClipView"),
            let tabHost = tabBar.superview,
            let containerView = clipView.superview
        else { return nil }

        return (titlebarView, containerView, clipView, tabHost, tabBar)
    }

    private func ensureNativeTabBarFrameObservers(
        titlebarView: NSView,
        containerView: NSView,
        clipView: NSView,
        tabHost: NSView,
        tabBar: NSView
    ) {
        let views = [titlebarView, containerView, clipView, tabHost, tabBar]
        let ids = views.map(ObjectIdentifier.init)
        guard ids != nativeTabBarObservedViewIDs else { return }

        clearNativeTabBarFrameObservers()
        nativeTabBarObservedViewIDs = ids

        let center = NotificationCenter.default
        nativeTabBarFrameObservers = views.map { view in
            view.postsFrameChangedNotifications = true
            return center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: view,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                guard !self.isApplyingNativeTabBarFrames else { return }
                self.queueNativeTabBarSidebarUpdate()
            }
        }
    }

    private func applyNativeTabBarForClaudeSidebar() {
        guard let components = nativeTabBarComponents() else { return }

        let titlebarView = components.titlebarView
        let containerView = components.containerView
        let clipView = components.clipView
        let tabHost = components.tabHost
        let tabBar = components.tabBar

        ensureNativeTabBarFrameObservers(
            titlebarView: titlebarView,
            containerView: containerView,
            clipView: clipView,
            tabHost: tabHost,
            tabBar: tabBar
        )

        isApplyingNativeTabBarFrames = true
        defer { isApplyingNativeTabBarFrames = false }

        titlebarView.layoutSubtreeIfNeeded()
        containerView.superview?.layoutSubtreeIfNeeded()
        containerView.layoutSubtreeIfNeeded()

        let inset = max(0, claudeSidebarLeadingInset + claudeSidebarTabBarGap)
        let targetWidth = max(0, titlebarView.bounds.width - inset)

        if containerView.frame.origin.x != inset || containerView.frame.width != targetWidth {
            containerView.frame = NSRect(
                x: inset,
                y: containerView.frame.origin.y,
                width: targetWidth,
                height: containerView.frame.height
            )
        }

        if clipView.frame != containerView.bounds {
            clipView.frame = containerView.bounds
        }

        if tabHost.frame != clipView.bounds {
            tabHost.frame = clipView.bounds
        }

        let tabBarHeight = tabBar.frame.height
        let targetTabBarFrame = NSRect(
            x: 0,
            y: max(0, tabHost.bounds.height - tabBarHeight),
            width: tabHost.bounds.width,
            height: tabBarHeight
        )
        if tabBar.frame != targetTabBarFrame {
            tabBar.frame = targetTabBarFrame
        }

        containerView.needsLayout = true
        clipView.needsLayout = true
        tabHost.needsLayout = true
        tabBar.needsLayout = true
        titlebarView.layoutSubtreeIfNeeded()
    }
}
