import SwiftUI
import UIKit

/// Верхний бар + разворачиваемая панель со статистикой и «деревом» по меткам `trackRecomposition`.
public struct SuiraInspectorOverlay<Content: View>: View {
    private let store: RecompositionStore?
    @ViewBuilder private let content: () -> Content

    @State private var isExpanded = false

    public init(store: RecompositionStore? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.store = store
        self.content = content
    }

    public var body: some View {
        SuiraInspectorOverlayBody(store: store, isExpanded: $isExpanded, content: content)
    }
}

private struct SuiraInspectorOverlayBody<Content: View>: View {
    let store: RecompositionStore?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.suiraRecompositionStore) private var environmentStore

    private var resolvedStore: RecompositionStore {
        store ?? environmentStore ?? .shared
    }

    var body: some View {
        let rootContent = content()

        ZStack(alignment: .top) {
            rootContent
                .safeAreaInset(edge: .top) {
                    if !isExpanded {
                        HStack {
                            Spacer(minLength: 0)
                            SuiraInspectorTopBar(store: resolvedStore) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isExpanded = true }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    }
                }

            if isExpanded {
                SuiraInspectorFullScreen(
                    store: resolvedStore,
                    onClose: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isExpanded = false } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .onAppear {
            SuiraPerformanceMonitor.shared.retain()
        }
        .onDisappear {
            SuiraPerformanceMonitor.shared.release()
        }
    }
}

// MARK: - Top bar

private struct SuiraInspectorTopBar: View {
    let store: RecompositionStore
    let onOpen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { _ in
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.body.weight(.semibold))
                    Text("SUIRA")
                        .font(.subheadline.weight(.semibold))
                    Text("\(store.updateBatchCount)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    Text("\(store.bodyEvaluationCount) body")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Full screen

private enum SuiraInspectorMainTab: Hashable {
    case recompositions
    case dataFlow
    case dependencies
}

private struct SuiraInspectorFullScreen: View {
    let store: RecompositionStore
    let onClose: () -> Void

    @State private var mainTab: SuiraInspectorMainTab = .recompositions
    @State private var refreshNonce = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Text("Инспектор SUIRA")
                        .font(.headline)
                    Spacer()
                    Button("Сброс", role: .destructive) {
                        store.reset()
                        SuiraPerformanceMonitor.shared.reset()
                        SuiraDependencyRegistry.shared.removeAll()
                        refreshNonce &+= 1
                    }
                    .font(.subheadline)
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

                Picker("Раздел", selection: $mainTab) {
                    Text("Рекомпозиции").tag(SuiraInspectorMainTab.recompositions)
                    Text("Поток данных").tag(SuiraInspectorMainTab.dataFlow)
                    Text("Зависимости").tag(SuiraInspectorMainTab.dependencies)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)

                Group {
                    switch mainTab {
                    case .recompositions:
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            SuiraInspectorScrollContent(store: store)
                        }
                    case .dataFlow:
                        TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                            SuiraDataFlowTabContent(store: store)
                        }
                    case .dependencies:
                        TimelineView(.periodic(from: .now, by: 0.35)) { _ in
                            SuiraDependencyTabContent()
                        }
                    }
                }
                .id(refreshNonce)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(SuiraSystemColors.groupedBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SuiraSystemColors.groupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 16)
            .padding(.horizontal, 8)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Data flow tab

private struct SuiraDataFlowTabContent: View {
    let store: RecompositionStore

    private struct SourceFinding: Identifiable {
        let source: String
        let detail: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(source)" }
    }

    private var edges: [SuiraDataFlowLog.InferredEdge] {
        SuiraDataFlowLog.shared.inferredEdges()
    }

    private var sourceStats: [SuiraDataFlowLog.SourceStats] {
        SuiraDataFlowLog.shared.sourceStats()
    }

    private var edgesBySource: [(source: String, edges: [SuiraDataFlowLog.InferredEdge])] {
        let grouped = Dictionary(grouping: edges, by: \.from)
        return grouped.keys.sorted().map { k in (k, grouped[k]!.sorted { $0.count > $1.count }) }
    }

    private var mergedTimeline: [SuiraTimelineEntry] {
        let muts = SuiraDataFlowLog.shared.recentMutations(limit: 60).map { SuiraTimelineEntry.mutation($0) }
        let recs = store.events.suffix(60).map { SuiraTimelineEntry.recomposition($0) }
        return (muts + recs).sorted { $0.date > $1.date }
    }

    private var sourceFindings: [SourceFinding] {
        let total = max(store.bodyEvaluationCount, 1)
        return sourceStats.prefix(8).compactMap { stat in
            let share = Double(stat.totalCount) / Double(total)

            if share >= 0.45, stat.totalCount >= 5 {
                return SourceFinding(
                    source: stat.source,
                    detail: "Поле коррелирует с \(Int(share * 100))% рекомпозиций и затрагивает \(stat.affectedViews) view.",
                    severity: "P1",
                    color: .red
                )
            }

            if stat.affectedViews >= 3, stat.totalCount >= 4 {
                return SourceFinding(
                    source: stat.source,
                    detail: "Источник влияет сразу на \(stat.affectedViews) view, возможен слишком широкий scope состояния.",
                    severity: "P2",
                    color: .orange
                )
            }

            if stat.totalCount >= 3 {
                return SourceFinding(
                    source: stat.source,
                    detail: "Источник часто появляется в графе зависимостей: \(stat.totalCount) совпадений.",
                    severity: "P3",
                    color: .yellow
                )
            }

            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dataFlowProfileSection

                if edges.isEmpty {
                    Text("Пока нет рёбер. Они появятся автоматически, когда библиотека увидит diff состояния перед рекомпозицией.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Кто кого обновляет")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(edgesBySource.enumerated()), id: \.offset) { _, group in
                            DisclosureGroup {
                                ForEach(group.edges) { edge in
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Text(edge.to)
                                            .font(.footnote)
                                        Spacer(minLength: 8)
                                        Text("×\(edge.count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            } label: {
                                HStack {
                                    Text(group.source)
                                        .font(.subheadline.weight(.medium))
                                    Spacer(minLength: 8)
                                    Text("\(group.edges.reduce(0) { $0 + $1.count })")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Хронология")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if mergedTimeline.isEmpty {
                        Text("Пусто")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(mergedTimeline.enumerated()), id: \.offset) { _, entry in
                                timelineRow(entry)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var dataFlowProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Профиль: Источники Изменений")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if sourceFindings.isEmpty {
                Text("Пока нет выраженных источников, которые заметно доминируют в потоке данных.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sourceFindings) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Text(finding.severity)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(finding.color, in: Capsule())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.source)
                                    .font(.footnote.weight(.semibold))
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !sourceStats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Топ источников")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(sourceStats.prefix(8)) { stat in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stat.source)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(2)
                                Text("Затронуто view: \(stat.affectedViews)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("×\(stat.totalCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

        }
    }

    @ViewBuilder
    private func timelineRow(_ entry: SuiraTimelineEntry) -> some View {
        switch entry {
        case let .mutation(m):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.source)
                            .font(.footnote.weight(.medium))
                        suiraTagBadge(SuiraDebugTag.make(from: m.source, prefix: "S"))
                    }
                    if let d = m.detail, !d.isEmpty {
                        Text(d)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(eventTimeFormatter.string(from: m.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case let .recomposition(e):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(e.viewLabel)
                            .font(.footnote.weight(.medium))
                        suiraTagBadge(SuiraDebugTag.make(from: e.viewLabel))
                    }
                    Text(eventTimeFormatter.string(from: e.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private enum SuiraTimelineEntry {
    case mutation(SuiraDataFlowLog.MutationEntry)
    case recomposition(RecompositionEvent)

    var date: Date {
        switch self {
        case let .mutation(m): m.timestamp
        case let .recomposition(e): e.timestamp
        }
    }
}

// MARK: - Dependencies tab (Mirror)

private struct SuiraDependencyTabContent: View {
    private struct StateOptimizationFinding: Identifiable {
        let title: String
        let detail: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(title)" }
    }

    private var roots: [(label: String, tree: SuiraMirrorTreeNode)] {
        SuiraDependencyRegistry.shared.resolvedRoots().map { label, value in
            (label, SuiraMirrorTreeBuilder.buildRoot(label: label, value: value))
        }
    }

    private var stateOptimizationFindings: [StateOptimizationFinding] {
        var items: [StateOptimizationFinding] = []
        let sourceStats = SuiraDataFlowLog.shared.sourceStats()

        for root in roots {
            let directChildren = root.tree.children.count
            let totalNodes = suiraCountNodes(root.tree)
            let collectionNodes = suiraCountNodes(root.tree) { node in
                node.typeName.contains("Array")
                    || node.typeName.contains("Dictionary")
                    || node.valueSummary.contains("элементов")
                    || node.valueSummary.contains("пар")
            }

            let matchingSources = sourceStats.filter { $0.source == root.label || $0.source.hasPrefix("\(root.label).") }
            let totalFanOut = matchingSources.reduce(0) { $0 + $1.affectedViews }
            let wideSources = matchingSources.filter { $0.affectedViews >= 3 }

            if directChildren >= 8 || totalNodes >= 28 {
                items.append(
                    StateOptimizationFinding(
                        title: root.label,
                        detail: "Корень состояния выглядит широким: \(directChildren) прямых полей, около \(totalNodes) узлов в дереве. Стоит дробить модель на более узкие куски.",
                        severity: totalNodes >= 40 ? "P1" : "P2",
                        color: totalNodes >= 40 ? .red : .orange
                    )
                )
            }

            if collectionNodes >= 3 {
                items.append(
                    StateOptimizationFinding(
                        title: root.label,
                        detail: "Внутри состояния много коллекций или крупных веток (\(collectionNodes)). Это частый признак того, что UI читает слишком большой кусок модели.",
                        severity: "P2",
                        color: .orange
                    )
                )
            }

            if totalFanOut >= 8, !wideSources.isEmpty {
                items.append(
                    StateOptimizationFinding(
                        title: root.label,
                        detail: "Источники из этого корня широко расходятся по view: \(wideSources.count) полей затрагивают сразу несколько экранных узлов.",
                        severity: "P1",
                        color: .red
                    )
                )
            } else if !matchingSources.isEmpty, matchingSources.count >= 4 {
                items.append(
                    StateOptimizationFinding(
                        title: root.label,
                        detail: "У корня много активных полей в графе зависимостей: \(matchingSources.count). Возможно, экрану передаётся слишком крупная модель целиком.",
                        severity: "P3",
                        color: .yellow
                    )
                )
            }
        }

        return Array(stateOptimizationFindingsDeduped(items).prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stateOptimizationProfileSection

                Text("Подключение: `.suiraDependencyProbe(\"Имя\", value: model)` на экране.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if roots.isEmpty {
                    Text("Нет зарегистрированных корней. Добавьте пробы на экран.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(roots.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "cube.transparent")
                                Text(item.label)
                                    .font(.headline)
                            }
                            SuiraMirrorTreeOutline(node: item.tree)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var stateOptimizationProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Профиль: Оптимизация Состояний")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if stateOptimizationFindings.isEmpty {
                Text("Пока нет выраженных сигналов, что состояние слишком широкое или плохо локализовано.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stateOptimizationFindings) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Text(finding.severity)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(finding.color, in: Capsule())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title)
                                    .font(.footnote.weight(.semibold))
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct SuiraMirrorTreeOutline: View {
    let node: SuiraMirrorTreeNode
    var gutterPrefix: String = ""
    var isLastSibling: Bool = true
    var isRoot: Bool = true

    private var childGutter: String {
        SuiraTreeGutter.childContinuation(
            parentGutter: gutterPrefix,
            parentIsLastSibling: isLastSibling,
            parentIsRoot: isRoot
        )
    }

    var body: some View {
        if node.children.isEmpty {
            SuiraMonospaceTreeRow(
                gutterPrefix: gutterPrefix,
                isLastSibling: isLastSibling,
                isRoot: isRoot,
                trailing: nil
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 6) {
                            Text(node.title)
                                .font(isRoot ? .subheadline.weight(.semibold) : .footnote.weight(.medium))
                            suiraTagBadge(node.tag)
                        }
                        Spacer(minLength: 8)
                        Text(node.typeName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    Text(node.valueSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
            }
            .padding(.vertical, 2)
        } else {
            DisclosureGroup {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { idx, child in
                    SuiraMirrorTreeOutline(
                        node: child,
                        gutterPrefix: childGutter,
                        isLastSibling: idx == node.children.count - 1,
                        isRoot: false
                    )
                }
            } label: {
                SuiraMonospaceTreeRow(
                    gutterPrefix: gutterPrefix,
                    isLastSibling: isLastSibling,
                    isRoot: isRoot,
                    trailing: nil
                ) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 6) {
                            Text(node.title)
                                .font(isRoot ? .subheadline.weight(.semibold) : .subheadline.weight(.medium))
                            suiraTagBadge(node.tag)
                        }
                        Spacer(minLength: 8)
                        Text(node.typeName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct SuiraTrackedViewHierarchyForest: View {
    let nodes: [RecompositionStore.ViewHierarchyNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                SuiraTrackedViewHierarchyOutline(
                    node: node,
                    isLastSibling: index == nodes.count - 1
                )
            }
        }
    }
}

private struct SuiraTrackedViewHierarchyOutline: View {
    let node: RecompositionStore.ViewHierarchyNode
    var gutterPrefix: String = ""
    var isLastSibling: Bool = true
    var isRoot: Bool = true

    private var childGutter: String {
        SuiraTreeGutter.childContinuation(
            parentGutter: gutterPrefix,
            parentIsLastSibling: isLastSibling,
            parentIsRoot: isRoot
        )
    }

    private var counterText: String {
        if node.children.isEmpty {
            return "×\(node.selfCount)"
        }
        if node.selfCount == 0 {
            return "Σ×\(node.subtreeCount)"
        }
        return "×\(node.selfCount)  Σ×\(node.subtreeCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SuiraMonospaceTreeRow(
                gutterPrefix: gutterPrefix,
                isLastSibling: isLastSibling,
                isRoot: isRoot,
                trailing: counterText
            ) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(suiraHierarchyHeatColor(node.subtreeCount))
                        .frame(width: 7, height: 7)
                    Text(node.title)
                        .font(isRoot ? .subheadline.weight(.semibold) : .footnote.weight(.medium))
                        .lineLimit(1)
                    suiraTagBadge(SuiraDebugTag.make(from: node.label))
                    if let p95 = node.p95BodyDuration, p95 > 0 {
                        Text("p95 \(suiraDurationText(p95))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)

            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                SuiraTrackedViewHierarchyOutline(
                    node: child,
                    gutterPrefix: childGutter,
                    isLastSibling: index == node.children.count - 1,
                    isRoot: false
                )
            }
        }
    }
}

// MARK: - Content

private struct SuiraInspectorScrollContent: View {
    let store: RecompositionStore
    @ObservedObject private var performanceMonitor = SuiraPerformanceMonitor.shared

    private struct Finding: Identifiable {
        let title: String
        let detail: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(title)" }
    }

    private struct RenderingFinding: Identifiable {
        let title: String
        let detail: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(title)" }
    }

    private struct SystemFinding: Identifiable {
        let title: String
        let detail: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(title)" }
    }

    private var stats: [RecompositionStore.LabelStats] {
        store.labelStats
    }

    private var elementStats: [RecompositionStore.ElementStats] {
        store.elementStats
    }

    private var viewHierarchy: [RecompositionStore.ViewHierarchyNode] {
        store.viewHierarchy
    }

    private var performanceSnapshot: SuiraPerformanceMonitor.Snapshot {
        performanceMonitor.snapshot
    }

    private var criticalFindingsCount: Int {
        findings.filter { $0.severity == "P1" }.count +
        renderingFindings.filter { $0.severity == "P1" }.count +
        systemFindings.filter { $0.severity == "P1" }.count
    }

    private var statusColor: Color {
        if criticalFindingsCount > 0 { return .red }
        if !findings.isEmpty || !renderingFindings.isEmpty || !systemFindings.isEmpty { return .orange }
        return .green
    }

    private func topCauses(for label: String) -> [SuiraDataFlowLog.ViewCause] {
        SuiraDataFlowLog.shared.topSources(for: label, limit: 3)
    }

    private var findings: [Finding] {
        guard store.bodyEvaluationCount > 0 else { return [] }

        var items: [Finding] = []

        for stat in stats.prefix(8) {
            let share = Double(stat.count) / Double(max(store.bodyEvaluationCount, 1))

            if share >= 0.45, stat.count >= 6 {
                items.append(
                    Finding(
                        title: stat.label,
                        detail: "На этот узел приходится \(Int(share * 100))% всех рекомпозиций за текущий буфер.",
                        severity: "P1",
                        color: .red
                    )
                )
            } else if share >= 0.25, stat.count >= 4 {
                items.append(
                    Finding(
                        title: stat.label,
                        detail: "Узел рекомпозируется заметно чаще остальных: \(stat.count) раз.",
                        severity: "P2",
                        color: .orange
                    )
                )
            }

            if let p95 = stat.p95BodyDuration, p95 >= 0.008 {
                items.append(
                    Finding(
                        title: stat.label,
                        detail: "95-й перцентиль времени body = \(suiraDurationText(p95)). Это уже похоже на тяжёлый участок.",
                        severity: p95 >= 0.016 ? "P1" : "P2",
                        color: p95 >= 0.016 ? .red : .orange
                    )
                )
            } else if let max = stat.maxBodyDuration, max >= 0.004 {
                items.append(
                    Finding(
                        title: stat.label,
                        detail: "Есть всплески времени body до \(suiraDurationText(max)).",
                        severity: "P3",
                        color: .yellow
                    )
                )
            }
        }

        return Array(items.prefix(8))
    }

    private var renderingStats: [RecompositionStore.LabelStats] {
        stats
            .filter { ($0.p95BodyDuration ?? 0) > 0 || ($0.maxBodyDuration ?? 0) > 0 }
            .sorted {
                let lhs = $0.p95BodyDuration ?? $0.maxBodyDuration ?? 0
                let rhs = $1.p95BodyDuration ?? $1.maxBodyDuration ?? 0
                if lhs == rhs {
                    return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }
                return lhs > rhs
            }
    }

    private var renderingFindings: [RenderingFinding] {
        var items: [RenderingFinding] = []

        for stat in renderingStats.prefix(8) {
            if let p95 = stat.p95BodyDuration, p95 >= 0.016 {
                items.append(
                    RenderingFinding(
                        title: stat.label,
                        detail: "95-й перцентиль времени body = \(suiraDurationText(p95)). Это уже выбивается за бюджет кадра для 60 FPS.",
                        severity: "P1",
                        color: .red
                    )
                )
            } else if let p95 = stat.p95BodyDuration, p95 >= 0.008 {
                items.append(
                    RenderingFinding(
                        title: stat.label,
                        detail: "95-й перцентиль времени body = \(suiraDurationText(p95)). Узел выглядит тяжёлым и может просаживать плавность в сложных сценариях.",
                        severity: "P2",
                        color: .orange
                    )
                )
            }

            if let max = stat.maxBodyDuration, max >= 0.012 {
                items.append(
                    RenderingFinding(
                        title: stat.label,
                        detail: "Есть пиковые всплески до \(suiraDurationText(max)). Возможны редкие, но заметные лаги.",
                        severity: "P2",
                        color: .orange
                    )
                )
            } else if let max = stat.maxBodyDuration, max >= 0.004 {
                items.append(
                    RenderingFinding(
                        title: stat.label,
                        detail: "Фиксируются всплески времени body до \(suiraDurationText(max)).",
                        severity: "P3",
                        color: .yellow
                    )
                )
            }
        }

        return Array(renderingFindingsDeduped(items).prefix(8))
    }

    private var systemFindings: [SystemFinding] {
        let snapshot = performanceSnapshot
        var items: [SystemFinding] = []

        if snapshot.averageFPS < 50 {
            items.append(
                SystemFinding(
                    title: "FPS",
                    detail: "Средний FPS = \(suiraFPS(snapshot.averageFPS)). Интерфейс уже заметно теряет плавность.",
                    severity: "P1",
                    color: .red
                )
            )
        } else if snapshot.averageFPS < 58 {
            items.append(
                SystemFinding(
                    title: "FPS",
                    detail: "Средний FPS = \(suiraFPS(snapshot.averageFPS)). Есть деградация относительно целевых 60 FPS.",
                    severity: "P2",
                    color: .orange
                )
            )
        }

        if snapshot.droppedFrames >= 10 {
            items.append(
                SystemFinding(
                    title: "Пропущенные кадры",
                    detail: "За текущий буфер зафиксировано \(snapshot.droppedFrames) пропущенных кадров.",
                    severity: "P1",
                    color: .red
                )
            )
        } else if snapshot.droppedFrames >= 3 {
            items.append(
                SystemFinding(
                    title: "Пропущенные кадры",
                    detail: "Появляются пропуски кадров: \(snapshot.droppedFrames).",
                    severity: "P2",
                    color: .orange
                )
            )
        }

        if snapshot.memoryUsageMB >= 1024 {
            items.append(
                SystemFinding(
                    title: "RAM usage",
                    detail: "Процесс использует около \(suiraMemory(snapshot.memoryUsageMB)) памяти.",
                    severity: "P1",
                    color: .red
                )
            )
        } else if snapshot.memoryUsageMB >= 600 {
            items.append(
                SystemFinding(
                    title: "RAM usage",
                    detail: "Память процесса выросла до \(suiraMemory(snapshot.memoryUsageMB)).",
                    severity: "P2",
                    color: .orange
                )
            )
        }

        return Array(renderingFindingsDeduped(items).prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summarySection
                recompositionProfileSection
                renderingProfileSection
                eventsSection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryTile(title: "Обновления", value: "\(store.updateBatchCount)")
                summaryTile(title: "Body-вызовы", value: "\(store.bodyEvaluationCount)")
                summaryTile(title: "Проблемы", value: "\(findings.count + renderingFindings.count + systemFindings.count)")
                summaryTile(title: "Средний FPS", value: suiraFPS(performanceSnapshot.averageFPS))
                summaryTile(title: "RAM", value: suiraMemory(performanceSnapshot.memoryUsageMB))
                summaryTile(title: "Оценка", value: "\(performanceSnapshot.performanceScore)%")
            }
            Toggle("Собирать события", isOn: Binding(
                get: { store.isEnabled },
                set: { store.isEnabled = $0 }
            ))
            .padding(.top, 4)
        }
        .padding(14)
        .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var recompositionProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Что перерисовывается слишком часто")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if findings.isEmpty {
                Text("Явных лишних рекомпозиций пока не видно.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(findings.prefix(3)) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Text(finding.severity)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(finding.color, in: Capsule())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title)
                                    .font(.footnote.weight(.semibold))
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !stats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Дерево рекомпозиций")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if viewHierarchy.isEmpty {
                        Text("Пока нет размеченных дочерних view.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        SuiraTrackedViewHierarchyForest(nodes: viewHierarchy)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    DisclosureGroup("Топ по body-вызовам") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(stats.prefix(8)) { stat in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        HStack(spacing: 6) {
                                            Text(stat.label)
                                                .font(.footnote.weight(.medium))
                                                .lineLimit(2)
                                            suiraTagBadge(SuiraDebugTag.make(from: stat.label))
                                        }
                                        Spacer(minLength: 8)
                                        Text("×\(stat.count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack(spacing: 10) {
                                        profileMetricPill(title: "p95", value: suiraDurationText(stat.p95BodyDuration))
                                        profileMetricPill(title: "max", value: suiraDurationText(stat.maxBodyDuration))
                                    }

                                    let causes = topCauses(for: stat.label)
                                    if let mainCause = causes.first {
                                        Text("Связано с: \(mainCause.source)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .font(.caption.weight(.semibold))

                    if !elementStats.isEmpty {
                        DisclosureGroup("Изменившиеся элементы") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(elementStats.prefix(6)) { stat in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            HStack(spacing: 6) {
                                                Text(stat.displayName)
                                                    .font(.footnote.weight(.medium))
                                                    .lineLimit(2)
                                                suiraTagBadge(stat.tag)
                                            }
                                            Spacer(minLength: 8)
                                            Text("×\(stat.count)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }

                                        Text("Экран: \(stat.screenLabel)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var renderingProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Плавность интерфейса")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if renderingFindings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("По времени выполнения `body` сейчас нет явных тяжёлых мест.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !systemFindings.isEmpty {
                        Divider()
                        ForEach(systemFindings) { finding in
                            systemFindingRow(finding)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(renderingFindings) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Text(finding.severity)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(finding.color, in: Capsule())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title)
                                    .font(.footnote.weight(.semibold))
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if !systemFindings.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                        ForEach(systemFindings) { finding in
                            systemFindingRow(finding)
                        }
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            DisclosureGroup("Подробные метрики") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summaryTile(title: "Текущий FPS", value: suiraFPS(performanceSnapshot.currentFPS))
                    summaryTile(title: "Средний FPS", value: suiraFPS(performanceSnapshot.averageFPS))
                    summaryTile(title: "RAM", value: suiraMemory(performanceSnapshot.memoryUsageMB))
                    summaryTile(title: "Пропуски кадров", value: "\(performanceSnapshot.droppedFrames)")
                    summaryTile(title: "Перегрузки кадра", value: "\(performanceSnapshot.frameOverruns)")
                    summaryTile(title: "Цель", value: "\(performanceSnapshot.targetFPS) FPS")
                }
            }
            .padding(12)
            .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !renderingStats.isEmpty {
                DisclosureGroup("Тяжёлые view") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(renderingStats.prefix(5)) { stat in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(stat.label)
                                            .font(.footnote.weight(.medium))
                                            .lineLimit(2)
                                        suiraTagBadge(SuiraDebugTag.make(from: stat.label))
                                    }
                                    Text("Рекомпозиций: \(stat.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("p95 \(suiraDurationText(stat.p95BodyDuration))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.primary)
                                    Text("max \(suiraDurationText(stat.maxBodyDuration))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func systemFindingRow(_ finding: SystemFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(finding.severity)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(finding.color, in: Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.title)
                    .font(.footnote.weight(.semibold))
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func profileMetricPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("Последние события") {
                if store.events.isEmpty {
                    Text("Пусто")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(store.events.suffix(20).reversed())) { event in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(event.viewLabel)
                                            .font(.subheadline.weight(.medium))
                                        suiraTagBadge(SuiraDebugTag.make(from: event.viewLabel))
                                    }
                                    Text(formatTime(event.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(suiraDurationText(event.bodyDuration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatTime(_ date: Date) -> String {
        eventTimeFormatter.string(from: date)
    }

}

private let eventTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

private func suiraDurationText(_ interval: TimeInterval?) -> String {
    guard let interval else { return "—" }
    if interval < 0.001 { return "<0.01 ms" }
    return String(format: "%.2f ms", interval * 1000)
}

private func suiraFPS(_ value: Double) -> String {
    String(format: "%.0f", value)
}

private func suiraMemory(_ valueMB: Double) -> String {
    if valueMB >= 1024 {
        return String(format: "%.2f GB", valueMB / 1024.0)
    }
    return String(format: "%.0f MB", valueMB)
}

private func suiraHierarchyHeatColor(_ count: Int) -> Color {
    if count >= 20 { return .red }
    if count >= 10 { return .orange }
    if count >= 4 { return .yellow }
    if count > 0 { return .green }
    return .secondary
}

private func suiraCountNodes(
    _ node: SuiraMirrorTreeNode,
    where predicate: ((SuiraMirrorTreeNode) -> Bool)? = nil
) -> Int {
    let ownCount = predicate?(node) ?? true ? 1 : 0
    return ownCount + node.children.reduce(0) { partial, child in
        partial + suiraCountNodes(child, where: predicate)
    }
}

private func stateOptimizationFindingsDeduped<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
    var seen: Set<T.ID> = []
    var result: [T] = []
    for item in items {
        if seen.insert(item.id).inserted {
            result.append(item)
        }
    }
    return result
}

private func renderingFindingsDeduped<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
    var seen: Set<T.ID> = []
    var result: [T] = []
    for item in items {
        if seen.insert(item.id).inserted {
            result.append(item)
        }
    }
    return result
}

private func suiraCompactTypeName(_ raw: String) -> String {
    let prefix = raw.split(separator: "<", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw
    return prefix.split(separator: ".", omittingEmptySubsequences: true).last.map(String.init) ?? prefix
}

private enum SuiraSystemColors {
    static var groupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var secondaryGroupedBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var tertiaryGroupedBackground: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
}

@ViewBuilder
private func suiraTagBadge(_ tag: String) -> some View {
    Text(tag)
        .font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
}

// MARK: - Public modifier

public extension View {
    /// Верхний бар SUIRA и полноэкранный инспектор (статистика, дерево по меткам, лента событий).
    ///
    /// Обновление через `TimelineView`, без `@ObservedObject`, чтобы не провоцировать лишние проходы `body` отслеживаемых экранов.
    func suiraInspectorOverlay(store: RecompositionStore? = nil) -> some View {
        SuiraInspectorOverlay(store: store) { self }
    }
}
