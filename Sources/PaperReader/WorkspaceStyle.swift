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
        var body: some View {
            configuration.label.font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8)).onHover { hovering = $0 }
        }
    }
}
