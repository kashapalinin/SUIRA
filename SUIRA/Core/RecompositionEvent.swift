import Foundation

/// A single recorded SwiftUI body (re)evaluation for a tracked view.
public struct RecompositionEvent: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Human-readable or auto-generated label for the view site.
    public let viewLabel: String
    /// Monotonic time when the event was recorded.
    public let timestamp: Date
    /// Time spent building the subtree inside the tracker, if measured.
    public let bodyDuration: TimeInterval?

    public init(
        id: UUID = UUID(),
        viewLabel: String,
        timestamp: Date = .now,
        bodyDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.viewLabel = viewLabel
        self.timestamp = timestamp
        self.bodyDuration = bodyDuration
    }
}
