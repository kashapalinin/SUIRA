import CoreFoundation
import SwiftUI

/// Wraps a subtree and records each time SwiftUI evaluates this part of the tree.
private struct RecompositionTrackedSubtree<Content: View>: View {
    let label: String
    let store: RecompositionStore?
    @ViewBuilder var content: () -> Content

    @Environment(\.suiraRecompositionStore) private var environmentStore

    private var activeStore: RecompositionStore {
        store ?? environmentStore ?? .shared
    }

    var body: some View {
        let start = CFAbsoluteTimeGetCurrent()
        let built = content()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        // Publishing (@Published) must not run during view updates; defer to next main turn.
        let store = activeStore
        let lbl = label
        DispatchQueue.main.async {
            store.record(viewLabel: lbl, bodyDuration: elapsed)
        }
        return built
    }
}

public extension View {
    /// Tracks each (re)evaluation of this view’s subtree: increments counters and appends an event.
    ///
    /// Avoid `@ObservedObject` / `@StateObject` on the **same** `RecompositionStore` inside a subtree
    /// wrapped by `trackRecomposition` (or above it): updates from `record` will re-enter `body` and
    /// inflate counts in a tight loop. Prefer polling (e.g. `TimelineView`), a separate store for UI, or
    /// keep observers outside tracked regions.
    ///
    /// - Parameters:
    ///   - label: Logical name; defaults to `fileID:line` for quick placement without naming.
    ///   - store: Optional store; defaults to environment `suiraRecompositionStore` or `RecompositionStore.shared`.
    @ViewBuilder
    func trackRecomposition(
        _ label: String? = nil,
        file: StaticString = #fileID,
        line: UInt = #line,
        store: RecompositionStore? = nil
    ) -> some View {
        let resolved = label.map { $0 } ?? "\(file):\(line)"
        RecompositionTrackedSubtree(label: resolved, store: store) { self }
    }
}
