import SwiftUI
import PaperCore

struct AIThinkingPopover: View {
    @ObservedObject var settings: AISettings
    @State private var choosingModel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if choosingModel {
                AIModelPicker(settings: settings, back: { choosingModel = false })
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Group {
                            if settings.canToggleFastMode {
                                Button { settings.toggleFastMode() } label: {
                                    Image(systemName: settings.fastModeActive ? "bolt.fill" : "bolt")
                                        .foregroundStyle(settings.fastModeActive ? WorkspacePalette.accent : Color.secondary)
                                }.buttonStyle(WorkspaceIconStyle(selected: settings.fastModeActive))
                                    .help(L("快速模式")).accessibilityLabel(L("快速模式"))
                                    .accessibilityValue(settings.fastModeActive ? L("已开启") : L("已关闭"))
                                    .accessibilityIdentifier("ai.fastMode")
                            } else { Color.clear.frame(width: 30, height: 30) }
                        }
                        Text(settings.thinkingTitle).font(Design.body).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(settings.thinkingIndex == nil ? Color.secondary : WorkspacePalette.accent)
                            .contentTransition(.opacity)
                            .overlay {
                                RainbowMetalFill().mask(Text(settings.thinkingTitle).font(Design.body).fontWeight(.semibold).lineLimit(1))
                                    .opacity(settings.maximumThinking ? 1 : 0)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: settings.maximumThinking)
                            }.frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: settings.thinkingTitle)
                        Button { settings.resetGenerationOptions() } label: { Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary) }
                            .buttonStyle(WorkspaceIconStyle()).help(L("恢复默认生成设置")).accessibilityLabel(L("恢复默认生成设置"))
                            .accessibilityIdentifier("ai.options.reset")
                    }
                    Button { choosingModel = true } label: {
                        HStack(spacing: 4) {
                            Text(settings.modelTitle).lineLimit(1).truncationMode(.middle)
                            if settings.refreshing { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "chevron.right") }
                        }.font(Design.small).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 18)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L("选择模型与提供方")).accessibilityIdentifier("ai.models.open")
                    if !settings.thinkingStops.isEmpty { AIEffortBar(settings: settings).padding(.top, 4) }
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).frame(width: 268).background(WorkspacePalette.paper)
            .task { if settings.models.isEmpty { await settings.refreshModels() } }
    }
}

private struct AIEffortBar: View {
    @ObservedObject var settings: AISettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var dragFraction: CGFloat?
    @State private var usingPointer = false
    var body: some View {
        GeometryReader { geometry in
            let radius: CGFloat = 14
            let length = max(1, geometry.size.width - radius * 2)
            let steps = settings.thinkingStops
            let count = max(1, steps.count - 1)
            let selected = settings.thinkingIndex
            let fraction = dragFraction ?? CGFloat(selected ?? 0) / CGFloat(count)
            let selectedX = radius + fraction * length
            let active = selected != nil || dragFraction != nil
            let positionAnimation: Animation? = reduceMotion || dragFraction != nil ? nil : .spring(response: 0.28, dampingFraction: 0.90)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07)).frame(height: 24)
                LinearGradient(colors: [WorkspacePalette.accent.opacity(0.85), WorkspacePalette.accent], startPoint: .leading, endPoint: .trailing)
                    .overlay {
                        RainbowMetalFill().opacity(settings.maximumThinking ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.34), value: settings.maximumThinking)
                    }
                    .frame(width: geometry.size.width, height: 24)
                    .mask(alignment: .leading) { Capsule().frame(width: selectedX, height: 24) }
                    .opacity(active ? 1 : 0)
                    .animation(positionAnimation, value: fraction)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: active)
                ForEach(steps.indices, id: \.self) { index in
                    Circle().fill((selected.map { index <= $0 } ?? false) ? Color.white.opacity(0.55) : Color.primary.opacity(0.20))
                        .frame(width: 4, height: 4).position(x: radius + CGFloat(index) / CGFloat(count) * length, y: geometry.size.height / 2)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selected)
                }
                Circle().fill(WorkspacePalette.paper)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 1.5, x: 0, y: 1)
                    .frame(width: 28, height: 28).position(x: selectedX, y: geometry.size.height / 2)
                    .opacity(active ? 1 : 0)
                    .animation(positionAnimation, value: fraction)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: active)
            }.frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    usingPointer = true
                    focused = true
                    if abs(value.translation.width) > 2 || dragFraction != nil {
                        let fraction = min(1, max(0, (value.location.x - radius) / length))
                        dragFraction = fraction
                        settings.selectThinking(min(steps.count - 1, Int((fraction * CGFloat(count)).rounded())))
                    }
                }.onEnded { value in
                    let fraction = min(1, max(0, (value.location.x - radius) / length))
                    settings.selectThinking(min(steps.count - 1, Int((fraction * CGFloat(count)).rounded())))
                    dragFraction = nil
                })
        }.frame(height: 32).focusable().focused($focused).focusEffectDisabled()
            .overlay(RoundedRectangle(cornerRadius: Design.radius).strokeBorder(focused && !usingPointer ? WorkspacePalette.accent.opacity(0.6) : .clear, lineWidth: 2).padding(-3))
            .onChange(of: focused) { _, active in if !active { usingPointer = false } }
            .onMoveCommand { direction in
                usingPointer = false
                if direction == .left || direction == .down { adjust(-1) }
                if direction == .right || direction == .up { adjust(1) }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(L("思考强度"))
            .accessibilityValue(settings.thinkingTitle).accessibilityIdentifier("ai.effort")
            .accessibilityAdjustableAction { direction in
                switch direction { case .increment: adjust(1); case .decrement: adjust(-1); @unknown default: break }
            }
    }
    private func adjust(_ delta: Int) {
        let next = (settings.thinkingIndex ?? (delta > 0 ? -1 : settings.thinkingStops.count)) + delta
        settings.selectThinking(min(settings.thinkingStops.count - 1, max(0, next)))
    }
}

/// Soft diagonal color bands and a broad satin highlight share the same coordinate space.
private struct RainbowMetalFill: View {
    private let colors: [Color] = [
        Color(red: 0.94, green: 0.35, blue: 0.40), Color(red: 0.98, green: 0.64, blue: 0.32),
        Color(red: 0.96, green: 0.84, blue: 0.43), Color(red: 0.39, green: 0.73, blue: 0.59),
        Color(red: 0.40, green: 0.63, blue: 0.93), Color(red: 0.67, green: 0.48, blue: 0.85)
    ]
    var body: some View {
        Canvas { context, size in
            let span = max(1, (size.width + size.height) / 2)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: span, y: span)))
        }.overlay {
            LinearGradient(stops: [
                .init(color: .white.opacity(0.25), location: 0),
                .init(color: .white.opacity(0.06), location: 0.24),
                .init(color: .white.opacity(0.30), location: 0.48),
                .init(color: .white.opacity(0.08), location: 0.72),
                .init(color: .black.opacity(0.05), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct AIModelPicker: View {
    @ObservedObject var settings: AISettings
    var back: () -> Void
    @State private var query = ""
    private var enteredModel: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var models: [String] { settings.models.filter { enteredModel.isEmpty || $0.localizedCaseInsensitiveContains(enteredModel) } }
    private var showsDefaultModel: Bool { settings.backend.usesCLI && enteredModel.isEmpty }
    private var showsCustomModel: Bool { !enteredModel.isEmpty && !models.contains(enteredModel) }
    private var listHeight: CGFloat {
        var rows = models.count
        if showsDefaultModel { rows += 1 }
        if showsCustomModel { rows += 1 }
        if settings.models.isEmpty && enteredModel.isEmpty { rows += 1 }
        return min(174, CGFloat(max(1, rows)) * 32)
    }
    private var extraOptions: [AgentSessionOption] {
        settings.agentOptions.filter { option in
            guard option.isGenerationOption else { return false }
            if option.id == settings.reasoningOption?.id { return option.choices.count != settings.thinkingStops.count }
            if option.id == settings.speedOption?.id { return settings.speedValues == nil || option.choices.count > 2 }
            return true
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: back) { Image(systemName: "chevron.left").foregroundStyle(.secondary) }.buttonStyle(WorkspaceIconStyle()).help(L("返回"))
                Text(L("选择模型")).fontWeight(.medium)
                Spacer()
                if settings.refreshing { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await settings.refreshModels() } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(.secondary) }
                        .buttonStyle(WorkspaceIconStyle()).help(L("读取模型"))
                }
            }
            Menu {
                ForEach(AIBackend.allCases) { backend in
                    Button { settings.backend = backend } label: {
                        if settings.backend == backend { Label(backend.title, systemImage: "checkmark") }
                        else { Text(backend.title) }
                    }
                }
            } label: { HStack { Text(settings.backend.title); Spacer(); Image(systemName: "chevron.down") }.foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityIdentifier("ai.provider")
            TextField(L("搜索或输入模型名称"), text: $query).textFieldStyle(.roundedBorder)
                .onSubmit { if !enteredModel.isEmpty { select(enteredModel) } }.accessibilityIdentifier("ai.customModel")
            ScrollView {
                VStack(spacing: 2) {
                    if showsDefaultModel { modelRow(L("使用默认模型"), value: "") }
                    ForEach(models, id: \.self) { modelRow($0, value: $0) }
                    if showsCustomModel { modelRow(L("使用此模型"), value: enteredModel) }
                    if settings.models.isEmpty && query.isEmpty { Text(L("读取模型或输入模型名称。")).font(Design.small).foregroundStyle(.secondary).padding(.vertical, 8) }
                }
            }.frame(height: listHeight)
            if !extraOptions.isEmpty {
                Menu(L("更多生成选项")) {
                    ForEach(extraOptions) { option in
                        Picker(option.name, selection: Binding(get: { settings.agentSelections[option.id] ?? "" }, set: {
                            if $0.isEmpty { settings.agentSelections.removeValue(forKey: option.id) }
                            else { settings.agentSelections[option.id] = $0 }
                        })) {
                            Text(L("使用默认设置")).tag("")
                            ForEach(option.choices) { Text($0.name).tag($0.value) }
                        }
                    }
                }.menuStyle(.borderlessButton).font(Design.small)
            }
            if settings.statusIsError { Text(settings.status).font(Design.small).foregroundStyle(.secondary).lineLimit(2) }
        }.font(Design.body).onChange(of: settings.backend) { _, _ in
            query = ""
            Task { await settings.refreshModels() }
        }
    }
    private func modelRow(_ title: String, value: String) -> some View {
        Button { select(value) } label: {
            HStack {
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if settings.model == value { Image(systemName: "checkmark").foregroundStyle(WorkspacePalette.accent) }
            }.padding(.horizontal, 8).frame(height: 30).contentShape(RoundedRectangle(cornerRadius: Design.radius))
        }.buttonStyle(AIModelRowStyle())
    }
    private func select(_ model: String) {
        settings.model = model
        if settings.backend.usesACP { Task { await settings.refreshModels() } }
        back()
    }
}

private struct AIModelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label.foregroundStyle(.primary)
                .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: Design.radius))
                .onHover { hovered = $0 }
        }
    }
}
