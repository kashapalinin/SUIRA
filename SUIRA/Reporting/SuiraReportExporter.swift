import Foundation

@MainActor
public enum SuiraReportExporter {
    @discardableResult
    public static func exportMarkdown(directory: URL? = nil) throws -> URL {
        try exportMarkdown(store: .shared, directory: directory)
    }

    @discardableResult
    public static func exportMarkdown(
        store: RecompositionStore,
        directory: URL? = nil
    ) throws -> URL {
        let folder = directory ?? defaultExportDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileURL = folder.appendingPathComponent("SUIRA-Report-\(fileTimestamp()).md")
        try markdownReport(store: store).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public static func markdownReport() -> String {
        markdownReport(store: .shared)
    }

    public static func markdownReport(store: RecompositionStore) -> String {
        let snapshot = SuiraPerformanceMonitor.shared.snapshot
        let labelStats = store.labelStats
        let sourceStats = SuiraDataFlowLog.shared.sourceStats()
        let edges = SuiraDataFlowLog.shared.inferredEdges()
        let updateBatches = store.updateBatches
        let elementStats = store.elementStats
        let idEvents = SuiraOptimizationTracker.shared.recentIdEvents(limit: 40)
        let equatableEvents = SuiraOptimizationTracker.shared.recentEquatableEvents(limit: 40)
        let roots = SuiraDependencyRegistry.shared.resolvedRoots().map { root in
            (label: root.label, tree: SuiraMirrorTreeBuilder.buildRoot(label: root.label, value: root.value))
        }

        var lines: [String] = []
        lines.append("# SUIRA Performance Report")
        lines.append("")
        lines.append("- Generated at: \(displayTimestamp(Date()))")
        lines.append("- Body evaluations: \(store.bodyEvaluationCount)")
        lines.append("- Update batches: \(store.updateBatchCount)")
        lines.append("- Tracked View labels: \(labelStats.count)")
        lines.append("- Inferred cause links: \(edges.count)")
        lines.append("- State sources: \(sourceStats.count)")
        lines.append("")

        lines.append("## Performance")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("| --- | ---: |")
        lines.append("| Score | \(snapshot.performanceScore)% |")
        lines.append("| Current FPS | \(fps(snapshot.currentFPS)) |")
        lines.append("| Average FPS | \(fps(snapshot.averageFPS)) |")
        lines.append("| Target FPS | \(snapshot.targetFPS) |")
        lines.append("| Dropped frames | \(snapshot.droppedFrames) |")
        lines.append("| Frame overruns | \(snapshot.frameOverruns) |")
        lines.append("| CPU | \(percent(snapshot.cpuUsagePercent)) |")
        lines.append("| Memory | \(memory(snapshot.memoryUsageMB)) |")
        lines.append("")

        appendHotViews(labelStats, store: store, to: &lines)
        appendCauseLinks(edges, sourceStats: sourceStats, to: &lines)
        appendUpdateBatches(updateBatches, to: &lines)
        appendElementStats(elementStats, to: &lines)
        appendStateRoots(roots, to: &lines)
        appendOptimizationEvents(idEvents: idEvents, equatableEvents: equatableEvents, to: &lines)
        appendRecentEvents(store.events, to: &lines)

        lines.append("## Notes")
        lines.append("")
        lines.append("- Cause links are inferred from state mutations that happened shortly before recompositions.")
        lines.append("- p95 means that 95% of measured body evaluations were faster than this value.")
        lines.append("- The report is intended for debug builds and performance investigation, not for production analytics.")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func appendHotViews(
        _ stats: [RecompositionStore.LabelStats],
        store: RecompositionStore,
        to lines: inout [String]
    ) {
        lines.append("## Hot Views")
        lines.append("")
        guard !stats.isEmpty else {
            lines.append("No tracked View recompositions recorded.")
            lines.append("")
            return
        }

        lines.append("| View | Count | Share | Avg body | p95 body | Max body | Top cause |")
        lines.append("| --- | ---: | ---: | ---: | ---: | ---: | --- |")
        for stat in stats.prefix(12) {
            let share = Double(stat.count) / Double(max(store.bodyEvaluationCount, 1))
            let cause = SuiraDataFlowLog.shared.topSources(for: stat.label, limit: 1).first
            lines.append(
                "| \(cell(stat.label)) | \(stat.count) | \(percent(share * 100)) | \(duration(stat.averageBodyDuration)) | \(duration(stat.p95BodyDuration)) | \(duration(stat.maxBodyDuration)) | \(cell(cause?.source ?? "-")) |"
            )
        }
        lines.append("")
    }

    private static func appendCauseLinks(
        _ edges: [SuiraDataFlowLog.InferredEdge],
        sourceStats: [SuiraDataFlowLog.SourceStats],
        to lines: inout [String]
    ) {
        lines.append("## Cause Links")
        lines.append("")
        guard !edges.isEmpty else {
            lines.append("No inferred cause links recorded.")
            lines.append("")
            return
        }

        lines.append("| Source | View | Count |")
        lines.append("| --- | --- | ---: |")
        for edge in edges.prefix(20) {
            lines.append("| \(cell(edge.from)) | \(cell(edge.to)) | \(edge.count) |")
        }
        lines.append("")

        lines.append("### State Sources")
        lines.append("")
        lines.append("| Source | Total links | Affected views | Last detail |")
        lines.append("| --- | ---: | ---: | --- |")
        for source in sourceStats.prefix(12) {
            lines.append(
                "| \(cell(source.source)) | \(source.totalCount) | \(source.affectedViews) | \(cell(source.latestDetail ?? "-")) |"
            )
        }
        lines.append("")
    }

    private static func appendUpdateBatches(
        _ batches: [RecompositionStore.UpdateBatch],
        to lines: inout [String]
    ) {
        lines.append("## Update Batches")
        lines.append("")
        guard !batches.isEmpty else {
            lines.append("No update batches recorded.")
            lines.append("")
            return
        }

        lines.append("| Time | Events | Duration | Labels |")
        lines.append("| --- | ---: | ---: | --- |")
        for batch in batches.suffix(12).reversed() {
            lines.append(
                "| \(displayTimestamp(batch.startedAt)) | \(batch.eventCount) | \(duration(batch.duration)) | \(cell(batch.labels.prefix(5).joined(separator: ", "))) |"
            )
        }
        lines.append("")
    }

    private static func appendElementStats(
        _ stats: [RecompositionStore.ElementStats],
        to lines: inout [String]
    ) {
        lines.append("## Changed Elements")
        lines.append("")
        guard !stats.isEmpty else {
            lines.append("No changed element snapshots recorded.")
            lines.append("")
            return
        }

        lines.append("| Element | Tag | Screen | Count | Type |")
        lines.append("| --- | --- | --- | ---: | --- |")
        for stat in stats.prefix(12) {
            lines.append(
                "| \(cell(stat.displayName)) | \(cell(stat.tag)) | \(cell(stat.screenLabel)) | \(stat.count) | \(cell(compactTypeName(stat.typeName))) |"
            )
        }
        lines.append("")
    }

    private static func appendStateRoots(
        _ roots: [(label: String, tree: SuiraMirrorTreeNode)],
        to lines: inout [String]
    ) {
        lines.append("## State Roots")
        lines.append("")
        guard !roots.isEmpty else {
            lines.append("No state dependency probes registered.")
            lines.append("")
            return
        }

        for root in roots.prefix(8) {
            lines.append("### \(escapeInline(root.label))")
            lines.append("")
            lines.append("- Type: \(escapeInline(compactTypeName(root.tree.typeName)))")
            lines.append("- Direct fields: \(root.tree.children.count)")
            lines.append("- Total nodes: \(countNodes(root.tree))")
            lines.append("")
            lines.append("```")
            appendTree(root.tree, depth: 0, maxDepth: 4, maxLines: 40, to: &lines)
            lines.append("```")
            lines.append("")
        }
    }

    private static func appendOptimizationEvents(
        idEvents: [SuiraOptimizationTracker.IdChangeEvent],
        equatableEvents: [SuiraOptimizationTracker.EquatableEvent],
        to lines: inout [String]
    ) {
        lines.append("## Optimization Events")
        lines.append("")

        if idEvents.isEmpty {
            lines.append("No .id() changes recorded.")
        } else {
            lines.append("### .id() changes")
            lines.append("")
            lines.append("| Time | Label | Old | New |")
            lines.append("| --- | --- | --- | --- |")
            for event in idEvents.suffix(12).reversed() {
                lines.append(
                    "| \(displayTimestamp(event.timestamp)) | \(cell(event.label)) | \(cell(event.oldId ?? "nil")) | \(cell(event.newId)) |"
                )
            }
        }
        lines.append("")

        if equatableEvents.isEmpty {
            lines.append("No Equatable checks recorded.")
        } else {
            lines.append("### Equatable checks")
            lines.append("")
            lines.append("| Time | Label | Result |")
            lines.append("| --- | --- | --- |")
            for event in equatableEvents.suffix(12).reversed() {
                lines.append(
                    "| \(displayTimestamp(event.timestamp)) | \(cell(event.label)) | \(event.isEqual ? "true" : "false") |"
                )
            }
        }
        lines.append("")
    }

    private static func appendRecentEvents(
        _ events: [RecompositionEvent],
        to lines: inout [String]
    ) {
        lines.append("## Recent Body Events")
        lines.append("")
        guard !events.isEmpty else {
            lines.append("No body events recorded.")
            lines.append("")
            return
        }

        lines.append("| Time | View | Body duration |")
        lines.append("| --- | --- | ---: |")
        for event in events.suffix(20).reversed() {
            lines.append(
                "| \(displayTimestamp(event.timestamp)) | \(cell(event.viewLabel)) | \(duration(event.bodyDuration)) |"
            )
        }
        lines.append("")
    }

    private static func appendTree(
        _ node: SuiraMirrorTreeNode,
        depth: Int,
        maxDepth: Int,
        maxLines: Int,
        to lines: inout [String]
    ) {
        guard lines.count < maxLines + 1_000 else { return }
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)- \(node.title): \(compactTypeName(node.typeName)) = \(singleLine(node.valueSummary))")
        guard depth < maxDepth else { return }
        for child in node.children.prefix(12) {
            appendTree(child, depth: depth + 1, maxDepth: maxDepth, maxLines: maxLines, to: &lines)
        }
        if node.children.count > 12 {
            lines.append("\(indent)  - ... \(node.children.count - 12) more")
        }
    }

    private static func defaultExportDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func displayTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private static func duration(_ interval: TimeInterval?) -> String {
        guard let interval else { return "-" }
        if interval < 0.001 { return "<0.01 ms" }
        return String(format: "%.2f ms", interval * 1000)
    }

    private static func fps(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private static func memory(_ valueMB: Double) -> String {
        if valueMB >= 1024 {
            return String(format: "%.2f GB", valueMB / 1024.0)
        }
        return String(format: "%.0f MB", valueMB)
    }

    private static func countNodes(_ node: SuiraMirrorTreeNode) -> Int {
        1 + node.children.reduce(0) { $0 + countNodes($1) }
    }

    private static func compactTypeName(_ raw: String) -> String {
        let prefix = raw.split(separator: "<", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw
        return prefix.split(separator: ".", omittingEmptySubsequences: true).last.map(String.init) ?? prefix
    }

    private static func cell(_ value: String) -> String {
        singleLine(value)
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func escapeInline(_ value: String) -> String {
        singleLine(value)
            .replacingOccurrences(of: "`", with: "'")
    }
}
