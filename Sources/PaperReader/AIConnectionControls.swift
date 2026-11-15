import SwiftUI
import PaperCore

/// One compact model/effort selector shared by the floating composer and conversation drawer.
struct AIConnectionControls: View {
    @ObservedObject var settings: AISettings
    var generating: Bool
    @State private var customModel = ""
    @State private var editingModel = false
    var body: some View {
        Menu {
            Picker(L("服务提供方"), selection: $settings.backend) {
                ForEach(AIBackend.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("ai.provider")
            Divider()
            if settings.backend.usesCLI { Button(L("使用默认模型")) { settings.model = "" } }
            ForEach(settings.models, id: \.self) { name in
                Button { settings.model = name } label: {
                    if settings.model == name { Label(name, systemImage: "checkmark") }
                    else { Text(name) }
                }
            }
            Button(L("自定义模型…")) { customModel = settings.model; editingModel = true }
            Button(L("读取模型")) { Task { await settings.refreshModels() } }.disabled(settings.refreshing)
            Divider()
            AIResponseMenuContent(settings: settings)
        } label: {
            HStack(spacing: 5) {
                Text(settings.model.isEmpty ? (settings.backend == .codex ? "Codex" : settings.backend.title) : settings.model)
                    .foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                if !settings.effortLevels.isEmpty {
                    Text(AIEffort.title(settings.effort)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                } else if let option = settings.agentOptions.first(where: \.isGenerationOption) {
                    Text(option.choices.first { $0.value == (settings.agentSelections[option.id] ?? option.currentValue) }?.name ?? option.name)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(Design.small).foregroundStyle(.secondary)
            }.font(Design.body).padding(.horizontal, 6).frame(height: 30)
                .contentShape(RoundedRectangle(cornerRadius: Design.radius))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            .onChange(of: settings.backend) { _, _ in settings.save() }
            .onChange(of: settings.model) { _, _ in settings.save() }
            .disabled(generating).help(L("模型与思考强度")).accessibilityIdentifier("ai.model")
            .task(id: "\(settings.backend.rawValue)|\(settings.backend.usesACP ? settings.model : "")") {
                if settings.backend.usesACP || settings.models.isEmpty { await settings.refreshModels() }
            }
            .alert(L("自定义模型…"), isPresented: $editingModel) {
                TextField(L("模型名称"), text: $customModel)
                Button(L("完成")) { settings.model = customModel.trimmingCharacters(in: .whitespacesAndNewlines); settings.save() }
                Button(L("取消"), role: .cancel) { }
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

struct AIResponseMenuContent: View {
    @ObservedObject var settings: AISettings
    var body: some View {
        if !settings.effortLevels.isEmpty {
            Picker(L("思考强度"), selection: $settings.effort) {
                Text(L("使用默认强度")).tag("")
                ForEach(settings.effortLevels, id: \.self) { Text(AIEffort.title($0)).tag($0) }
            }.accessibilityIdentifier("ai.effort")
        }
        ForEach(settings.agentOptions.filter(\.isGenerationOption)) { option in
            Picker(option.name, selection: Binding(get: { settings.agentSelections[option.id] ?? "" }, set: {
                if $0.isEmpty { settings.agentSelections.removeValue(forKey: option.id) }
                else { settings.agentSelections[option.id] = $0 }
            })) {
                Text(L("使用默认设置")).tag("")
                ForEach(option.choices) { Text($0.name).tag($0.value) }
            }
        }
        if settings.supportsFastMode { Toggle(L("快速模式"), isOn: $settings.fastMode) }
    }
}

struct AIResponseOptions: View {
    @ObservedObject var settings: AISettings
    var body: some View {
        if !settings.effortLevels.isEmpty || settings.agentOptions.contains(where: \.isGenerationOption) || settings.supportsFastMode {
            Menu { AIResponseMenuContent(settings: settings) } label: {
                HStack(spacing: 6) {
                    Text(settings.effortLevels.isEmpty ? L("生成选项") : L("思考强度"))
                    if !settings.effortLevels.isEmpty { Text(AIEffort.title(settings.effort)).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.down").font(Design.small).foregroundStyle(.secondary)
                }.font(Design.body)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
    }
}

private enum AIEffort {
    static func title(_ level: String) -> String {
        switch level {
        case "": L("默认")
        case "none": L("关闭思考")
        case "minimal": L("最低")
        case "low": L("低")
        case "medium": L("中等")
        case "high": L("高")
        case "xhigh": L("超高")
        case "max": L("最高")
        default: level
        }
    }
}
