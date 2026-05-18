//
//  SuiraEquatableProxy.swift
//  SUIRA
//
//  Created by Павел Калинин on 10.05.2026.
//
import SwiftUI

// MARK: - Equatable Proxy
private struct SuiraEquatableProxy<Content: View & Equatable>: View, Equatable {
    let label: String
    let content: Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        let result = lhs.content == rhs.content
        SuiraOptimizationTracker.shared.recordEquatable(label: lhs.label, isEqual: result)
        return result
    }

    var body: some View { content }
}

public extension View where Self: Equatable {
    /// Аналог .equatable(), но с логированием результата == в SuiraOptimizationTracker
    func suiraTrackEquatable(_ label: String) -> some View {
        SuiraEquatableProxy(label: label, content: self)
    }
}

// MARK: - ID Tracker
private struct SuiraIdTrackingModifier<ID: Hashable>: ViewModifier {
    let label: String
    let id: ID
    @State private var lastSeenId: String?

    func body(content: Content) -> some View {
        content
            .task(id: id) {
                let current = String(describing: id)
                if lastSeenId != current {
                    SuiraOptimizationTracker.shared.recordIdChange(label: label, oldId: lastSeenId, newId: current)
                    lastSeenId = current
                }
            }
    }
}

public extension View {
    /// Отслеживает изменения .id() и логирует их для анализа стабильности идентичности
    func suiraTrackId<ID: Hashable>(_ label: String, id: ID) -> some View {
        modifier(SuiraIdTrackingModifier(label: label, id: id))
    }
}
