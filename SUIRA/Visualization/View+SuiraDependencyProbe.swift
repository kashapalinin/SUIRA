import SwiftUI

private struct SuiraDependencyProbeUpdater<Value>: View {
    let label: String
    let value: Value

    var body: some View {
        let snapshot: () -> Any = { value as Any }
        let _ = SuiraDependencyRegistry.shared.upsertSnapshot(label: label, snapshot: snapshot)
        return Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Регистрирует значение для вкладки «Зависимости»: при каждом пересчёте `body` обновляется замыкание снимка (актуально для struct и value types).
    ///
    /// Показывает **структуру полей через `Mirror`**, а не официальный граф зависимостей SwiftUI (он закрыт).
    func suiraDependencyProbe<Value>(_ label: String, value: Value) -> some View {
        background(alignment: .center) {
            SuiraDependencyProbeUpdater(label: label, value: value)
                .allowsHitTesting(false)
        }
    }
}
