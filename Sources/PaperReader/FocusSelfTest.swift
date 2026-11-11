import AppKit
import PDFKit
import PaperCore

/// Exercises real PDFKit scrolling and layer pixels without requiring foreground activation.
@MainActor enum FocusSelfTest {
    /// Optional, read-only regression against an external PDF. Fast repeated arrows also
    /// exercise cancellation of in-flight camera motion through overlapping font boxes.
    static func walkDocument(reader: PDFReaderController, url: URL) async throws -> [String] {
        let original = try Data(contentsOf: url)
        let layouts = try await Task.detached {
            guard let document = PDFDocument(url: url) else { throw LibraryError.invalidPDF }
            return try (0..<document.pageCount).map { try PDFServices.layout(url: url, page: $0) }
        }.value
        try await reader.load(url: url, page: 0, scale: 0)
        let focus = reader.focus
        let speed = focus.linesPerMinute
        let pauseOnDeactivate = focus.pausesWhenInactive
        focus.pausesWhenInactive = false
        defer { focus.enabled = false; focus.linesPerMinute = speed; focus.pausesWhenInactive = pauseOnDeactivate }
        focus.enabled = true
        var checks: [String] = []
        func wait(_ message: String, _ condition: () -> Bool) async throws {
            for _ in 0..<500 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(30))
            }
            throw IntegrationSelfTest.Failure(message: message + "; enabled=\(focus.enabled), keyboard=\(focus.keyboard), automatic=\(focus.automatic), active=\(NSApp.isActive), line=\(String(describing: focus.currentLineID)), displayed=\(String(describing: focus.overlay.readingLineID)), column=\(focus.overlay.highlightColumn), pages=\(reader.pageCount)")
        }
        for (page, layout) in layouts.enumerated() {
            let order = layout.readingOrder()
            guard let first = order.first else { continue }
            focus.keyboard = false
            focus.togglePin(at: .init(x: first.rect.cgRect.midX, y: first.rect.cgRect.midY), page: page)
            try await wait("External PDF page \(page + 1) initial anchor") {
                !focus.isMoving && focus.overlay.highlights?.0 == page && focus.currentLineID == first.id
            }
            for line in order.dropFirst() {
                focus.step(1)
                try await wait("External PDF page \(page + 1) stalled before line \(line.id)") { focus.currentLineID == line.id }
            }
            try await wait("External PDF page \(page + 1) final camera") { !focus.isMoving && centerError(reader) < 2 }
            checks.append("External PDF page \(page + 1): repeated arrows visit all \(order.count) extracted lines without repeating an overlapping footer anchor")
            for region in layout.figureRegions {
                let point = PDFPoint(x: region.cgRect.midX, y: region.cgRect.midY)
                focus.keyboard = false
                focus.overlay.onMove?(point, page)
                guard focus.overlay.highlights == nil else { throw IntegrationSelfTest.Failure(message: "External PDF figure still receives a mouse aperture") }
                focus.togglePin(at: point, page: page)
                guard !focus.keyboard else { throw IntegrationSelfTest.Failure(message: "Clicking a figure pinned an empty reading anchor") }
            }
            if !layout.figureRegions.isEmpty {
                checks.append("External PDF page \(page + 1): hovering or clicking each of \(layout.figureRegions.count) graphic/caption regions leaves it dark and keeps mouse-follow mode available")
            }
            guard let handoff = order.indices.dropLast().last(where: { order[$0].column == 0 && order[$0 + 1].column == 1 }) else { continue }
            let start = max(0, handoff - 10)
            // A mouse can land on another overlapping line. Start on the actual hit and
            // require automatic navigation to pass the entire remaining footer sequence.
            let line = order[start]
            focus.keyboard = false
            focus.togglePin(at: .init(x: line.rect.cgRect.midX, y: line.rect.cgRect.midY), page: page)
            try await wait("External PDF page \(page + 1) automatic start") { !focus.isMoving && focus.overlay.highlights?.0 == page }
            focus.linesPerMinute = 120
            focus.automatic = true
            try await wait("External PDF page \(page + 1) automatic footer handoff stalled") {
                focus.overlay.highlights?.0 == page && focus.overlay.highlightColumn == 1 && focus.overlay.readingLineID == order[handoff + 1].id
            }
            focus.automatic = false
            try await wait("External PDF page \(page + 1) reverse handoff start") { !focus.isMoving }
            focus.step(-1)
            try await wait("External PDF page \(page + 1) reverse footer handoff stalled") {
                !focus.isMoving && focus.overlay.highlightColumn == 0 && focus.currentLineID == order[handoff].id && centerError(reader) < 2
            }
            checks.append("External PDF page \(page + 1): automatic playback crosses the footer into the right column, and Up returns to the left-column bottom")
        }
        guard try Data(contentsOf: url) == original else { throw IntegrationSelfTest.Failure(message: "External focus validation changed the original PDF") }
        checks.append("External focus regression preserves the source PDF bytes")
        return checks
    }

    static func run(reader: PDFReaderController, layout: ReadingLayout, output: URL) async throws -> [String] {
        var checks: [String] = []
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw IntegrationSelfTest.Failure(message: message) }
            checks.append(message)
        }
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<150 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(30))
            }
            let clip = reader.view.documentView?.enclosingScrollView?.contentView
            let projected = focus.overlay.highlights.flatMap { entry in reader.view.document?.page(at: entry.0).map { page in clip?.convert(reader.view.convert(entry.1[0], from: page), from: reader.view) } }
            throw IntegrationSelfTest.Failure(message: "Timed out waiting for smooth focus motion after \(checks.last ?? "layout"). Centre error=\(centerError(reader)), moving=\(focus.isMoving), keyboard=\(focus.keyboard), column=\(focus.overlay.highlightColumn), clip=\(String(describing: clip?.bounds)), projected=\(String(describing: projected)), frame=\(String(describing: focus.overlay.highlights))")
        }
        let focus = reader.focus
        let savedSpeed = focus.linesPerMinute
        let pauseOnDeactivate = focus.pausesWhenInactive
        focus.pausesWhenInactive = false
        defer { focus.enabled = false; focus.keyboard = false; focus.linesPerMinute = savedSpeed; focus.pausesWhenInactive = pauseOnDeactivate }
        reader.goToPage(0)
        focus.enabled = true
        try await wait { focus.detectedColumns == 2 }
        let order = layout.readingOrder()
        guard let handoff = order.indices.dropLast().first(where: { order[$0].column == 0 && order[$0 + 1].column == 1 }) else {
            throw IntegrationSelfTest.Failure(message: "Missing real two-column fixture handoff")
        }
        let left = order[handoff], right = order[handoff + 1]
        focus.togglePin(at: PDFPoint(x: left.rect.cgRect.midX, y: left.rect.cgRect.midY), page: 0)
        try await wait { !focus.isMoving && centerError(reader) < 2 && focus.overlay.highlights?.1.first?.contains(left.rect.cgRect) == true }
        try check(focus.overlay.highlights?.1.count == 1, "Context lines and their whitespace share one rectangular aperture")
        let clip = reader.view.documentView?.enclosingScrollView?.contentView
        var cameraPositions = [clip?.bounds.origin ?? .zero]
        focus.step(1)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            var centred = true
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(40))
                centred = centred && centerError(reader) < 2
                cameraPositions.append(clip?.bounds.origin ?? .zero)
            }
            try check(centred, "The visible frame stays centred throughout a live column transition")
            let travelled = zip(cameraPositions, cameraPositions.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
            let total = travelled.reduce(0, +)
            try check(total > 1 && (travelled.max() ?? 0) < total * 0.5,
                      "The PDF camera progresses over multiple intermediate positions during column handoff")
        }
        try await wait { !focus.isMoving && focus.overlay.highlightColumn == 1 && centerError(reader) < 2 }
        try check(focus.overlay.highlights?.1.first?.contains(right.rect.cgRect) == true,
                  "Down at the actual left-column bottom reaches the right-column top")
        focus.step(-1)
        try await wait { !focus.isMoving && focus.overlay.highlightColumn == 0 && centerError(reader) < 2 }
        try check(focus.overlay.highlights?.1.first?.contains(left.rect.cgRect) == true,
                  "Up at the right-column top returns to the left-column bottom")
        focus.linesPerMinute = 120
        focus.automatic = true
        try await wait { focus.overlay.highlightColumn == 1 && focus.automatic && centerError(reader) < 2 }
        try check(centerError(reader) < 2, "Automatic column handoff finishes with the focus rectangle centred")
        focus.step(1)
        try await Task.sleep(for: .milliseconds(60))
        try await wait { !focus.isMoving && centerError(reader) < 2 }
        try check(!focus.automatic && focus.keyboard, "Arrow input pauses automatic playback and retains manual control")
        let pinned = focus.overlay.highlights?.1
        focus.overlay.onMove?(PDFPoint(x: 70, y: 595), 0)
        try check(focus.overlay.highlights?.1 == pinned, "Mouse movement leaves a manually pinned rectangle fixed")
        focus.linesPerMinute = 10
        focus.automatic = true
        try await Task.sleep(for: .milliseconds(500))
        let slowStart = focus.overlay.highlights?.1.first?.midY ?? 0
        try await Task.sleep(for: .milliseconds(180))
        let slowDistance = abs((focus.overlay.highlights?.1.first?.midY ?? 0) - slowStart)
        focus.linesPerMinute = 120
        let fastStart = focus.overlay.highlights?.1.first?.midY ?? 0
        try await Task.sleep(for: .milliseconds(180))
        let fastDistance = abs((focus.overlay.highlights?.1.first?.midY ?? 0) - fastStart)
        try check(slowDistance > 0.05 && fastDistance > slowDistance * 2,
                  "Changing playback speed changes the real PDF aperture velocity during playback")
        focus.automatic = false
        focus.keyboard = false
        let first = try unwrap(order.first)
        focus.togglePin(at: PDFPoint(x: first.rect.cgRect.midX, y: first.rect.cgRect.midY), page: 0)
        try await wait { !focus.isMoving && centerError(reader) < 2 }
        try check(centerError(reader) < 2, "The first-page heading can be centred beyond the ordinary top scroll limit")
        focus.keyboard = false
        let last = try unwrap(order.last)
        focus.togglePin(at: PDFPoint(x: last.rect.cgRect.midX, y: last.rect.cgRect.midY), page: reader.pageCount - 1)
        try await wait { !focus.isMoving && focus.overlay.highlights?.0 == reader.pageCount - 1 && centerError(reader) < 2 }
        try check(centerError(reader) < 2, "The final-page line remains centred beyond the ordinary bottom scroll limit")
        focus.automatic = true
        try await wait { !focus.automatic }
        try check(!focus.isMoving, "Automatic reading stops at the document end")
        focus.keyboard = false
        focus.togglePin(at: PDFPoint(x: last.rect.cgRect.midX, y: last.rect.cgRect.midY), page: 0)
        focus.step(1)
        try await wait { !focus.isMoving && focus.overlay.highlights?.0 == 1 && centerError(reader) < 2 }
        checks.append("A page handoff loads the cached adjacent layout and centres its first line")
        focus.automatic = true
        focus.pausesWhenInactive = true
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        try check(!focus.automatic, "Application deactivation notification pauses automatic playback")
        focus.pausesWhenInactive = false
        focus.keyboard = false
        focus.manualColumn = 0
        let manualOrder = layout.readingOrder(manualColumn: 0, manualCount: 2)
        let manualLast = try unwrap(manualOrder.last)
        focus.togglePin(at: PDFPoint(x: manualLast.rect.cgRect.midX, y: manualLast.rect.cgRect.midY), page: 0)
        try await wait { !focus.isMoving && focus.overlay.highlights?.0 == 0 && centerError(reader) < 2 }
        focus.step(1)
        try await wait { !focus.isMoving && focus.manualColumn == 1 && centerError(reader) < 2 }
        try check(focus.overlay.highlights?.0 == 0, "Manual column calibration also advances from left bottom to right top on the same page")
        focus.manualColumn = -1
        focus.enabled = false

        let mask = FocusMaskView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        mask.holes = [CGRect(x: 100, y: 60, width: 120, height: 60)]
        mask.feather = 16
        mask.renderMask()
        let image = try snapshot(mask)
        guard let core = image.colorAt(x: 120, y: 90)?.alphaComponent,
              let feather = image.colorAt(x: 108, y: 90)?.alphaComponent,
              let outside = image.colorAt(x: 70, y: 90)?.alphaComponent else {
            throw IntegrationSelfTest.Failure(message: "Cannot sample the rendered focus mask")
        }
        try check(core < 0.02 && feather > core + 0.05 && outside > feather + 0.05,
                  "Actual Core Animation pixels have a clear core, soft edge and darker exterior")
        try image.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("focus-soft-mask.png"))
        let preview = try snapshot(mask, whiteBackground: true, paper: reader.view.document?.page(at: 0))
        try preview.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("focus-light-preview.png"))
        let corners: [(Int, Int)] = [(108, 68), (211, 68), (108, 111), (211, 111)]
        let alphas = corners.compactMap { image.colorAt(x: $0.0, y: $0.1)?.alphaComponent }
        try check(alphas.count == 4 && (alphas.max() ?? 1) - (alphas.min() ?? 0) < 0.03,
                  "All four spotlight corners have continuous symmetric penumbra pixels")
        let boundary = image.colorAt(x: 100, y: 90)?.alphaComponent ?? 0
        try check(abs(boundary - outside) < 0.02, "The aperture edge matches the exterior dimming with no lighter seam")
        for offset in [0.125, 0.25, 0.5, 0.75] {
            mask.holes = [CGRect(x: 100 + offset, y: 60 + offset, width: 120, height: 60)]
            mask.renderMask()
            let moving = try snapshot(mask)
            try check(abs((moving.colorAt(x: 100, y: 90)?.alphaComponent ?? 0) - outside) < 0.02,
                      "A fractional moving edge at \(offset) points has no bright antialiasing seam")
        }
        mask.holes = [CGRect(x: 100, y: 60, width: 120, height: 60)]
        mask.holeVisibility = 0
        mask.renderMask()
        let faded = try snapshot(mask)
        try check(abs((faded.colorAt(x: 120, y: 90)?.alphaComponent ?? 0) - outside) < 0.03,
                  "Column-transition fading closes the aperture without changing the exterior dimming")
        return checks
    }

    private static func centerError(_ reader: PDFReaderController) -> Double {
        guard let rectangle = reader.focus.overlay.screenRectangleInPDFView,
              let clip = reader.view.documentView?.enclosingScrollView?.contentView else { return .infinity }
        let visible = clip.convert(rectangle, from: reader.view)
        return hypot(visible.midX - clip.bounds.midX, visible.midY - clip.bounds.midY)
    }

    private static func snapshot(_ view: NSView, whiteBackground: Bool = false, paper: PDFPage? = nil) throws -> NSBitmapImageRep {
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = CGContext(data: image.bitmapData, width: 320, height: 180, bitsPerComponent: 8,
                                      bytesPerRow: image.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw IntegrationSelfTest.Failure(message: "Cannot allocate focus mask image")
        }
        if whiteBackground {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            if let paper {
                context.saveGState()
                context.translateBy(x: 160, y: 90)
                context.scaleBy(x: 0.5, y: 0.5)
                context.translateBy(x: -170, y: -560)
                paper.draw(with: .cropBox, to: context)
                context.restoreGState()
            }
        }
        view.layer?.render(in: context)
        return image
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw IntegrationSelfTest.Failure(message: "Missing focus fixture line") }
        return value
    }
}
