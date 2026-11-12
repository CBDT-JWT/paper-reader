import AppKit
import SwiftUI

/// White surfaces, cobalt bookmark and amber emphasis follow the application icon.
enum WorkspacePalette {
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("PaperReader." + name)) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let accentNS = adaptive("cobalt", light: 0x315FAD, dark: 0x91B7F5)
    static let paperNS = adaptive("paper", light: 0xFFFFFF, dark: 0x20242B)
    static let chromeNS = adaptive("chrome", light: 0xFFFFFF, dark: 0x252B35)
    static let sidebarNS = adaptive("sidebar", light: 0xFFFFFF, dark: 0x24272D)
    static let canvasNS = adaptive("canvas", light: 0xFFFFFF, dark: 0x191B20)
    static let selectionNS = adaptive("selection", light: 0xCFDCF2, dark: 0x304D7B)
    static let amberNS = adaptive("amber", light: 0xA36912, dark: 0xF2BC60)
    static let toolbarNS = adaptive("toolbar", light: 0xEDF3FC, dark: 0x273247)
    static let toolbar = Color(nsColor: toolbarNS)
    static let accent = Color(nsColor: accentNS)
    static let paper = Color(nsColor: paperNS)
    static let chrome = Color(nsColor: chromeNS)
    static let sidebar = Color(nsColor: sidebarNS)
    static let canvas = Color(nsColor: canvasNS)
    static let selection = Color(nsColor: selectionNS)
    static let amber = Color(nsColor: amberNS)
}
