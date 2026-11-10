import SwiftUI
import AppKit
import PaperCore

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: CommandShortcut
    let title: String
    func makeNSView(context: Context) -> RecorderView { let view = RecorderView(); view.setAccessibilityElement(true); view.setAccessibilityRole(.button); view.change = { shortcut = $0 }; return view }
    func updateNSView(_ view: RecorderView, context: Context) { view.shortcut = shortcut; view.setAccessibilityLabel(title); view.setAccessibilityValue(shortcut.key.isEmpty ? L("点击录制") : shortcut.display); view.change = { shortcut = $0 }; view.needsDisplay = true }
    @MainActor final class RecorderView: NSView {
        var shortcut = CommandShortcut(key: "")
        var change: ((CommandShortcut) -> Void)?
        private var recording = false
        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 118, height: 30) }
        override func mouseDown(with event: NSEvent) { _ = accessibilityPerformPress() }
        override func accessibilityPerformPress() -> Bool { recording = true; window?.makeFirstResponder(self); needsDisplay = true; return true }
        override func resignFirstResponder() -> Bool { recording = false; needsDisplay = true; return true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { guard recording else { return false }; keyDown(with: event); return true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { recording = false; needsDisplay = true; return }
            if event.keyCode == 51 || event.keyCode == 117 { change?(CommandShortcut(key: "")); recording = false; needsDisplay = true; return }
            guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return }
            let flags = event.modifierFlags
            change?(CommandShortcut(key: key, command: flags.contains(.command), option: flags.contains(.option), shift: flags.contains(.shift), control: flags.contains(.control)))
            recording = false; needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 1, dy: 1); let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            NSColor.controlBackgroundColor.setFill(); path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke(); path.lineWidth = recording ? 2 : 1; path.stroke()
            let title = recording ? L("按下快捷键…") : shortcut.key.isEmpty ? L("点击录制") : shortcut.display
            let style = NSMutableParagraphStyle(); style.alignment = .center
            (title as NSString).draw(in: rect.insetBy(dx: 5, dy: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        }
    }
}
