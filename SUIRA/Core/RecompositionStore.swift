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

    private var previousScreenSnapshots: [String: SuiraValueSnapshot] = [:]
    private var previousDependencySnapshots: [String: SuiraValueSnapshot] = [:]
    private var previousViewNodeSignatures: [String: [String: String]] = [:]
    private var elementDescriptors: [String: ElementStats] = [:]
    private var resetGeneration: UInt64 = 0

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
        previousScreenSnapshots.removeAll(keepingCapacity: false)
        previousDependencySnapshots.removeAll(keepingCapacity: false)
        previousViewNodeSignatures.removeAll(keepingCapacity: false)
        elementDescriptors.removeAll(keepingCapacity: false)
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

        if !viewNodeSnapshots.isEmpty {
            recordElementChanges(
                screenLabel: viewLabel,
                nodeSnapshots: viewNodeSnapshots,
                timestamp: event.timestamp
            )
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
                    return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }
                return lhs > rhs
            }
            return $0.count > $1.count
        }
    }

    private func trimEventsIfNeeded() {
        guard maxEvents > 0, events.count > maxEvents else { return }
        events.removeFirst(events.count - maxEvents)
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
