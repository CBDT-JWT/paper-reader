import AppKit
import WebKit
import PaperCore

/// Reproducible screenshots of the real native workbench, using only our generated paper.
/// Invoked explicitly for release artwork, always with an isolated disposable library.
@MainActor enum WebsiteDemo {
    static func prepare(model: AppModel) async {
        guard ProcessInfo.processInfo.environment["PAPER_READER_LIBRARY"] != nil else { return }
        do {
            for _ in 0..<100 {
                if model.editor.ready { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard model.editor.ready else { return }
            await model.openDemo()
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) else { return }
            window.setContentSize(NSSize(width: 1440, height: 872))
            window.center(); window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .seconds(2))
            guard let destination = ProcessInfo.processInfo.environment["PAPER_READER_WEBSITE_CAPTURE_DIR"] else { return }
            let folder = URL(fileURLWithPath: destination, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: view.bounds.size); image.addRepresentation(bitmap)
            let webImage: NSImage = try await withCheckedThrowingContinuation { continuation in
                model.editor.webView.takeSnapshot(with: nil) { image, error in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                }
            }
            func imageRect(_ rect: NSRect) -> NSRect {
                view.isFlipped ? NSRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height) : rect
            }
            image.lockFocus()
            // PDFKit and WebKit render in separate compositing surfaces. Use their real rendering
            // APIs at the frames measured from the live native window, rather than mock up UI.
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                let pdf = model.reader.view
                let viewport = imageRect(view.convert(pdf.bounds, from: pdf))
                context.clip(to: viewport)
                context.setFillColor(NSColor.controlBackgroundColor.cgColor); context.fill(viewport)
                for page in pdf.visiblePages {
                    let bounds = page.bounds(for: pdf.displayBox)
                    let destination = imageRect(view.convert(pdf.convert(bounds, from: page), from: pdf))
                    context.saveGState()
                    context.translateBy(x: destination.minX, y: destination.minY)
                    context.scaleBy(x: destination.width / bounds.width, y: destination.height / bounds.height)
                    page.draw(with: pdf.displayBox, to: context)
                    context.restoreGState()
                }
                context.restoreGState()
            }
            webImage.draw(in: imageRect(view.convert(model.editor.webView.bounds, from: model.editor.webView)))
            image.unlockFocus()
            // Capture the workspace split view; the standard title bar is outside this view.
            func findSplit(_ parent: NSView) -> NSSplitView? {
                if let split = parent as? NSSplitView, split.isVertical { return split }
                return parent.subviews.compactMap { findSplit($0) }.first
            }
            let crop = findSplit(view).map { imageRect(view.convert($0.bounds, from: $0)) } ?? view.bounds
            let workspace = NSImage(size: crop.size)
            workspace.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: crop.size), from: crop, operation: .copy, fraction: 1)
            workspace.unlockFocus()
            if let data = workspace.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("workspace.png"), options: .atomic)
                print("WEBSITE CAPTURE: \(folder.path)/workspace.png")
            }
        } catch { print("WEBSITE CAPTURE FAILED: \(error)") }
    }
}
