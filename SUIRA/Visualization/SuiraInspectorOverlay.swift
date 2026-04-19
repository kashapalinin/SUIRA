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

            if isExpanded {
                SuiraInspectorFullScreen(
                    store: resolvedStore,
                    rootViewTree: SuiraSwiftUIViewTreeBuilder.buildRoot(label: "RootView", view: rootContent),
                    onClose: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isExpanded = false } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            } else {
                SuiraInspectorTopBar(store: resolvedStore) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isExpanded = true }
                }
                .zIndex(1)
            }
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
                    Text("\(store.totalCount)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    Spacer(minLength: 0)
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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
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
    let rootViewTree: SuiraMirrorTreeNode
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
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)

                Group {
                    switch mainTab {
                    case .recompositions:
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            SuiraInspectorScrollContent(store: store, rootViewTree: rootViewTree)
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
            .padding(.top, 6)
            .padding(.horizontal, 4)
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
        let total = max(store.totalCount, 1)
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
    private var roots: [(label: String, tree: SuiraMirrorTreeNode)] {
        SuiraDependencyRegistry.shared.resolvedRoots().map { label, value in
            (label, SuiraMirrorTreeBuilder.buildRoot(label: label, value: value))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

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

// MARK: - Content

private struct SuiraInspectorScrollContent: View {
    let store: RecompositionStore
    let rootViewTree: SuiraMirrorTreeNode

    private struct Finding: Identifiable {
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

    private func topCauses(for label: String) -> [SuiraDataFlowLog.ViewCause] {
        SuiraDataFlowLog.shared.topSources(for: label, limit: 3)
    }

    private var findings: [Finding] {
        guard store.totalCount > 0 else { return [] }

        var items: [Finding] = []

        for stat in stats.prefix(8) {
            let share = Double(stat.count) / Double(max(store.totalCount, 1))

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summarySection
                recompositionProfileSection
                hierarchySection
                eventsSection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сводка")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryTile(title: "Всего", value: "\(store.totalCount)")
                summaryTile(title: "Меток", value: "\(store.countsByLabel.count)")
                summaryTile(title: "Событий в буфере", value: "\(store.events.count)")
                summaryTile(title: "Запись", value: store.isEnabled ? "Вкл" : "Выкл")
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

    private var hierarchySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Иерархия View (Mirror)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Строится автоматически из корневого `View`, без дополнительной разметки в приложении.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            SuiraMirrorTreeOutline(node: rootViewTree)
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var recompositionProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Профиль: Избыточные Рекомпозиции")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if findings.isEmpty {
                Text("Пока нет выраженных аномалий в текущем буфере событий.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(findings) { finding in
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
                    Text(elementStats.isEmpty ? "Метрики по меткам" : "Изменившиеся элементы")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if elementStats.isEmpty {
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
                                    profileMetricPill(title: "avg", value: suiraDurationText(stat.averageBodyDuration))
                                    profileMetricPill(title: "p95", value: suiraDurationText(stat.p95BodyDuration))
                                    profileMetricPill(title: "max", value: suiraDurationText(stat.maxBodyDuration))
                                }

                                let causes = topCauses(for: stat.label)
                                if !causes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Основные причины")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(causes) { cause in
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Image(systemName: "arrow.right")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                Text(cause.source)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                                Spacer(minLength: 6)
                                                Text("×\(cause.count)")
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    } else {
                        ForEach(elementStats.prefix(12)) { stat in
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

                                HStack(spacing: 10) {
                                    profileMetricPill(title: "type", value: suiraCompactTypeName(stat.typeName))
                                }

                                Text("Экран: \(stat.screenLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(stat.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)

                                let causes = topCauses(for: stat.analysisLabel)
                                if !causes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Основные причины")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(causes) { cause in
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Image(systemName: "arrow.right")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                Text(cause.source)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                                Spacer(minLength: 6)
                                                Text("×\(cause.count)")
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
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
            Text("Последние события")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if store.events.isEmpty {
                Text("Пусто")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(store.events.suffix(40).reversed())) { event in
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
                        .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
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
    /// Базовое подключение остаётся минимальным: overlay + `trackRecomposition` на корневой экран.
    /// Более глубокая иерархия появится только если приложение опционально размечает дочерние вью.
    ///
    /// Обновление через `TimelineView`, без `@ObservedObject`, чтобы не провоцировать лишние проходы `body` отслеживаемых экранов.
    func suiraInspectorOverlay(store: RecompositionStore? = nil) -> some View {
        SuiraInspectorOverlay(store: store) { self }
    }
}
