import AppKit
import QuartzCore

/// Draws only a translucent mask; never reads, captures or copies other apps' screen contents.
/// Windows are nonactivating and mouse-transparent, so underlying PDF controls remain usable.
@MainActor final class ScreenFocusMask {
    private var windows: [MaskWindow] = []
    private var observers: [NSObjectProtocol] = []
    private var escapeMonitor: Any?
    private var active = false
    private var regions: [CGRect] = []
    private var opacity = 0.48
    var onEscape: (() -> Void)?
    private(set) var screenCount = 0
    var coversEveryScreen: Bool {
        active && NSApp.isActive && !windows.isEmpty && windows.count == NSScreen.screens.count &&
        zip(NSScreen.screens, windows).allSatisfy { screen, window in
            guard let view = window.contentView as? MaskView,
                  let path = view.maskLayer.path, let fill = view.maskLayer.fillColor else { return false }
            return window.isVisible && window.frame == screen.frame && window.ignoresMouseEvents &&
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
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.active, event.keyCode == 53 else { return event }
            self.onEscape?(); return nil
        }
    }
    func update(regions: [CGRect], opacity: Double, enabled: Bool) {
        guard self.regions != regions || self.opacity != opacity || active != enabled else { return }
        self.regions = regions; self.opacity = opacity; active = enabled; refresh()
    }
    func hide() { active = false; windows.forEach { $0.orderOut(nil) } }
    private func refresh() {
        guard active, NSApp.isActive else { windows.forEach { $0.orderOut(nil) }; return }
        let screens = NSScreen.screens
        if windows.count != screens.count {
            windows.forEach { $0.close() }; windows = screens.map { screen in
                let window = MaskWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
                window.ignoresMouseEvents = true; window.hidesOnDeactivate = true
                window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
                window.isExcludedFromWindowsMenu = true; window.setAccessibilityElement(false)
                let view = MaskView(frame: NSRect(origin: .zero, size: screen.frame.size)); window.contentView = view; return window
            }
        }
        screenCount = screens.count
        for (screen, window) in zip(screens, windows) {
            if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
            guard let view = window.contentView as? MaskView else { continue }
            view.opacity = opacity
            view.holes = regions.compactMap { rect in
                let intersection = rect.intersection(screen.frame)
                return intersection.isNull ? nil : CGRect(x: intersection.minX - screen.frame.minX, y: intersection.minY - screen.frame.minY, width: intersection.width, height: intersection.height)
            }
            view.renderMask(); window.orderFrontRegardless()
        }
    }
    private final class MaskWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private final class MaskView: NSView {
        var holes: [CGRect] = []
        var opacity = 0.48
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        let maskLayer = CAShapeLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect); wantsLayer = true
            layer?.addSublayer(maskLayer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
        override func layout() { super.layout(); renderMask() }
        func renderMask() {
            let shape = maskLayer
            var disjoint: [CGRect] = []
            for hole in holes {
                var merged = hole; var remaining = disjoint
                var again = true
                while again {
                    again = false
                    if let index = remaining.firstIndex(where: { $0.intersects(merged) }) {
                        merged = merged.union(remaining.remove(at: index)); again = true
                    }
                }
                disjoint = remaining + [merged]
            }
            let path = CGMutablePath(); path.addRect(bounds); path.addRects(disjoint)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            shape.frame = bounds; shape.fillRule = .evenOdd; shape.fillColor = NSColor.black.withAlphaComponent(opacity).cgColor; shape.path = path
            CATransaction.commit()
        }
    }
}
