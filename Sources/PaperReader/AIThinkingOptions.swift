import Foundation
import PaperCore

struct AIThinkingStop: Identifiable {
    let value: String
    let title: String
    var id: String { value }
}

@MainActor extension AISettings {
    var reasoningOption: AgentSessionOption? {
        let options = agentOptions.filter(\.isReasoningOption)
        return options.first { $0.choices.contains { ["low", "medium", "high", "xhigh", "max"].contains($0.value.lowercased()) } } ?? options.first
    }
    var speedOption: AgentSessionOption? { agentOptions.first { $0.isSpeedOption } }
    var thinkingStops: [AIThinkingStop] {
        if let option = reasoningOption {
            let choices = option.choices.filter { !["default", "auto", "adaptive"].contains($0.value.lowercased()) }
            return AIEffort.ordered(choices.map { .init(value: $0.value, title: AIEffort.title($0.value, fallback: $0.name)) })
        }
        return AIEffort.ordered(effortLevels.map { .init(value: $0, title: AIEffort.title($0)) })
    }
    var effectiveThinkingValue: String {
        if let option = reasoningOption { return agentSelections[option.id] ?? option.currentValue }
        return effort.isEmpty ? codexDefaultEfforts[model] ?? "" : effort
    }
    var thinkingIndex: Int? { thinkingStops.firstIndex { $0.value == effectiveThinkingValue } }
    var thinkingTitle: String {
        thinkingStops.first { $0.value == effectiveThinkingValue }?.title ?? AIEffort.title(effectiveThinkingValue)
    }
    var maximumThinking: Bool { thinkingStops.count > 1 && thinkingIndex == thinkingStops.count - 1 }
    var modelTitle: String {
        if !model.isEmpty { return model }
        if backend == .codex { return codexDefaultModel.isEmpty ? "Codex" : codexDefaultModel }
        return backend.usesCLI ? backend.title : L("选择模型")
    }
    func selectThinking(_ index: Int) {
        guard thinkingStops.indices.contains(index) else { return }
        let value = thinkingStops[index].value
        if let option = reasoningOption {
            if agentSelections[option.id] != value { agentSelections[option.id] = value }
        } else if effort != value { effort = value }
    }
    func resetGenerationOptions() {
        effort = ""; fastMode = false
        for option in agentOptions where option.isGenerationOption { agentSelections.removeValue(forKey: option.id) }
    }
    var speedValues: (enabled: String, disabled: String)? {
        guard let option = speedOption,
              let enabled = option.choices.first(where: { ["fast", "on", "true", "enabled"].contains($0.value.lowercased()) }),
              let disabled = option.choices.first(where: { ["normal", "standard", "off", "false", "disabled"].contains($0.value.lowercased()) }) else { return nil }
        return (enabled.value, disabled.value)
    }
    var canToggleFastMode: Bool { supportsFastMode || speedValues != nil }
    var fastModeActive: Bool {
        if supportsFastMode { return fastMode }
        guard let option = speedOption, let values = speedValues else { return false }
        return (agentSelections[option.id] ?? option.currentValue) == values.enabled
    }
    func toggleFastMode() {
        if supportsFastMode { fastMode.toggle() }
        else if let option = speedOption, let values = speedValues { agentSelections[option.id] = fastModeActive ? values.disabled : values.enabled }
    }
}

extension AgentSessionOption {
    var isSpeedOption: Bool { isGenerationOption && ["fast", "speed"].contains { (id + " " + category).lowercased().contains($0) } }
    var isReasoningOption: Bool { isGenerationOption && !isSpeedOption }
}

enum AIEffort {
    static func ordered(_ stops: [AIThinkingStop]) -> [AIThinkingStop] {
        let values = ["none", "off", "disabled", "false", "minimal", "low", "medium", "high", "xhigh", "max"]
        let ranks = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element, $0.offset) })
        guard stops.allSatisfy({ ranks[$0.value.lowercased()] != nil }) else { return stops }
        return stops.sorted { (ranks[$0.value.lowercased()] ?? 0) < (ranks[$1.value.lowercased()] ?? 0) }
    }
    static func title(_ value: String, fallback: String? = nil) -> String {
        switch value.lowercased() {
        case "", "auto", "default", "adaptive": L("默认")
        case "none", "off", "disabled", "false": L("关闭思考")
        case "minimal": L("最低")
        case "low": L("低")
        case "medium": L("中等")
        case "high": L("高")
        case "xhigh": L("超高")
        case "max": L("最高")
        default: fallback ?? value
        }
    }
}
