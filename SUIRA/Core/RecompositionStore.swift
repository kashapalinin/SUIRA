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
    /// Shared instance used when no environment override is set.
    public static let shared = RecompositionStore()

    /// When false, `record` does nothing (near-zero overhead).
    @Published public var isEnabled: Bool = true

    /// Most recent events, newest last. Size is bounded by `maxEvents`.
    @Published public private(set) var events: [RecompositionEvent] = []

    /// Total number of recompositions per label since last `reset()`.
    @Published public private(set) var countsByLabel: [String: Int] = [:]

    /// Upper bound for `events` to cap memory use.
    public var maxEvents: Int = 500 {
        didSet { trimEventsIfNeeded() }
    }

    public init() {}

    public func reset() {
        events.removeAll(keepingCapacity: false)
        countsByLabel.removeAll(keepingCapacity: false)
    }

    /// Records one recomposition for `viewLabel`.
    public func record(viewLabel: String, bodyDuration: TimeInterval? = nil) {
        guard isEnabled else { return }

        let event = RecompositionEvent(viewLabel: viewLabel, bodyDuration: bodyDuration)
        events.append(event)
        trimEventsIfNeeded()

        countsByLabel[viewLabel, default: 0] += 1
    }

    /// Total recompositions across all labels.
    public var totalCount: Int {
        countsByLabel.values.reduce(0, +)
    }

    private func trimEventsIfNeeded() {
        guard maxEvents > 0, events.count > maxEvents else { return }
        events.removeFirst(events.count - maxEvents)
    }
}
