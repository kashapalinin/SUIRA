//
//  SuiraHighlightEnabledKey.swift
//  SUIRA
//
//  Created by Павел Калинин on 10.05.2026.
//
import SwiftUI

private struct SuiraHighlightEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    /// Глобальный флаг подсветки рекомпозиций. Включается один раз у корня.
    var suiraHighlightEnabled: Bool {
        get { self[SuiraHighlightEnabledKey.self] }
        set { self[SuiraHighlightEnabledKey.self] = newValue }
    }
}

public extension View {
    /// Включает/выключает подсветку рекомпозиций для всего дерева.
    func suiraEnableHighlights(_ enabled: Bool = true) -> some View {
        environment(\.suiraHighlightEnabled, enabled)
    }
}
