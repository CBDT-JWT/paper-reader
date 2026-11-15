import SwiftUI
import AppKit
import PaperCore

@MainActor final class RelatedPapersController: ObservableObject {
    @Published var graph: LiteratureGraph?
    @Published var positions: [String: CGPoint] = [:]
    @Published var selectedID: String?
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    private struct Cache: Codable { let query: String; let graph: LiteratureGraph }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var selected: RelatedPaper? { graph?.papers.first { $0.id == selectedID } }
    func open(_ paper: Paper, store: LibraryStore) {
        let doi = paper.metadata?.doi ?? ""
        query = doi.isEmpty ? paper.metadata?.title ?? paper.title : doi
        load(paperID: paper.id, store: store, useCache: true)
    }
    func load(paperID: UUID, store: LibraryStore, useCache: Bool = false) {
        task?.cancel()
        let token = UUID(); generation = token
        let query = query
        loading = true; error = nil
        task = Task {
            defer { if generation == token { loading = false } }
            do {
                let graph: LiteratureGraph
                if useCache, let data = try await store.readSidecar(paperID, name: "related-papers.json"),
                   let cached = try? JSONDecoder().decode(Cache.self, from: data), cached.query == query,
                   cached.graph.papers.first?.id == cached.graph.rootID, Set(cached.graph.papers.map(\.id)).count == cached.graph.papers.count {
                    graph = cached.graph
                } else {
                    graph = try await RelatedPapersService.load(query: query)
                }
                let positions = await Task.detached { LiteratureGraphLayout.positions(graph) }.value
                try Task.checkCancellation()
                guard token == generation else { return }
                self.graph = graph; self.positions = positions; selectedID = graph.rootID
                try await store.saveSidecar(paperID, name: "related-papers.json", data: JSONEncoder().encode(Cache(query: query, graph: graph)))
            } catch is CancellationError { }
            catch { if token == generation { self.error = error.localizedDescription } }
        }
    }
    func resetLayout() {
        guard let graph else { return }
        let token = generation
        Task {
            let positions = await Task.detached { LiteratureGraphLayout.positions(graph) }.value
            if generation == token { self.positions = positions }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); loading = false }
}

struct RelatedPapersView: View {
    @ObservedObject var model: AppModel
    @StateObject private var controller = RelatedPapersController()
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var previousZoom: CGFloat = 1
    @State private var pan = CGSize.zero
    @State private var previousPan = CGSize.zero
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("关联文献")).font(Design.title)
                Spacer()
                if controller.loading { ProgressView().controlSize(.small) }
                Button(L("完成")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            HStack(spacing: 8) {
                TextField(L("DOI 或论文标题"), text: $controller.query).textFieldStyle(.roundedBorder).onSubmit { reload() }
                Button(L("探索")) { reload() }.disabled(controller.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { resetViewport() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help(L("重置视图"))
            }.padding(.horizontal, 20).padding(.bottom, 16)
            if let error = controller.error {
                HStack { Image(systemName: "exclamationmark.circle"); Text(error).textSelection(.enabled); Spacer(); Button(L("重试")) { reload() } }
                    .font(Design.small).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 12)
            }
            HStack(spacing: 0) {
                graphCanvas
                Rectangle().fill(Color(nsColor: WorkspacePalette.dividerNS)).frame(width: 1)
                inspector.frame(width: 280)
            }
            HStack(spacing: 16) {
                Label(L("引用关系"), systemImage: "line.diagonal").foregroundStyle(WorkspacePalette.accent)
                Label(L("相关文献"), systemImage: "circle.dotted").foregroundStyle(.secondary)
                Text(L("共同参考文献")).foregroundStyle(.secondary)
                Spacer()
                Text("OpenAlex").foregroundStyle(.secondary)
                if let graph = controller.graph { Text(graph.fetchedAt, style: .date).foregroundStyle(.secondary) }
            }.font(Design.small).padding(16)
        }.font(Design.body).background(WorkspacePalette.paper).frame(width: 1000, height: 700)
            .task(id: model.selectedID) { if let paper = model.currentPaper { controller.open(paper, store: model.store) } }
            .onDisappear { controller.cancel() }
    }
    private var graphCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                WorkspacePalette.canvas.contentShape(Rectangle()).gesture(DragGesture().onChanged { value in
                    pan = CGSize(width: previousPan.width + value.translation.width, height: previousPan.height + value.translation.height)
                }.onEnded { _ in previousPan = pan })
                if let graph = controller.graph {
                    Canvas { context, size in
                        for edge in graph.edges {
                            guard let a = controller.positions[edge.source], let b = controller.positions[edge.target] else { continue }
                            var path = Path(); path.move(to: point(a, in: size)); path.addLine(to: point(b, in: size))
                            let selected = edge.source == controller.selectedID || edge.target == controller.selectedID
                            let color = edge.kind == .citation ? WorkspacePalette.accent : Color.secondary
                            context.stroke(path, with: .color(color.opacity(selected ? 0.65 : 0.18)), style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: edge.kind == .related ? [3, 4] : []))
                        }
                    }.allowsHitTesting(false)
                    ForEach(graph.papers) { paper in
                        if let location = controller.positions[paper.id] {
                            LiteratureNode(paper: paper, selected: controller.selectedID == paper.id, root: graph.rootID == paper.id,
                                           select: { controller.selectedID = paper.id }, move: { delta in
                                let current = controller.positions[paper.id] ?? location
                                controller.positions[paper.id] = CGPoint(x: current.x + delta.width / (geometry.size.width * zoom), y: current.y + delta.height / (geometry.size.height * zoom))
                            }).position(point(location, in: geometry.size))
                        }
                    }
                } else if controller.loading {
                    ProgressView(L("正在建立文献图…")).font(Design.body)
                } else {
                    Text(L("输入 DOI 或论文标题，探索引用与相关文献。")).font(Design.body).foregroundStyle(.secondary).padding(30)
                }
            }.clipped().gesture(MagnificationGesture().onChanged { zoom = min(3, max(0.5, previousZoom * $0)) }.onEnded { _ in previousZoom = zoom })
        }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let paper = controller.selected {
                    Text(paper.title).font(Design.body).fontWeight(.semibold).textSelection(.enabled)
                    Text(paper.authors.prefix(6).joined(separator: ", ")).font(Design.small).foregroundStyle(.secondary)
                    Text([paper.year.map(String.init), paper.venue.isEmpty ? nil : paper.venue].compactMap { $0 }.joined(separator: " · ")).font(Design.small).foregroundStyle(.secondary)
                    Text(L("被引用 \(paper.citationCount) 次")).font(Design.small).foregroundStyle(.secondary)
                    Button(L("以此为中心")) { controller.query = paper.id; reload() }.disabled(controller.loading)
                    if let url = paper.url { Link(L("查看论文来源"), destination: url) }
                    if let local = model.papers.first(where: { !paper.doi.isEmpty && MetadataService.doi(in: $0.metadata?.doi ?? "") == paper.doi.lowercased() }) {
                        Button(L("在文献库中打开")) { Task { await model.select(local.id); dismiss() } }
                    }
                    if !paper.abstract.isEmpty { Text(paper.abstract).font(Design.body).textSelection(.enabled).lineSpacing(4) }
                    if let graph = controller.graph {
                        let edges = graph.edges.filter { $0.source == paper.id || $0.target == paper.id }
                        if let strongest = edges.filter({ $0.kind == .sharedReferences }).map(\.strength).max() {
                            Text(L("与相连节点最多共享 \(strongest) 篇参考文献")).font(Design.small).foregroundStyle(.secondary)
                        }
                    }
                } else { Text(L("选择节点查看文献信息")).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func point(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (location.x - 0.5) * size.width * zoom + size.width / 2 + pan.width,
                y: (location.y - 0.5) * size.height * zoom + size.height / 2 + pan.height)
    }
    private func resetViewport() { zoom = 1; previousZoom = 1; pan = .zero; previousPan = .zero; controller.resetLayout() }
    private func reload() { guard let id = model.selectedID else { return }; resetViewport(); controller.load(paperID: id, store: model.store) }
}

private struct LiteratureNode: View {
    let paper: RelatedPaper
    let selected: Bool
    let root: Bool
    var select: () -> Void
    var move: (CGSize) -> Void
    @State private var previousTranslation = CGSize.zero
    var body: some View {
        Button(action: select) {
            Circle().fill(root ? WorkspacePalette.accent : WorkspacePalette.selection)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(selected ? WorkspacePalette.accent : Color.clear, lineWidth: 2).padding(-4))
                .frame(width: 38, height: 38)
                .overlay(alignment: .top) {
                    VStack(spacing: 2) {
                        Text(paper.title).font(Design.small).fontWeight(selected || root ? .semibold : .regular).lineLimit(2).multilineTextAlignment(.center)
                        if let year = paper.year { Text(String(year)).font(Design.small).foregroundStyle(.secondary) }
                    }.frame(width: 108).offset(y: 34)
                }
        }.buttonStyle(.plain).help(paper.title).accessibilityLabel(paper.title)
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                move(CGSize(width: value.translation.width - previousTranslation.width, height: value.translation.height - previousTranslation.height))
                previousTranslation = value.translation
            }.onEnded { _ in previousTranslation = .zero })
    }
    private var diameter: CGFloat { root ? 24 : CGFloat(min(22, 10 + log2(Double(paper.citationCount + 1)) * 1.3)) }
}
