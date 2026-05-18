import SwiftUI

/// Подключает SUIRA **один раз** у корня сцены: пробрасывает `RecompositionStore` в окружение.
///
/// Важно: из‑за модели обновления SwiftUI родительский контейнер в `App` **не обязан** заново вызывать `body` при изменении `@State` внутри дочернего экрана, поэтому считать рекомпозиции «снаружи» экрана нельзя. На каждый **корневой экран** добавьте **одну** строку в конце его `body`, например:
/// `NavigationView { … }.trackRecomposition("ИмяЭкрана")`.
public struct SuiraTrackedRoot<Content: View>: View {
    private let store: RecompositionStore
    @ViewBuilder private let content: () -> Content

    /// - Parameter store: Хранилище; по умолчанию `shared`.
    public init(
        store: RecompositionStore? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.store = store ?? .shared
        self.content = content
    }

    public var body: some View {
        content()
            .environment(\.suiraRecompositionStore, store)
    }
}

public extension View {
    /// Пробрасывает `store` в окружение — эквивалент `SuiraTrackedRoot { self }`.
    func suiraTrackedRoot(store: RecompositionStore? = nil) -> some View {
        SuiraTrackedRoot(store: store) { self }
    }
}
