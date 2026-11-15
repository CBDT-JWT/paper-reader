import SwiftUI
import PaperCore

struct AIConnectionControls: View {
    @ObservedObject var settings: AISettings
    var generating: Bool
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 5) {
                Text(settings.modelTitle).lineLimit(1).truncationMode(.middle)
                Text(settings.thinkingTitle).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Image(systemName: "chevron.down").font(Design.small).foregroundStyle(.secondary)
            }.font(Design.body).foregroundStyle(.primary).padding(.horizontal, 6).frame(height: 30)
                .contentShape(RoundedRectangle(cornerRadius: Design.radius))
        }.buttonStyle(.plain).disabled(generating)
            .help(L("模型与思考强度")).accessibilityIdentifier("ai.model")
            .popover(isPresented: $presented, arrowEdge: .bottom) { AIThinkingPopover(settings: settings) }
            .onChange(of: settings.backend) { _, _ in settings.save() }
            .onChange(of: settings.model) { _, _ in settings.save() }
            .onChange(of: generating) { _, busy in if busy { presented = false } }
            .task(id: "\(settings.backend.rawValue)|\(settings.backend.usesACP ? settings.model : "")") {
                if settings.backend.usesACP || settings.models.isEmpty { await settings.refreshModels() }
            }
    }
}

struct AIErrorBanner: View {
    @ObservedObject var ai: AIController
    @State private var configuring = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                Text(ai.error ?? "").font(Design.small).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if ai.canRetry { Button(L("重试此问题")) { ai.retry() }.accessibilityIdentifier("ai.retry") }
                Button(L("连接设置")) { configuring = true }
            }.font(Design.small)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspacePalette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Design.radius))
            .sheet(isPresented: $configuring) {
                VStack(spacing: 0) {
                    HStack { Text(L("AI 连接设置")).font(Design.title); Spacer(); Button(L("完成")) { ai.settings.save(); configuring = false } }.padding(20)
                    AISettingsView(settings: ai.settings)
                }
            }
    }
}

struct AIResponseOptions: View {
    @ObservedObject var settings: AISettings
    @State private var presented = false
    var body: some View {
        if !settings.thinkingStops.isEmpty || settings.canToggleFastMode || settings.agentOptions.contains(where: \.isGenerationOption) {
            Button { presented.toggle() } label: {
                HStack(spacing: 6) {
                    Text(L("生成选项"))
                    Text(settings.thinkingTitle).foregroundStyle(.secondary)
                    Image(systemName: "chevron.down").font(Design.small).foregroundStyle(.secondary)
                }.font(Design.body)
            }.buttonStyle(.plain)
                .popover(isPresented: $presented, arrowEdge: .bottom) { AIThinkingPopover(settings: settings) }
        }
    }
}
