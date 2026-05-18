//
//  SuiraOptimizationTracker.swift
//  SUIRA
//
//  Created by Павел Калинин on 10.05.2026.
//
import Foundation

/// Журнал вызовов == и изменений .id() для вкладки «Оптимизация».
public final class SuiraOptimizationTracker: @unchecked Sendable {
    public static let shared = SuiraOptimizationTracker()
    private let lock = NSLock()

    public struct EquatableEvent: Identifiable, Sendable {
        public let id: UUID
        public let label: String
        public let timestamp: Date
        public let isEqual: Bool
    }

    public struct IdChangeEvent: Identifiable, Sendable {
        public let id: UUID
        public let label: String
        public let timestamp: Date
        public let oldId: String?
        public let newId: String
    }

    private var equatableEvents: [EquatableEvent] = []
    private var idEvents: [IdChangeEvent] = []
    private let maxEvents = 300

    private init() {}

    public func recordEquatable(label: String, isEqual: Bool) {
        lock.lock(); defer { lock.unlock() }
        equatableEvents.append(EquatableEvent(id: UUID(), label: label, timestamp: .now, isEqual: isEqual))
        if equatableEvents.count > maxEvents { equatableEvents.removeFirst(equatableEvents.count - maxEvents) }
    }

    public func recordIdChange(label: String, oldId: String?, newId: String) {
        lock.lock(); defer { lock.unlock() }
        idEvents.append(IdChangeEvent(id: UUID(), label: label, timestamp: .now, oldId: oldId, newId: newId))
        if idEvents.count > maxEvents { idEvents.removeFirst(idEvents.count - maxEvents) }
    }

    public func recentEquatableEvents(limit: Int = 60) -> [EquatableEvent] {
        lock.lock(); defer { lock.unlock() }
        return Array(equatableEvents.suffix(limit))
    }

    public func recentIdEvents(limit: Int = 60) -> [IdChangeEvent] {
        lock.lock(); defer { lock.unlock() }
        return Array(idEvents.suffix(limit))
    }

    /// Возвращает лейблы, где == часто возвращает true, но view всё равно обновляется (признак избыточности)
    public func inefficientEquatableLabels(threshold: Int = 3) -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        var trueCounts: [String: Int] = [:]
        for e in equatableEvents where e.isEqual {
            trueCounts[e.label, default: 0] += 1
        }
        return trueCounts.filter { $0.value >= threshold }
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        equatableEvents.removeAll(keepingCapacity: false)
        idEvents.removeAll(keepingCapacity: false)
    }
}
