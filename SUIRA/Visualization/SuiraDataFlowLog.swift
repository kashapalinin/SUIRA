import Foundation

/// Журнал явных мутаций данных и выводимых из них рёбер «источник → экран (метка рекомпозиции)».
///
/// SwiftUI не сообщает граф зависимостей: рёбра строятся **эвристически** — при каждой рекомпозиции
/// учитываются мутации с тем же `source`, попавшие в окно `inferenceWindow` до момента рекомпозиции.
/// Для осмысленного графа вызывайте `SuiraDataFlow.mutation(...)` в местах записи состояния или используйте `Binding.suiraMutationSource`.
public final class SuiraDataFlowLog: @unchecked Sendable {
    public static let shared = SuiraDataFlowLog()

    private let lock = NSLock()

    /// Окно (секунды): какие мутации считаются «причиной» следующей рекомпозиции.
    public var inferenceWindow: TimeInterval = 0.15

    private var mutations: [MutationEntry] = []
    private var maxMutations = 400
    /// fromSource -> toViewLabel -> count
    private var edgeCounts: [String: [String: Int]] = [:]

    private init() {}

    public struct MutationEntry: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let source: String
        public let detail: String?

        public init(id: UUID = UUID(), timestamp: Date = .now, source: String, detail: String?) {
            self.id = id
            self.timestamp = timestamp
            self.source = source
            self.detail = detail
        }
    }

    public struct InferredEdge: Identifiable, Hashable, Sendable {
        public let from: String
        public let to: String
        public let count: Int
        public var id: String { "\(from)\u{2063}→\u{2063}\(to)" }
    }

    public struct SourceStats: Identifiable, Hashable, Sendable {
        public let source: String
        public let totalCount: Int
        public let affectedViews: Int

        public var id: String { source }
    }

    public struct ViewCause: Identifiable, Hashable, Sendable {
        public let source: String
        public let count: Int

        public var id: String { source }
    }

    public func recordMutation(source: String, detail: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        mutations.append(MutationEntry(source: source, detail: detail))
        if mutations.count > maxMutations {
            mutations.removeFirst(mutations.count - maxMutations)
        }
    }

    /// Вызывается из `RecompositionStore` при каждой зафиксированной рекомпозиции.
    public func onRecomposition(viewLabel: String, at timestamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        let start = timestamp.addingTimeInterval(-inferenceWindow)
        let relevant = mutations.filter { $0.timestamp >= start && $0.timestamp <= timestamp }
        let uniqueSources = Set(relevant.map(\.source))
        for source in uniqueSources {
            edgeCounts[source, default: [:]][viewLabel, default: 0] += 1
        }
    }

    public func inferredEdges() -> [InferredEdge] {
        lock.lock()
        defer { lock.unlock() }
        var list: [InferredEdge] = []
        for (from, tos) in edgeCounts {
            for (to, count) in tos {
                list.append(InferredEdge(from: from, to: to, count: count))
            }
        }
        return list.sorted { $0.count > $1.count }
    }

    public func sourceStats() -> [SourceStats] {
        lock.lock()
        defer { lock.unlock() }

        return edgeCounts.map { source, targets in
            SourceStats(
                source: source,
                totalCount: targets.values.reduce(0, +),
                affectedViews: targets.count
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

    public func recentMutations(limit: Int = 80) -> [MutationEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(mutations.suffix(limit))
    }

    public func topSources(for viewLabel: String, limit: Int = 3) -> [ViewCause] {
        lock.lock()
        defer { lock.unlock() }

        return edgeCounts.compactMap { source, targets in
            guard let count = targets[viewLabel], count > 0 else { return nil }
            return ViewCause(source: source, count: count)
        }
        .sorted {
            if $0.count == $1.count {
                return $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
            }
            return $0.count > $1.count
        }
        .prefix(limit)
        .map { $0 }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        mutations.removeAll(keepingCapacity: false)
        edgeCounts.removeAll(keepingCapacity: false)
    }
}

/// Удобная точка входа для записи мутаций с главного потока (типичные `Button`, `Binding`).
public enum SuiraDataFlow {
    public static func mutation(_ source: String, detail: String? = nil) {
        SuiraDataFlowLog.shared.recordMutation(source: source, detail: detail)
    }
}

public extension SuiraDataFlowLog {
    func recordDiffs(
        previous: SuiraValueSnapshot?,
        current: SuiraValueSnapshot,
        limit: Int = 20
    ) {
        let changes = SuiraValueSnapshotBuilder.diff(previous: previous, current: current, limit: limit)
        for change in changes {
            let source = change.path.isEmpty ? current.label : "\(current.label).\(change.path)"
            let detail = diffDetail(oldValue: change.oldValue, newValue: change.newValue)
            recordMutation(source: source, detail: detail)
        }
    }

    private func diffDetail(oldValue: String?, newValue: String?) -> String {
        switch (oldValue, newValue) {
        case let (old?, new?):
            return "\(old) -> \(new)"
        case let (nil, new?):
            return "new: \(new)"
        case let (old?, nil):
            return "removed: \(old)"
        case (nil, nil):
            return "changed"
        }
    }
}
