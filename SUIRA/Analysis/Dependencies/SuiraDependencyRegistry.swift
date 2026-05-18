import Foundation

/// Снимки значений для вкладки «Зависимости»: замыкание обновляется при каждом проходе `body` пробы (ожидается вызов с главного потока / MainActor).
public final class SuiraDependencyRegistry {
    public static let shared = SuiraDependencyRegistry()

    private struct Entry {
        var label: String
        var snapshot: () -> Any
    }

    private var entries: [Entry] = []
    private var indexByLabel: [String: Int] = [:]

    private init() {}

    /// Последний снимок с данным ярлыком перезаписывает предыдущий.
    public func upsertSnapshot(label: String, snapshot: @escaping () -> Any) {
        if let i = indexByLabel[label] {
            entries[i].snapshot = snapshot
        } else {
            indexByLabel[label] = entries.count
            entries.append(Entry(label: label, snapshot: snapshot))
        }
    }

    public func removeAll() {
        entries.removeAll(keepingCapacity: false)
        indexByLabel.removeAll(keepingCapacity: false)
    }

    /// Пары (ярлык, актуальное значение) для построения дерева `Mirror`.
    public func resolvedRoots() -> [(label: String, value: Any)] {
        entries.map { ($0.label, $0.snapshot()) }
    }
}
