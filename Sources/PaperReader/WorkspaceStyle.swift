import SwiftUI

struct WorkspaceIconStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, selected: selected)
    }
    private struct Chrome: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label.font(.system(size: 14, weight: .regular))
                .frame(width: 30, height: 30)
                .foregroundStyle(selected ? WorkspacePalette.accent : WorkspacePalette.accent.opacity(0.85))
                .background(selected ? WorkspacePalette.accent.opacity(0.1) : WorkspacePalette.accent.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8)).onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        }
    }
}
