import AppKit
import QuartzCore

/// Draws only a translucent mask; never reads, captures or copies other apps' screen contents.
/// Windows are nonactivating and mouse-transparent, so underlying PDF controls remain usable.
@MainActor final class ScreenFocusMask {
    private var windows: [MaskWindow] = []
    private weak var ownerWindow: NSWindow?
    private var transitioning = false
    private var spaceObserver: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var escapeMonitor: Any?
    private var active = false
    private var regions: [CGRect] = []
    private var opacity = 0.48
    private var feather = 12.0
    private var holeVisibility = 1.0
    var onEscape: (() -> Void)?
    private(set) var screenCount = 0
    var diagnostic: String {
        "active=\(active) app=\(NSApp.isActive) transition=\(transitioning) owner=\(ownerWindow?.windowNumber ?? -1) ownerActiveSpace=\(ownerWindow?.isOnActiveSpace ?? false) fullscreen=\(ownerWindow?.styleMask.contains(.fullScreen) ?? false) masks=" + windows.map { window in
            let view = window.contentView as? FocusMaskView
            return "[id=\(window.windowNumber) visible=\(window.isVisible) activeSpace=\(window.isOnActiveSpace) frame=\(window.frame) bounds=\(view?.bounds ?? .zero) path=\(view?.maskLayer.path?.boundingBoxOfPath ?? .zero) alpha=\(view?.maskLayer.fillColor?.alpha ?? -1) level=\(window.level.rawValue) key=\(window.isKeyWindow) main=\(window.isMainWindow) parent=\(window.parent?.windowNumber ?? -1)]"
        }.joined(separator: " ")
    }
    var coversEveryScreen: Bool {
        active && NSApp.isActive && !windows.isEmpty && windows.count == NSScreen.screens.count &&
        zip(NSScreen.screens, windows).allSatisfy { screen, window in
            guard let view = window.contentView as? FocusMaskView,
                  let path = view.maskLayer.path, let fill = view.maskLayer.fillColor else { return false }
            return window.isVisible && window.isOnActiveSpace && window.frame == screen.frame && window.ignoresMouseEvents &&
            !window.isKeyWindow && !window.isMainWindow && window.level.rawValue > NSWindow.Level.normal.rawValue &&
            view.bounds.size == screen.frame.size && path.boundingBoxOfPath == view.bounds && fill.alpha > 0
        }
    }
    init() {
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let identifier = (notification.object as? NSWindow).map(ObjectIdentifier.init)
                let starting = name == NSWindow.willEnterFullScreenNotification || name == NSWindow.willExitFullScreenNotification
                MainActor.assumeIsolated {
                    guard let self, let owner = self.ownerWindow, ObjectIdentifier(owner) == identifier else { return }
                    self.transitioning = starting
                    if starting { self.windows.forEach { $0.orderOut(nil) } }
                    else { self.refresh() }
                }
            })
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.active, event.keyCode == 53 else { return event }
            self.onEscape?(); return nil
        }
    }
    func update(regions: [CGRect], opacity: Double, enabled: Bool, owner: NSWindow?, feather: Double = 12, holeVisibility: Double = 1) {
        let ownerChanged = ownerWindow !== owner
        if ownerChanged {
            for window in windows { window.parent?.removeChildWindow(window) }
            ownerWindow = owner; transitioning = false
        }
        guard self.regions != regions || self.opacity != opacity || self.feather != feather || self.holeVisibility != holeVisibility || active != enabled || ownerChanged || (enabled && windows.contains(where: { !$0.isOnActiveSpace })) else { return }
        self.regions = regions; self.opacity = opacity; self.feather = feather; self.holeVisibility = holeVisibility; active = enabled; refresh()
    }
    func hide() { active = false; windows.forEach { $0.orderOut(nil) } }
    private func refresh() {
        guard active, NSApp.isActive, !transitioning else { windows.forEach { $0.orderOut(nil) }; return }
        let screens = NSScreen.screens
        if windows.count != screens.count {
            windows.forEach { $0.close() }; windows = screens.map { screen in
                let window = MaskWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
                window.ignoresMouseEvents = true; window.hidesOnDeactivate = true
                window.isFloatingPanel = true; window.becomesKeyOnlyIfNeeded = true; window.animationBehavior = .none
                window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle, .stationary]
                window.isExcludedFromWindowsMenu = true; window.setAccessibilityElement(false)
                let view = FocusMaskView(frame: NSRect(origin: .zero, size: screen.frame.size)); window.contentView = view; return window
            }
        }
        screenCount = screens.count
        for (screen, window) in zip(screens, windows) {
            if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
            guard let view = window.contentView as? FocusMaskView else { continue }
            view.opacity = opacity
            view.feather = feather
            view.holeVisibility = holeVisibility
            view.holes = regions.compactMap { rect in
                let intersection = rect.insetBy(dx: -feather * 2.5, dy: -feather * 2.5).intersection(screen.frame)
                return intersection.isNull ? nil : CGRect(x: rect.minX - screen.frame.minX, y: rect.minY - screen.frame.minY, width: rect.width, height: rect.height)
            }
            // Keep the overlay independent: addChildWindow would force the parent's
            // normal window level, placing the mask below menu-bar/full-screen surfaces.
            view.renderMask()
            if !window.isVisible || !window.isOnActiveSpace { window.orderFrontRegardless() }
        }
    }
    private final class MaskWindow: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
