import SwiftUI
import AppKit
import PaperCore

struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    var quoteID: UUID?
    var submit: () -> Void
    var dismiss: () -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        let view = AIInputTextView()
        view.isRichText = false
        view.font = .systemFont(ofSize: 14)
        view.textColor = .labelColor
        view.insertionPointColor = WorkspacePalette.accentNS
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize.height = .greatestFiniteMagnitude
        view.delegate = context.coordinator
        view.submit = submit; view.dismiss = dismiss
        scroll.documentView = view
        view.setAccessibilityLabel(L("询问论文或当前选区…"))
        view.setAccessibilityIdentifier("ai.input")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? AIInputTextView else { return }
        if !view.hasMarkedText(), view.string != text { view.string = text; view.needsDisplay = true }
        view.submit = submit; view.dismiss = dismiss
        if context.coordinator.parent.quoteID != quoteID {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        context.coordinator.parent = self
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        init(parent: ChatInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

@MainActor final class AIInputTextView: NSTextView {
    var submit: (() -> Void)?
    var dismiss: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        // Use the same AppKit layout and container origin as the caret and entered text.
        let storage = NSTextStorage(string: L("询问论文或当前选区…"), attributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor])
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: textContainer?.containerSize ?? bounds.size)
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: textContainerOrigin)
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        // A candidate-confirmation Return belongs to the input method.
        if hasMarkedText() { super.keyDown(with: event); return }
        if [36, 76].contains(event.keyCode) {
            if event.modifierFlags.contains(.shift) { insertNewline(nil) }
            else { submit?() }
            return
        }
        if event.keyCode == 53 { dismiss?(); return }
        super.keyDown(with: event)
    }
}
