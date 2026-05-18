import Combine
import Foundation
import SwiftUI

private enum RecompositionStoreEnvironmentKey: EnvironmentKey {
    static let defaultValue: RecompositionStore? = nil
}

public extension EnvironmentValues {
    /// Override the active store for `trackRecomposition` (e.g. in tests or previews).
    var suiraRecompositionStore: RecompositionStore? {
        get { self[RecompositionStoreEnvironmentKey.self] }
        set { self[RecompositionStoreEnvironmentKey.self] = newValue }
    }
}

/// Collects recomposition events and per-label statistics.
///
/// Do not observe the same instance with `@ObservedObject` inside views that also call
/// `trackRecomposition` targeting this store: that creates a feedback loop (record → publish →
/// `body` → record).
@MainActor
public final class RecompositionStore: ObservableObject {
    public struct LabelStats: Identifiable, Sendable {
        public let label: String
        public let count: Int
        public let averageBodyDuration: TimeInterval?
        public let p95BodyDuration: TimeInterval?
        public let maxBodyDuration: TimeInterval?

        public var id: String { label }
    }

    public struct ViewHierarchyNode: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let title: String
        public let depth: Int
        public let selfCount: Int
        public let subtreeCount: Int
        public let averageBodyDuration: TimeInterval?
        public let p95BodyDuration: TimeInterval?
        public let maxBodyDuration: TimeInterval?
        public let children: [ViewHierarchyNode]

        public var hasOwnEvents: Bool { selfCount > 0 }
    }

    public struct UpdateBatch: Identifiable, Sendable {
        public let id: String
        public let startedAt: Date
        public let endedAt: Date
        public let eventCount: Int
        public let labels: [String]

        public var duration: TimeInterval {
            endedAt.timeIntervalSince(startedAt)
        }
    }

    public struct ElementStats: Identifiable, Sendable {
        public let key: String
        public let screenLabel: String
        public let path: String
        public let tag: String
        public let title: String
        public let typeName: String
        public let displayName: String
        public let count: Int

        public var id: String { key }
        public var analysisLabel: String { "\(displayName) [\(tag)]" }
    }

    /// Shared instance used when no environment override is set.
    public static let shared = RecompositionStore()

    /// When false, `record` does nothing (near-zero overhead).
    @Published public var isEnabled: Bool = true

    /// Most recent events, newest last. Size is bounded by `maxEvents`.
    @Published public private(set) var events: [RecompositionEvent] = []

    /// Total number of recompositions per label since last `reset()`.
    @Published public private(set) var countsByLabel: [String: Int] = [:]
    @Published public private(set) var elementCounts: [String: Int] = [:]
    @Published public private(set) var updateBatchCount: Int = 0

    private var previousScreenSnapshots: [String: SuiraValueSnapshot] = [:]
    private var previousDependencySnapshots: [String: SuiraValueSnapshot] = [:]
    private var previousViewNodeSignatures: [String: [String: String]] = [:]
    private var elementDescriptors: [String: ElementStats] = [:]
    private var firstSeenLabelOrder: [String: Int] = [:]
    private var nextLabelOrder = 0
    private var lastBatchEventTimestamp: Date?
    private var resetGeneration: UInt64 = 0
    private static let updateBatchGap: TimeInterval = 0.08

    /// Upper bound for `events` to cap memory use.
    public var maxEvents: Int = 500 {
        didSet { trimEventsIfNeeded() }
    }

    public init() {}

    public func reset() {
        resetGeneration &+= 1
        events.removeAll(keepingCapacity: false)
        countsByLabel.removeAll(keepingCapacity: false)
        elementCounts.removeAll(keepingCapacity: false)
        updateBatchCount = 0
        previousScreenSnapshots.removeAll(keepingCapacity: false)
        previousDependencySnapshots.removeAll(keepingCapacity: false)
        previousViewNodeSignatures.removeAll(keepingCapacity: false)
        elementDescriptors.removeAll(keepingCapacity: false)
        firstSeenLabelOrder.removeAll(keepingCapacity: false)
        nextLabelOrder = 0
        lastBatchEventTimestamp = nil
        SuiraDataFlowLog.shared.reset()
    }

    /// Records one recomposition for `viewLabel`.
    public func record(
        viewLabel: String,
        bodyDuration: TimeInterval? = nil,
        screenSnapshot: SuiraValueSnapshot? = nil,
        viewNodeSnapshots: [SuiraViewNodeSnapshot] = [],
        dependencySnapshots: [SuiraValueSnapshot] = [],
        generation: UInt64? = nil
    ) {
        guard isEnabled else { return }
        if let generation, generation != resetGeneration { return }

        if let screenSnapshot {
            let previous = previousScreenSnapshots[viewLabel]
            SuiraDataFlowLog.shared.recordDiffs(previous: previous, current: screenSnapshot, limit: 24)
            previousScreenSnapshots[viewLabel] = screenSnapshot
        }

        for snapshot in dependencySnapshots {
            let previous = previousDependencySnapshots[snapshot.label]
            SuiraDataFlowLog.shared.recordDiffs(previous: previous, current: snapshot, limit: 16)
            previousDependencySnapshots[snapshot.label] = snapshot
        }

        let event = RecompositionEvent(viewLabel: viewLabel, bodyDuration: bodyDuration)
        if firstSeenLabelOrder[viewLabel] == nil {
            firstSeenLabelOrder[viewLabel] = nextLabelOrder
            nextLabelOrder += 1
        }

        if !viewNodeSnapshots.isEmpty {
            recordElementChanges(
                screenLabel: viewLabel,
                nodeSnapshots: viewNodeSnapshots,
                timestamp: event.timestamp
            )
        }

        if let lastBatchEventTimestamp,
           event.timestamp.timeIntervalSince(lastBatchEventTimestamp) <= Self.updateBatchGap {
            self.lastBatchEventTimestamp = event.timestamp
        } else {
            updateBatchCount += 1
            lastBatchEventTimestamp = event.timestamp
        }

        events.append(event)
        trimEventsIfNeeded()

        countsByLabel[viewLabel, default: 0] += 1

        SuiraDataFlowLog.shared.onRecomposition(viewLabel: viewLabel, at: event.timestamp)
    }

    /// Total recompositions across all labels.
    public var totalCount: Int {
        countsByLabel.values.reduce(0, +)
    }

    /// Number of tracked `body` evaluations. This is intentionally more granular than user actions.
    public var bodyEvaluationCount: Int {
        totalCount
    }

    public var updateBatches: [UpdateBatch] {
        Self.makeUpdateBatches(from: events)
    }

    public var currentGeneration: UInt64 {
        resetGeneration
    }

    public var elementStats: [ElementStats] {
        elementCounts.compactMap { key, count in
            guard var descriptor = elementDescriptors[key] else { return nil }
            descriptor = ElementStats(
                key: descriptor.key,
                screenLabel: descriptor.screenLabel,
                path: descriptor.path,
                tag: descriptor.tag,
                title: descriptor.title,
                typeName: descriptor.typeName,
                displayName: descriptor.displayName,
                count: count
            )
            return descriptor
        }
        .sorted {
            if $0.count == $1.count {
                let lhs = elementTypePriority($0.typeName)
                let rhs = elementTypePriority($1.typeName)
                if lhs == rhs {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return lhs > rhs
            }
            return $0.count > $1.count
        }
    }

    public var labelStats: [LabelStats] {
        var durationsByLabel: [String: [TimeInterval]] = [:]
        for event in events {
            guard let duration = event.bodyDuration else { continue }
            durationsByLabel[event.viewLabel, default: []].append(duration)
        }

        return countsByLabel.map { label, count in
            let durations = durationsByLabel[label, default: []]
            let average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
            let sortedDurations = durations.sorted()
            let maxDuration = sortedDurations.last
            let p95Duration: TimeInterval? = {
                guard !sortedDurations.isEmpty else { return nil }
                let index = min(sortedDurations.count - 1, Int(Double(sortedDurations.count - 1) * 0.95))
                return sortedDurations[index]
            }()

            return LabelStats(
                label: label,
                count: count,
                averageBodyDuration: average,
                p95BodyDuration: p95Duration,
                maxBodyDuration: maxDuration
            )
        }
        .sorted {
            if $0.count == $1.count {
                let lhs = $0.p95BodyDuration ?? 0
                let rhs = $1.p95BodyDuration ?? 0
                if lhs == rhs {
                    let lhsOrder = firstSeenLabelOrder[$0.label] ?? Int.max
                    let rhsOrder = firstSeenLabelOrder[$1.label] ?? Int.max
                    if lhsOrder == rhsOrder {
                        return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                    }
                    return lhsOrder < rhsOrder
                }
                return lhs > rhs
            }
            return $0.count > $1.count
        }
    }

    public var viewHierarchy: [ViewHierarchyNode] {
        let stats = labelStats
        guard !stats.isEmpty else { return [] }

        let statsByLabel = Dictionary(uniqueKeysWithValues: stats.map { ($0.label, $0) })
        let orderedLabels = stats.map(\.label).sorted { lhs, rhs in
            let lhsOrder = firstSeenLabelOrder[lhs] ?? Int.max
            let rhsOrder = firstSeenLabelOrder[rhs] ?? Int.max
            if lhsOrder == rhsOrder {
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            return lhsOrder < rhsOrder
        }

        let root = RecompositionHierarchyBuilderNode(title: "root", label: "", depth: -1)
        for label in orderedLabels {
            let segments = Self.splitHierarchyLabel(label)
            guard !segments.isEmpty else { continue }

            var current = root
            var prefix = ""
            for (index, segment) in segments.enumerated() {
                prefix = prefix.isEmpty ? segment : "\(prefix).\(segment)"
                current = current.child(title: segment, label: prefix, depth: index)
            }
        }

        return root.orderedChildren.compactMap { child in
            Self.finalizeHierarchyNode(child, statsByLabel: statsByLabel)
        }
    }

    private func trimEventsIfNeeded() {
        guard maxEvents > 0, events.count > maxEvents else { return }
        events.removeFirst(events.count - maxEvents)
    }

    private static func splitHierarchyLabel(_ label: String) -> [String] {
        label
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func finalizeHierarchyNode(
        _ node: RecompositionHierarchyBuilderNode,
        statsByLabel: [String: LabelStats]
    ) -> ViewHierarchyNode? {
        let children = node.orderedChildren.compactMap { child in
            finalizeHierarchyNode(child, statsByLabel: statsByLabel)
        }
        let ownStats = statsByLabel[node.label]
        let selfCount = ownStats?.count ?? 0
        let subtreeCount = selfCount + children.reduce(0) { $0 + $1.subtreeCount }

        guard selfCount > 0 || subtreeCount > 0 else { return nil }

        return ViewHierarchyNode(
            id: node.label,
            label: node.label,
            title: node.title,
            depth: node.depth,
            selfCount: selfCount,
            subtreeCount: subtreeCount,
            averageBodyDuration: ownStats?.averageBodyDuration,
            p95BodyDuration: ownStats?.p95BodyDuration,
            maxBodyDuration: ownStats?.maxBodyDuration,
            children: children
        )
    }

    private static func makeUpdateBatches(from events: [RecompositionEvent]) -> [UpdateBatch] {
        guard let first = events.first else { return [] }

        var batches: [UpdateBatch] = []
        var startedAt = first.timestamp
        var endedAt = first.timestamp
        var eventCount = 0
        var labels: [String] = []
        var seenLabels = Set<String>()

        func appendLabel(_ label: String) {
            guard !seenLabels.contains(label) else { return }
            seenLabels.insert(label)
            labels.append(label)
        }

        func flushBatch() {
            guard eventCount > 0 else { return }
            batches.append(
                UpdateBatch(
                    id: "\(startedAt.timeIntervalSince1970)-\(eventCount)",
                    startedAt: startedAt,
                    endedAt: endedAt,
                    eventCount: eventCount,
                    labels: labels
                )
            )
        }

        for event in events {
            if event.timestamp.timeIntervalSince(endedAt) > updateBatchGap {
                flushBatch()
                startedAt = event.timestamp
                eventCount = 0
                labels.removeAll(keepingCapacity: true)
                seenLabels.removeAll(keepingCapacity: true)
            }

            endedAt = event.timestamp
            eventCount += 1
            appendLabel(event.viewLabel)
        }

        flushBatch()
        return batches
    }

    private func recordElementChanges(
        screenLabel: String,
        nodeSnapshots: [SuiraViewNodeSnapshot],
        timestamp: Date
    ) {
        let previous = previousViewNodeSignatures[screenLabel] ?? [:]
        let isFirstCapture = previous.isEmpty
        var current: [String: String] = [:]

        for snapshot in nodeSnapshots {
            current[snapshot.key] = snapshot.signature
            elementDescriptors[snapshot.key] = ElementStats(
                key: snapshot.key,
                screenLabel: snapshot.screenLabel,
                path: snapshot.path,
                tag: snapshot.tag,
                title: snapshot.title,
                typeName: snapshot.typeName,
                displayName: snapshot.displayName,
                count: elementCounts[snapshot.key, default: 0]
            )

            guard !isFirstCapture else { continue }
            let oldSignature = previous[snapshot.key]
            let shouldCountAsChanged =
                oldSignature != snapshot.signature ||
                elementTypePriority(snapshot.typeName) >= 4
            guard shouldCountAsChanged else { continue }

            elementCounts[snapshot.key, default: 0] += 1
            SuiraDataFlowLog.shared.onRecomposition(
                viewLabel: "\(snapshot.displayName) [\(snapshot.tag)]",
                at: timestamp
            )
        }

        previousViewNodeSignatures[screenLabel] = current
    }

    private func elementTypePriority(_ rawTypeName: String) -> Int {
        let typeName = rawTypeName.lowercased()
        if typeName.contains("textfield") || typeName.contains("securefield") || typeName.contains("texteditor") {
            return 6
        }
        if typeName.contains("toggle") || typeName.contains("picker") || typeName.contains("slider") || typeName.contains("stepper") {
            return 5
        }
        if typeName.contains("button") || typeName.contains("navigationlink") {
            return 4
        }
        if typeName.contains("image") || typeName.contains("text") {
            return 3
        }
        if typeName.contains("scrollview") || typeName.contains("list") || typeName.contains("lazy") {
            return 2
        }
        return 1
    }
}

private final class RecompositionHierarchyBuilderNode {
    let title: String
    let label: String
    let depth: Int

    private var childrenByTitle: [String: RecompositionHierarchyBuilderNode] = [:]
    private var childOrder: [String] = []

    init(title: String, label: String, depth: Int) {
        self.title = title
        self.label = label
        self.depth = depth
    }

    var orderedChildren: [RecompositionHierarchyBuilderNode] {
        childOrder.compactMap { childrenByTitle[$0] }
    }

    func child(title: String, label: String, depth: Int) -> RecompositionHierarchyBuilderNode {
        if let existing = childrenByTitle[title] {
            return existing
        }

        let node = RecompositionHierarchyBuilderNode(title: title, label: label, depth: depth)
        childrenByTitle[title] = node
        childOrder.append(title)
        return node
    }
}
