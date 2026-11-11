import Foundation
import CoreGraphics
import CoreText

/// Reproducible, locally generated fixture; no third-party paper or network required.
public enum DemoPaper {
    public static func create(at url: URL, withFooters: Bool = false) throws {
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &media, nil) else { throw LibraryError.invalidPDF }
        for index in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(media)
            draw("A workspace for thoughtful research", at: CGPoint(x: 48, y: 726), size: 23, context: context)
            draw("Paper Reader  /  Technical validation fixture  /  2026", at: CGPoint(x: 48, y: 700), size: 11, context: context)
            draw(index == 0 ? "Abstract" : "\(index + 1). Reading and reasoning", at: CGPoint(x: 48, y: 658), size: 16, context: context)
            let lines = [
                "Scientific reading brings together careful attention,",
                "local evidence, and notes that remain yours.",
                "This document is generated inside Paper Reader.",
                "Select text to quote it into the linked note.",
                "Use the region tool to capture a figure or formula.",
                "Each capture keeps its page and PDF coordinates.",
                "Click its source link to return to the evidence.",
                "The original PDF is never modified by this app.",
                "Notes are ordinary Markdown files on your disk.",
                "Equations use offline KaTeX rendering.",
                "The editor supports structured, editable content.",
                "A useful tool makes the next thought easier."
            ]
            for column in 0..<2 {
                draw(column == 0 ? "1. Evidence" : "2. Understanding", at: CGPoint(x: 48 + column * 264, y: 620), size: 14, context: context)
                for (line, text) in lines.enumerated() {
                    draw(text, at: CGPoint(x: 48 + column * 264, y: 592 - line * 18), size: 10, context: context)
                }
            }
            context.setFillColor(CGColor(red: 0.88, green: 0.93, blue: 0.97, alpha: 1))
            context.fill(CGRect(x: 48, y: 210, width: 516, height: 128))
            context.setStrokeColor(CGColor(red: 0.2, green: 0.42, blue: 0.65, alpha: 1)); context.setLineWidth(2)
            context.move(to: CGPoint(x: 76, y: 230))
            for x in 0...400 {
                let y = 245.0 + 60.0 * sin(Double(x) / 100.0)
                context.addLine(to: CGPoint(x: Double(76 + x), y: y))
            }
            context.strokePath()
            draw("Figure 1. A vector curve: capture this area at 3x resolution.", at: CGPoint(x: 48, y: 188), size: 11, context: context)
            if withFooters {
                draw("Figure axis label", at: CGPoint(x: 100, y: 240), size: 8, context: context)
                draw("Research support and funding acknowledgement.", at: CGPoint(x: 48, y: 100), size: 8, context: context)
                draw("This footer belongs to the left reading column.", at: CGPoint(x: 48, y: 88), size: 8, context: context)
                draw("Copyright 2026. All rights reserved. Authorized reading fixture.", at: CGPoint(x: 48, y: 48), size: 8, context: context)
            }
            draw("\(index + 1)", at: CGPoint(x: 300, y: 32), size: 11, context: context)
            context.endPDFPage()
        }
        context.closePDF()
    }
    private static func draw(_ string: String, at point: CGPoint, size: CGFloat, context: CGContext) {
        let font = CTFontCreateWithName("Times-Roman" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = point; context.setFillColor(CGColor(gray: 0.13, alpha: 1)); CTLineDraw(line, context)
    }
}
