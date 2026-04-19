import SwiftUI

public extension Binding {
    /// Перед записью в `Binding` регистрирует мутацию с ярлыком `source` (для вкладки «Поток данных»).
    func suiraMutationSource(_ source: String) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                SuiraDataFlow.mutation(source, detail: nil)
                wrappedValue = newValue
            }
        )
    }
}
