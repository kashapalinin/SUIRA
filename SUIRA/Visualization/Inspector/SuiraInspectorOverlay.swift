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
            .accessibilityIdentifier("SUIRAInspectorTopBar")
            .accessibilityLabel("SUIRA Inspector")
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
    @State private var exportErrorAlert: SuiraExportAlert?
    @State private var sharedReport: SuiraSharedReport?

    private struct SuiraExportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private struct SuiraSharedReport: Identifiable {
        let id = UUID()
        let url: URL
    }

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
                    Button {
                        exportReport()
                    } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline)
                    Button("Сброс", role: .destructive) {
                        store.reset()
                        SuiraPerformanceMonitor.shared.reset()
                        SuiraDependencyRegistry.shared.removeAll()
                        SuiraOptimizationTracker.shared.reset()
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
                    Text("Сводка").tag(SuiraInspectorMainTab.recompositions)
                    Text("Причины").tag(SuiraInspectorMainTab.dataFlow)
                    Text("Состояние").tag(SuiraInspectorMainTab.dependencies)
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
        .alert(item: $exportErrorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("ОК"))
            )
        }
        .sheet(item: $sharedReport) { report in
            SuiraReportShareSheet(url: report.url)
        }
    }

    private func exportReport() {
        do {
            let url = try SuiraReportExporter.exportMarkdown(
                store: store,
                directory: FileManager.default.temporaryDirectory
            )
            sharedReport = SuiraSharedReport(url: url)
        } catch {
            exportErrorAlert = SuiraExportAlert(
                title: "Не удалось сохранить отчёт",
                message: error.localizedDescription
            )
        }
    }
}

private struct SuiraReportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Data flow tab

private struct SuiraDataFlowTabContent: View {
    let store: RecompositionStore

    private struct SourceImpactGroup: Identifiable {
        let source: String
        let totalCount: Int
        let affectedViews: Int
        let fields: [String]
        let edges: [SuiraDataFlowLog.InferredEdge]

        var id: String { source }
    }

    private struct RecentVariableSource: Identifiable {
        let source: String
        let mutationCount: Int
        let latestDetail: String?
        let lastSeenAt: Date

        var id: String { source }
    }

    private struct RepairLink: Identifiable {
        let source: String
        let target: String
        let count: Int
        let viewCount: Int
        let p95BodyDuration: TimeInterval?
        let fields: [String]
        let diagnosis: String
        let action: String
        let severity: String
        let color: Color

        var id: String { "\(source)\u{2063}→\u{2063}\(target)" }
    }

    private var edges: [SuiraDataFlowLog.InferredEdge] {
        SuiraDataFlowLog.shared.inferredEdges()
    }

    private var viewStatsByLabel: [String: RecompositionStore.LabelStats] {
        Dictionary(uniqueKeysWithValues: store.labelStats.map { ($0.label, $0) })
    }

    private var impactGroups: [SourceImpactGroup] {
        let groupedEdges = Dictionary(grouping: edges) { sourceRoot($0.from) }

        return groupedEdges.map { rootSource, sourceEdges in
            let sourceNames = Array(Set(sourceEdges.map(\.from))).sorted()
            let fieldNames = sourceNames.compactMap { sourceFieldName(root: rootSource, source: $0) }
            let combinedEdges = combineEdges(sourceEdges, as: rootSource)
            let sortedEdges = combinedEdges.sorted {
                if $0.count == $1.count {
                    return $0.to.localizedCaseInsensitiveCompare($1.to) == .orderedAscending
                }
                return $0.count > $1.count
            }
            let totalCount = sortedEdges.reduce(0) { $0 + $1.count }
            return SourceImpactGroup(
                source: rootSource,
                totalCount: totalCount,
                affectedViews: sortedEdges.count,
                fields: fieldNames,
                edges: sortedEdges
            )
        }
        .sorted {
            if $0.totalCount == $1.totalCount {
                if $0.affectedViews == $1.affectedViews {
                    return $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
                }
                return $0.affectedViews > $1.affectedViews
            }
            return $0.totalCount > $1.totalCount
        }
    }

    private var recentVariableSources: [RecentVariableSource] {
        let grouped = Dictionary(grouping: SuiraDataFlowLog.shared.recentMutations(limit: 120)) { mutation in
            sourceRoot(mutation.source)
        }

        return grouped.compactMap { source, mutations in
            guard let latest = mutations.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return RecentVariableSource(
                source: source,
                mutationCount: mutations.count,
                latestDetail: latest.detail,
                lastSeenAt: latest.timestamp
            )
        }
        .sorted {
            if $0.lastSeenAt == $1.lastSeenAt {
                return $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
            }
            return $0.lastSeenAt > $1.lastSeenAt
        }
    }

    private var repairLinks: [RepairLink] {
        impactGroups.flatMap { group in
            group.edges.compactMap { edge in
                makeRepairLink(group: group, edge: edge)
            }
        }
        .sorted {
            if severityRank($0.severity) == severityRank($1.severity) {
                if $0.count == $1.count {
                    return $0.target.localizedCaseInsensitiveCompare($1.target) == .orderedAscending
                }
                return $0.count > $1.count
            }
            return severityRank($0.severity) > severityRank($1.severity)
        }
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dataFlowProfileSection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var dataFlowProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Причины")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            repairLinksSection

            if !recentVariableSources.isEmpty {
                recentVariablesSection
            }
        }
    }

    private var recentVariablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Источники состояния")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(recentVariableSources.prefix(5)) { source in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(source.source)
                                .font(.footnote.weight(.medium))
                                .lineLimit(2)
                            suiraTagBadge(SuiraDebugTag.make(from: source.source, prefix: "S"))
                        }
                        if let detail = source.latestDetail, !detail.isEmpty {
                            Text("Последнее: \(detail)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    Text("×\(source.mutationCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var repairLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Связи для исправления")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Показывает только практичные пары: какое состояние связано с какой View и что попробовать исправить.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if repairLinks.isEmpty {
                Text(edges.isEmpty ? "Пока нет связей. Запустите сценарий, где меняется состояние и происходят рекомпозиции." : "Связи есть, но явных кандидатов на исправление пока не видно.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ForEach(repairLinks.prefix(5)) { link in
                    repairLinkCard(link)
                }
            }
        }
        .padding(12)
        .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func repairLinkCard(_ link: RepairLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(link.severity)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(link.color, in: Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(link.source)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(link.target)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                    }

                    Text("Сигнал: связь повторилась \(link.count) раз после изменений состояния.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                repairTextRow(title: "Почему", text: link.diagnosis)
                repairTextRow(title: "Правка", text: link.action)
            }

            HStack(spacing: 8) {
                influenceMetricPill(title: "связь", value: "×\(link.count)")
                if link.viewCount > 0 {
                    influenceMetricPill(title: "body", value: "×\(link.viewCount)")
                }
                if let p95 = link.p95BodyDuration {
                    influenceMetricPill(title: "p95", value: suiraDurationText(p95))
                }
            }

            if !link.fields.isEmpty {
                Text("Поля источника: \(link.fields.prefix(4).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func repairTextRow(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
    }

    private func combineEdges(_ edges: [SuiraDataFlowLog.InferredEdge], as source: String) -> [SuiraDataFlowLog.InferredEdge] {
        let countsByView = edges.reduce(into: [String: Int]()) { result, edge in
            result[edge.to, default: 0] += edge.count
        }

        return countsByView.map { viewLabel, count in
            SuiraDataFlowLog.InferredEdge(from: source, to: viewLabel, count: count)
        }
    }

    private func sourceRoot(_ source: String) -> String {
        source.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? source
    }

    private func sourceFieldName(root: String, source: String) -> String? {
        guard source.hasPrefix("\(root).") else { return nil }
        let field = String(source.dropFirst(root.count + 1))
        return field.isEmpty ? nil : field
    }

    private func influenceMetricPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private func makeRepairLink(group: SourceImpactGroup, edge: SuiraDataFlowLog.InferredEdge) -> RepairLink? {
        let sourceShare = Double(edge.count) / Double(max(group.totalCount, 1))
        let viewStat = viewStatsByLabel[edge.to]
        let viewCount = viewStat?.count ?? 0
        let p95 = viewStat?.p95BodyDuration
        let signalScore = edge.count
            + (sourceShare >= 0.45 ? 3 : 0)
            + ((p95 ?? 0) >= 0.008 ? 3 : 0)
            + (group.affectedViews >= 3 ? 2 : 0)

        guard edge.count >= 3 || (p95 ?? 0) >= 0.008 || signalScore >= 6 else { return nil }

        let severity = repairSeverity(
            count: edge.count,
            sourceShare: sourceShare,
            p95: p95,
            affectedViews: group.affectedViews
        )

        return RepairLink(
            source: group.source,
            target: edge.to,
            count: edge.count,
            viewCount: viewCount,
            p95BodyDuration: p95,
            fields: group.fields,
            diagnosis: repairDiagnosis(
                source: group.source,
                target: edge.to,
                count: edge.count,
                viewCount: viewCount,
                sourceShare: sourceShare,
                fields: group.fields,
                p95: p95,
                affectedViews: group.affectedViews
            ),
            action: repairAction(
                source: group.source,
                target: edge.to,
                count: edge.count,
                sourceShare: sourceShare,
                fields: group.fields,
                p95: p95,
                affectedViews: group.affectedViews
            ),
            severity: severity,
            color: repairColor(severity)
        )
    }

    private func repairSeverity(
        count: Int,
        sourceShare: Double,
        p95: TimeInterval?,
        affectedViews: Int
    ) -> String {
        if count >= 8 || (count >= 5 && sourceShare >= 0.6) || (p95 ?? 0) >= 0.016 {
            return "P1"
        }
        if count >= 4 || (count >= 2 && sourceShare >= 0.6) || affectedViews >= 3 || (p95 ?? 0) >= 0.008 {
            return "P2"
        }
        return "P3"
    }

    private func repairColor(_ severity: String) -> Color {
        switch severity {
        case "P1": return .red
        case "P2": return .orange
        default: return .yellow
        }
    }

    private func severityRank(_ severity: String) -> Int {
        switch severity {
        case "P1": return 3
        case "P2": return 2
        default: return 1
        }
    }

    private func repairDiagnosis(
        source: String,
        target: String,
        count: Int,
        viewCount: Int,
        sourceShare: Double,
        fields: [String],
        p95: TimeInterval?,
        affectedViews: Int
    ) -> String {
        if looksLikeIdentityProblem(source: source, target: target) {
            return "`\(source)` связан с `\(target)` \(count) раз. Похоже, меняется identity, поэтому SwiftUI может пересоздавать поддерево вместо точечного обновления."
        }
        if looksLikeHeavyBody(source: source, target: target, p95: p95) {
            return "`\(target)` дорогая при пересчёте: p95 body \(suiraDurationText(p95)). Связь с `\(source)` повторилась \(count) раз, поэтому частые изменения становятся заметным лагом."
        }
        if target.localizedCaseInsensitiveContains("Screen") {
            return "`\(source)` поднимает обновление до экрана `\(target)`. Если экран пересобирается \(count) раз, вместе с ним могут трогаться независимые дочерние блоки."
        }
        if fields.count >= 3 {
            return "`\(source)` меняется сразу по нескольким полям: \(repairFieldList(fields)). Эта пара повторилась \(count) раз и выглядит как слишком широкий вход для `\(target)`."
        }
        if affectedViews >= 4 {
            return "`\(source)` связан с \(affectedViews) View. `\(target)` только один из получателей, поэтому проблема похожа на широкий fan-out состояния."
        }
        if sourceShare >= 0.6, count >= 2 {
            return "Для `\(source)` эта связь доминирует: \(suiraPercent(sourceShare * 100)) его совпадений ведут к `\(target)`. Это хороший первый кандидат на локализацию."
        }
        if viewCount > 0 {
            return "`\(target)` прошла body \(viewCount) раз, из них \(count) раз рядом с изменением `\(source)`. Связь не абсолютная, но повторяется достаточно часто."
        }
        return "`\(source)` регулярно появляется перед body `\(target)`. Это эвристическая связь, но её стоит проверить первой среди похожих пар."
    }

    private func repairAction(
        source: String,
        target: String,
        count: Int,
        sourceShare: Double,
        fields: [String],
        p95: TimeInterval?,
        affectedViews: Int
    ) -> String {
        if looksLikeIdentityProblem(source: source, target: target) {
            return "Проверьте `.id()` около `\(target)`: используйте id сущности, а не `UUID()`, дату, индекс после сортировки или tick-счётчик."
        }
        if looksLikeHeavyBody(source: source, target: target, p95: p95) {
            return "Сначала облегчите `\(target)`: вынесите вычисления из `body`, закэшируйте derived value или считайте данные во ViewModel/Task."
        }
        if target.localizedCaseInsensitiveContains("Screen") {
            return "Не передавайте весь `\(source)` через экран. Опустите state к нужному блоку или вынесите зависимую часть в отдельную tracked/Equatable View."
        }
        if fields.count >= 3 {
            return "Передайте в `\(target)` projection из нужных полей (`\(repairFieldList(fields))`) или разделите `\(source)` на более мелкие модели."
        }
        if affectedViews >= 4 {
            return "Сократите fan-out `\(source)`: разнесите состояние по владельцам или передавайте дочерним View отдельные значения вместо общего контейнера."
        }
        if sourceShare >= 0.6, count >= 2 {
            return "Сфокусируйтесь на этой паре: попробуйте локальный `@State`, `Equatable` projection или отдельный ViewModel только для `\(target)`."
        }
        return "Проверьте, читает ли `\(target)` лишние поля из `\(source)`. Если да, передайте стабильное значение или маленький immutable DTO."
    }

    private func looksLikeIdentityProblem(source: String, target: String) -> Bool {
        source.localizedCaseInsensitiveContains("identity")
            || target.localizedCaseInsensitiveContains("identity")
            || target.localizedCaseInsensitiveContains(".id")
    }

    private func looksLikeHeavyBody(source: String, target: String, p95: TimeInterval?) -> Bool {
        source.localizedCaseInsensitiveContains("workload")
            || target.localizedCaseInsensitiveContains("expensive")
            || (p95 ?? 0) >= 0.008
    }

    private func repairFieldList(_ fields: [String]) -> String {
        let visible = fields.prefix(3).joined(separator: ", ")
        guard fields.count > 3 else { return visible }
        return "\(visible) +\(fields.count - 3)"
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
            Text("Оптимизация состояния")
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

    private struct OptimizationFinding: Identifiable {
        let title: String
        let detail: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(title)" }
    }

    private struct SummaryAction: Identifiable {
        let title: String
        let detail: String
        let recommendation: String
        let severity: String
        let color: Color

        var id: String { "\(severity):\(title):\(recommendation)" }
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
        systemFindings.filter { $0.severity == "P1" }.count +
        optimizationFindings.filter { $0.severity == "P1" }.count
    }

    private var totalFindingsCount: Int {
        findings.count + optimizationFindings.count + renderingFindings.count + systemFindings.count
    }

    private var warningFindingsCount: Int {
        findings.filter { $0.severity == "P2" }.count +
        renderingFindings.filter { $0.severity == "P2" }.count +
        systemFindings.filter { $0.severity == "P2" }.count +
        optimizationFindings.filter { $0.severity == "P2" }.count
    }

    private var statusColor: Color {
        if criticalFindingsCount > 0 { return .red }
        if !findings.isEmpty || !renderingFindings.isEmpty || !systemFindings.isEmpty || !optimizationFindings.isEmpty { return .orange }
        return .green
    }

    private var statusTitle: String {
        if store.bodyEvaluationCount == 0 { return "Нет данных" }
        if criticalFindingsCount > 0 { return "Есть критичные места" }
        if totalFindingsCount > 0 { return "Есть кандидаты на правку" }
        return "Серьёзных проблем не видно"
    }

    private var statusDetail: String {
        if store.bodyEvaluationCount == 0 {
            return "Повторите сценарий в приложении, чтобы инспектор накопил body-вызовы и связи состояния."
        }
        if let firstAction = summaryActions.first {
            return "Начните с \(firstAction.severity): \(firstAction.title). Ниже показана первая практичная правка."
        }
        return "Сценарий записан: \(store.bodyEvaluationCount) body-вызовов, \(stats.count) View-меток. Явных узких мест пока нет."
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

    private var optimizationFindings: [OptimizationFinding] {
        let idEvents = SuiraOptimizationTracker.shared.recentIdEvents(limit: 120)
        let equatableEvents = SuiraOptimizationTracker.shared.recentEquatableEvents(limit: 120)
        var items: [OptimizationFinding] = []

        let idCounts = Dictionary(grouping: idEvents, by: \.label)
            .mapValues { $0.count }
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }

        for (label, count) in idCounts.prefix(4) where count >= 3 {
            items.append(
                OptimizationFinding(
                    title: label,
                    detail: ".id() менялся \(count) раз за последний буфер. Это может пересоздавать поддерево и сбрасывать локальное состояние.",
                    severity: count >= 8 ? "P1" : "P2",
                    color: count >= 8 ? .red : .orange
                )
            )
        }

        let equatableGroups = Dictionary(grouping: equatableEvents, by: \.label)
        for (label, events) in equatableGroups.sorted(by: { lhs, rhs in
            if lhs.value.count == rhs.value.count {
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            return lhs.value.count > rhs.value.count
        }).prefix(4) {
            let trueCount = events.filter { $0.isEqual }.count
            let falseCount = events.count - trueCount

            if trueCount >= 3 {
                items.append(
                    OptimizationFinding(
                        title: label,
                        detail: "== вернул true \(trueCount) раз. Если рядом всё ещё растут body-вызовы, проверьте область состояния выше этого View.",
                        severity: trueCount >= 8 ? "P2" : "P3",
                        color: trueCount >= 8 ? .orange : .yellow
                    )
                )
            } else if falseCount >= 4 {
                items.append(
                    OptimizationFinding(
                        title: label,
                        detail: "== часто возвращает false (\(falseCount) раз). Возможно, в сравнение попали нестабильные поля.",
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

        if snapshot.cpuUsagePercent >= 90 {
            items.append(
                SystemFinding(
                    title: "CPU usage",
                    detail: "CPU процесса около \(suiraPercent(snapshot.cpuUsagePercent)). Высокая загрузка может совпадать с тяжёлыми рекомпозициями.",
                    severity: "P1",
                    color: .red
                )
            )
        } else if snapshot.cpuUsagePercent >= 70 {
            items.append(
                SystemFinding(
                    title: "CPU usage",
                    detail: "CPU процесса вырос до \(suiraPercent(snapshot.cpuUsagePercent)).",
                    severity: "P2",
                    color: .orange
                )
            )
        }

        return Array(renderingFindingsDeduped(items).prefix(6))
    }

    private var summaryActions: [SummaryAction] {
        var items: [SummaryAction] = []

        for finding in findings.prefix(4) {
            items.append(
                SummaryAction(
                    title: finding.title,
                    detail: finding.detail,
                    recommendation: recompositionRecommendation(for: finding.title),
                    severity: finding.severity,
                    color: finding.color
                )
            )
        }

        for finding in optimizationFindings.prefix(4) {
            items.append(
                SummaryAction(
                    title: finding.title,
                    detail: finding.detail,
                    recommendation: "Проверьте стабильность `.id()` и `Equatable`: нестабильные значения часто пересоздают поддерево вместо точечного обновления.",
                    severity: finding.severity,
                    color: finding.color
                )
            )
        }

        for finding in renderingFindings.prefix(4) {
            items.append(
                SummaryAction(
                    title: finding.title,
                    detail: finding.detail,
                    recommendation: "Вынесите тяжёлую работу из `body`: кэш, заранее рассчитанное поле, Task/ViewModel или более узкая дочерняя View.",
                    severity: finding.severity,
                    color: finding.color
                )
            )
        }

        for finding in systemFindings.prefix(4) {
            items.append(
                SummaryAction(
                    title: finding.title,
                    detail: finding.detail,
                    recommendation: "Сопоставьте системный симптом с горячими View ниже: чаще всего причина рядом с большим счётчиком body или высоким p95.",
                    severity: finding.severity,
                    color: finding.color
                )
            )
        }

        let deduped = summaryActionsDeduped(items)
        return Array(deduped.sorted {
            if summarySeverityRank($0.severity) == summarySeverityRank($1.severity) {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return summarySeverityRank($0.severity) > summarySeverityRank($1.severity)
        }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                priorityActionsSection
                hotspotsSection
                compactMetricsSection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.headline.weight(.semibold))
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(performanceSnapshot.performanceScore)%")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("оценка")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                summaryBadge(title: "критично", value: "\(criticalFindingsCount)", color: .red)
                summaryBadge(title: "важно", value: "\(warningFindingsCount)", color: .orange)
                summaryBadge(title: "body", value: "\(store.bodyEvaluationCount)", color: .gray)
                summaryBadge(title: "View", value: "\(stats.count)", color: .gray)
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

    private func summaryBadge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private var priorityActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Что исправить сначала")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if summaryActions.isEmpty {
                Text(store.bodyEvaluationCount == 0 ? "Пока нечего ранжировать: запустите проблемный сценарий." : "Явных кандидатов на правку пока нет. Если лаг виден глазами, повторите действие несколько раз на этом же экране.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(summaryActions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, 9)
                        }
                        summaryActionRow(action)
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func summaryActionRow(_ action: SummaryAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(summaryPriorityText(action.severity))
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(action.color, in: Capsule())

            VStack(alignment: .leading, spacing: 5) {
                Text(action.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Правка: \(action.recommendation)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func summaryPriorityText(_ severity: String) -> String {
        switch severity {
        case "P1": return "P1 критично"
        case "P2": return "P2 важно"
        default: return "P3 низко"
        }
    }

    private var hotspotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Горячие View")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if stats.isEmpty {
                Text("Пока нет размеченных View.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stats.prefix(5).enumerated()), id: \.element.id) { index, stat in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, 9)
                        }
                        hotspotRow(stat)
                    }
                }
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func hotspotRow(_ stat: RecompositionStore.LabelStats) -> some View {
        let share = Double(stat.count) / Double(max(store.bodyEvaluationCount, 1))
        let cause = topCauses(for: stat.label).first

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Text(stat.label)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                    suiraTagBadge(SuiraDebugTag.make(from: stat.label))
                }

                Spacer(minLength: 8)

                Text("×\(stat.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                profileMetricPill(title: "доля", value: suiraPercent(share * 100))
                profileMetricPill(title: "p95", value: suiraDurationText(stat.p95BodyDuration))
                profileMetricPill(title: "max", value: suiraDurationText(stat.maxBodyDuration))
            }

            Text(cause.map { "Вероятный источник: \($0.source)" } ?? "Источник пока не найден: откройте «Причины» после повторения сценария.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var compactMetricsSection: some View {
        let sourceCount = SuiraDataFlowLog.shared.sourceStats().count
        let edgeCount = SuiraDataFlowLog.shared.inferredEdges().count

        return VStack(alignment: .leading, spacing: 10) {
            Text("Метрики")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                compactMetricTile(title: "Body", value: "\(store.bodyEvaluationCount)", detail: "в текущем буфере")
                compactMetricTile(title: "Причины", value: "\(edgeCount)", detail: "\(sourceCount) источников")
                compactMetricTile(title: "FPS", value: suiraFPS(performanceSnapshot.averageFPS), detail: "средний")
                compactMetricTile(title: "Кадры", value: "\(performanceSnapshot.droppedFrames)", detail: "\(performanceSnapshot.frameOverruns) перегрузок")
                compactMetricTile(title: "CPU", value: suiraPercent(performanceSnapshot.cpuUsagePercent), detail: "процесс")
                compactMetricTile(title: "RAM", value: suiraMemory(performanceSnapshot.memoryUsageMB), detail: "процесс")
            }
        }
    }

    private func compactMetricTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func recompositionRecommendation(for label: String) -> String {
        if let source = topCauses(for: label).first?.source {
            return "Сузьте `\(source)` или передайте в `\(label)` только поля, которые эта View реально рисует."
        }
        return "Опустите state ближе к месту использования или вынесите независимый блок в отдельную tracked/Equatable View."
    }

    private func summarySeverityRank(_ severity: String) -> Int {
        switch severity {
        case "P1": return 3
        case "P2": return 2
        default: return 1
        }
    }

    private func summaryActionsDeduped(_ items: [SummaryAction]) -> [SummaryAction] {
        var seen: Set<String> = []
        var result: [SummaryAction] = []
        for item in items {
            if seen.insert("\(item.severity):\(item.title)").inserted {
                result.append(item)
            }
        }
        return result
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
            Text("Лишние рекомпозиции")
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

    private var optimizationProfileSection: some View {
        let idEvents = SuiraOptimizationTracker.shared.recentIdEvents(limit: 20)
        let equatableEvents = SuiraOptimizationTracker.shared.recentEquatableEvents(limit: 20)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Стабильность оптимизаций")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if optimizationFindings.isEmpty {
                Text("Нестабильных .id() и подозрительных сравнений Equatable пока не видно.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(optimizationFindings) { finding in
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

            if !idEvents.isEmpty || !equatableEvents.isEmpty {
                DisclosureGroup("Последние проверки") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(idEvents.reversed()) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(".id")
                                        .font(.caption2.monospaced().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(event.label)
                                        .font(.footnote.weight(.medium))
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(formatTime(event.timestamp))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Text("\(event.oldId ?? "nil") → \(event.newId)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        ForEach(equatableEvents.reversed()) { event in
                            HStack(spacing: 8) {
                                Text("==")
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(event.label)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Text(event.isEqual ? "true" : "false")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(event.isEqual ? .green : .orange)
                                Text(formatTime(event.timestamp))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuiraSystemColors.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(12)
                .background(SuiraSystemColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var renderingProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Производительность кадра")
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
                    summaryTile(title: "CPU", value: suiraPercent(performanceSnapshot.cpuUsagePercent))
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

private func suiraPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value)
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
