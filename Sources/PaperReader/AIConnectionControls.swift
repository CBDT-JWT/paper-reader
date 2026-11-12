import SwiftUI
import PaperCore

struct AIConnectionControls: View {
    @ObservedObject var settings: AISettings
    var generating: Bool
    @State private var configuring = false
    @State private var customModel = ""
    @State private var editingModel = false
    @FocusState private var modelFieldFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(AIBackend.allCases) { backend in
                        Button { settings.backend = backend; settings.save() } label: {
                            if settings.backend == backend { Label(backend.title, systemImage: "checkmark") }
                            else { Text(backend.title) }
                        }
                    }
                } label: { Text(settings.backend == .codex ? "Codex" : settings.backend.title).lineLimit(1) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityIdentifier("ai.provider")
                Menu {
                    if settings.backend == .codex { Button(L("使用默认模型")) { settings.model = ""; settings.save() } }
                    ForEach(settings.models, id: \.self) { name in
                        Button { settings.model = name; settings.save() } label: {
                            if settings.model == name { Label(name, systemImage: "checkmark") }
                            else { Text(name) }
                        }
                    }
                    Divider()
                    Button(L("读取模型")) { Task { await settings.refreshModels() } }.disabled(settings.refreshing)
                    Button(L("自定义模型…")) { customModel = settings.model; editingModel = true }
                } label: {
                    Text(settings.model.isEmpty ? (settings.backend == .codex ? L("默认模型") : L("选择模型")) : settings.model)
                        .lineLimit(1).truncationMode(.middle)
                }.menuStyle(.borderlessButton).accessibilityIdentifier("ai.model")
                if settings.refreshing { ProgressView().controlSize(.small) }
                Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(WorkspaceIconStyle()).help(L("AI 连接设置")).accessibilityIdentifier("ai.settings")
            }
            if editingModel {
                HStack(spacing: 6) {
                    TextField(L("模型名称"), text: $customModel).textFieldStyle(.roundedBorder)
                        .font(Design.body).focused($modelFieldFocused).onAppear { modelFieldFocused = true }
                        .onSubmit { applyModel() }.onExitCommand { editingModel = false }
                        .accessibilityIdentifier("ai.customModel")
                    Button { applyModel() } label: { Image(systemName: "checkmark") }.buttonStyle(WorkspaceIconStyle()).help(L("完成")).accessibilityLabel(L("完成"))
                    Button { editingModel = false } label: { Image(systemName: "xmark") }.buttonStyle(WorkspaceIconStyle()).help(L("取消")).accessibilityLabel(L("取消"))
                }
            }
        }.font(Design.small).disabled(generating)
            .onChange(of: settings.backend) { _, _ in editingModel = false }
            .task(id: settings.backend) { if settings.models.isEmpty { await settings.refreshModels() } }
            .sheet(isPresented: $configuring) {
                VStack(spacing: 0) {
                    HStack { Text(L("AI 连接设置")).font(Design.title); Spacer(); Button(L("完成")) { settings.save(); configuring = false } }.padding(20)
                    AISettingsView(settings: settings)
                }
            }
    }
    private func applyModel() { settings.model = customModel.trimmingCharacters(in: .whitespacesAndNewlines); settings.save(); editingModel = false }
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
