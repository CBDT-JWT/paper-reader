import AppKit
import PDFKit
import QuartzCore
import PaperCore

struct FocusFrame {
    let lineID: Int
    let page: Int
    let column: Int
    let rectangle: CGRect
    let anchor: PDFPoint
    let crossesFigure: Bool
}

/// Moves the PDF and its aperture in the same frame, including at document boundaries.
@MainActor final class FocusMotion {
    let overlay: FocusOverlay
    private var generation = UUID()
    private(set) var isAnimating = false

    init(overlay: FocusOverlay) { self.overlay = overlay }

    func cancel() {
        generation = UUID()
        isAnimating = false
        overlay.viewportRectangle = nil
        overlay.holeVisibility = 1
    }

    func restoreScrollLimits() {
        guard let scroll = overlay.pdfView?.documentView?.enclosingScrollView else { return }
        let clip = scroll.contentView
        clip.scroll(to: clip.constrainBoundsRect(clip.bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }

    func animate(to target: FocusFrame, automatic: Bool, speed: () -> Double) async throws {
        guard let pdf = overlay.pdfView, let page = pdf.document?.page(at: target.page),
              let scroll = pdf.documentView?.enclosingScrollView else { return }
        let token = UUID()
        generation = token
        isAnimating = true
        defer {
            if generation == token {
                isAnimating = false
                overlay.viewportRectangle = nil
                overlay.holeVisibility = 1
            }
        }
        let clip = scroll.contentView
        let startOrigin = clip.bounds.origin
        let start = overlay.highlights?.1.first ?? target.rectangle
        let startReadingAnchor = overlay.readingAnchor?.cgPoint ?? target.anchor.cgPoint
        let startLineID = overlay.readingLineID
        let crossing = overlay.highlights?.0 != target.page || overlay.highlightColumn != target.column || target.crossesFigure
        let startVisible = overlay.screenRectangleInPDFView ?? pdf.convert(target.rectangle, from: page)
        let viewport = pdf.convert(clip.bounds, from: clip)
        let endVisible = CGRect(x: viewport.midX - pdf.convert(target.rectangle, from: page).width / 2,
                                y: viewport.midY - pdf.convert(target.rectangle, from: page).height / 2,
                                width: pdf.convert(target.rectangle, from: page).width,
                                height: pdf.convert(target.rectangle, from: page).height)
        let initialPosition = clip.convert(startVisible, from: pdf)
        let initialAnchor = CGPoint(x: initialPosition.midX - startOrigin.x, y: initialPosition.midY - startOrigin.y)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var progress = 0.0
        var previousTime = CACurrentMediaTime()
        let startTime = previousTime
        while true {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            let now = CACurrentMediaTime()
            let elapsed = min(now - previousTime, 0.1)
            previousTime = now
            if reduceMotion && (!automatic || crossing) { progress = 1 }
            else if automatic && !crossing { progress = min(1, progress + elapsed * min(240, max(5, speed())) / 60) }
            else { progress = min(1, progress + elapsed / (crossing ? 0.48 : 0.24)) }
            let eased = automatic && !crossing ? progress : progress * progress * (3 - 2 * progress)
            if crossing {
                // Fade while the page pans between columns, keeping the frame at the viewport
                // anchor. No aperture travels diagonally through unrelated text or the gutter.
                overlay.viewportRectangle = interpolate(startVisible, endVisible, eased)
                overlay.holeVisibility = max(0, 1 - progress / 0.2, (progress - 0.8) / 0.2)
                let currentDestination = clip.convert(pdf.convert(target.rectangle, from: page), from: pdf)
                let currentGoal = CGPoint(x: currentDestination.midX - clip.bounds.width / 2,
                                          y: currentDestination.midY - clip.bounds.height / 2)
                clip.scroll(to: interpolate(startOrigin, currentGoal, eased))
            } else {
                let rectangle = interpolate(start, target.rectangle, eased)
                overlay.highlights = (target.page, [rectangle])
                overlay.readingAnchor = PDFPoint(interpolate(startReadingAnchor, target.anchor.cgPoint, eased))
                overlay.readingLineID = progress < 0.5 ? startLineID : target.lineID
                let position = clip.convert(pdf.convert(rectangle, from: page), from: pdf)
                let approach = progress >= 1 ? 1 : min(1, (now - startTime) / 0.24)
                let anchor = interpolate(initialAnchor, CGPoint(x: clip.bounds.width / 2, y: clip.bounds.height / 2), approach * approach * (3 - 2 * approach))
                clip.scroll(to: CGPoint(x: position.midX - anchor.x, y: position.midY - anchor.y))
            }
            scroll.reflectScrolledClipView(clip)
            overlay.onGeometryChanged?()
            if progress >= 1 { break }
            try await Task.sleep(for: .milliseconds(16))
        }
        overlay.highlights = (target.page, [target.rectangle])
        overlay.highlightColumn = target.column
        overlay.readingAnchor = target.anchor
        overlay.readingLineID = target.lineID
        overlay.viewportRectangle = nil
        overlay.holeVisibility = 1
        // PDFKit can adjust its tiled document's geometry after a large column/page pan.
        // Keep centring while that layout settles instead of retaining a stale origin.
        if crossing { try await Task.sleep(for: .milliseconds(16)) }
        for _ in 0..<3 {
            try Task.checkCancellation()
            let rectangle = clip.convert(pdf.convert(target.rectangle, from: page), from: pdf)
            if hypot(rectangle.midX - clip.bounds.midX, rectangle.midY - clip.bounds.midY) < 0.5 { break }
            clip.scroll(to: CGPoint(x: rectangle.midX - clip.bounds.width / 2, y: rectangle.midY - clip.bounds.height / 2))
            scroll.reflectScrolledClipView(clip)
            overlay.onGeometryChanged?()
            try await Task.sleep(for: .milliseconds(16))
        }
        overlay.onGeometryChanged?()
    }
}

private func interpolate(_ start: CGPoint, _ end: CGPoint, _ fraction: Double) -> CGPoint {
    CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
}

private func interpolate(_ start: CGRect, _ end: CGRect, _ fraction: Double) -> CGRect {
    CGRect(x: start.minX + (end.minX - start.minX) * fraction,
           y: start.minY + (end.minY - start.minY) * fraction,
           width: start.width + (end.width - start.width) * fraction,
           height: start.height + (end.height - start.height) * fraction)
}
