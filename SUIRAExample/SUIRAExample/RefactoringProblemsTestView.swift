//
//  RefactoringProblemsTestView.swift
//  SUIRAExample
//
//  Created by Павел Калинин on 10.05.2026.
//
import SwiftUI
import SUIRA

// MARK: - Главный экран тестов
struct RefactoringProblemsTestView: View {
    @State private var triggerCount = 0
    @State private var sharedState = "Initial"
    @State private var unstableIdCounter = 0
    @State private var heavyTrigger = false
    @State private var equatableTimestamp = Date()

    var body: some View {
        List {
            Section("🎛 Управление тестами") {
                Button("🔥 Запустить все проблемы") {
                    SuiraDataFlow.mutation("TestRunner", detail: "Одновременный запуск 5 антипаттернов")
                    triggerCount += 1
                    sharedState = "Updated \(Date().formatted(date: .omitted, time: .standard))"
                    unstableIdCounter += 1
                    equatableTimestamp = Date()
                    heavyTrigger.toggle()
                }
                .buttonStyle(.borderedProminent)
                .trackRecomposition("Refactoring.TriggerButton")
                
                Text("Нажмите кнопку 3–5 раз, затем откройте инспектор SUIRA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("1. Нестабильный .id()") {
                UnstableIdDemo(changingId: unstableIdCounter)
            }

            Section("2. Неэффективный .equatable()") {
                InefficientEquatableDemo(timestamp: equatableTimestamp)
            }

            Section("3. Широкий охват состояния (Fan-out)") {
                WideStateFanOutDemo(sharedText: sharedState)
            }

            Section("4. Тяжёлый body") {
                HeavyBodyDemo(trigger: heavyTrigger)
            }

            Section("5. Избыточные обновления детей") {
                MissingEquatableDemo(parentTrigger: triggerCount)
            }
        }
        .navigationTitle("Проблемы рефакторинга")
        .trackRecomposition("RefactoringProblemsTestView")
    }
}

// MARK: - 1. Нестабильный .id()
private struct UnstableIdDemo: View {
    let changingId: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ID меняется при каждом нажатии → дерево пересоздаётся")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Текущий ID: \(changingId)")
                .font(.headline)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
        // Антипаттерн: .id() зависит от часто меняющегося значения
        .id(changingId)
        .suiraTrackId("UnstableIdDemo", id: changingId)
        .trackRecomposition("Refactoring.UnstableId")
    }
}

// MARK: - 2. Неэффективный .equatable()
private struct InefficientEquatableDemo: View, Equatable {
    let timestamp: Date
    
    // Антипаттерн: == игнорирует изменяющееся поле, возвращает true,
    // но родитель всё равно форсирует обновление layout-контекста
    static func == (lhs: Self, rhs: Self) -> Bool {
        let result = lhs.timestamp.timeIntervalSince1970 == rhs.timestamp.timeIntervalSince1970
        // SUIRA зафиксирует частые вызовы == и результат
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("equatable() вызывается, но не предотвращает обновления")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Timestamp: \(timestamp.formatted(date: .omitted, time: .standard))")
                .font(.headline)
        }
        .padding(.vertical, 4)
//        .suiraTrackEquatable("InefficientEquatableDemo")
        .trackRecomposition("Refactoring.InefficientEquatable")
    }
}

// MARK: - 3. Широкий охват состояния (Fan-out)
private struct WideStateFanOutDemo: View {
    let sharedText: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text("Одно состояние обновляет 5 независимых view")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                FanOutChild(text: sharedText, index: 1)
                FanOutChild(text: sharedText, index: 2)
                FanOutChild(text: sharedText, index: 3)
                FanOutChild(text: sharedText, index: 4)
                FanOutChild(text: sharedText, index: 5)
            }
        }
        .padding(.vertical, 4)
        .trackRecomposition("Refactoring.WideStateRoot")
    }
}

private struct FanOutChild: View {
    let text: String
    let index: Int
    
    var body: some View {
        Text("\(index): \(text)")
            .font(.caption.monospacedDigit())
            .padding(6)
            .background(.tertiary, in: RoundedRectangle(cornerRadius: 6))
            .trackRecomposition("Refactoring.FanOutChild.\(index)")
    }
}

// MARK: - 4. Тяжёлый body
private struct HeavyBodyDemo: View {
    let trigger: Bool
    
    var body: some View {
        // Антипаттерн: синхронные вычисления в body
        let heavyResult = performHeavyCalculation(trigger: trigger)
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Синхронный расчёт в body (~0.5–2 ms)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Результат: \(heavyResult)")
                .font(.headline)
        }
        .padding(.vertical, 4)
        .trackRecomposition("Refactoring.HeavyBody")
    }
    
    private func performHeavyCalculation(trigger: Bool) -> Int {
        var sum = 0
        // Намеренно тяжёлый цикл для генерации p95/max всплесков
        let limit = trigger ? 800_000 : 100_000
        for i in 0..<limit { sum += i }
        return sum
    }
}

// MARK: - 5. Избыточные обновления детей
private struct MissingEquatableDemo: View {
    let parentTrigger: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Родитель обновляется → ребёнок перерисовывается без причины")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            UnoptimizedChild(staticLabel: "Я не меняюсь, но body вызывается")
        }
        .padding(.vertical, 4)
        .trackRecomposition("Refactoring.MissingEquatableParent")
    }
}

private struct UnoptimizedChild: View {
    let staticLabel: String
    
    var body: some View {
        Text(staticLabel)
            .font(.subheadline)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .trackRecomposition("Refactoring.UnoptimizedChild")
    }
}

#Preview {
    NavigationView {
        RefactoringProblemsTestView()
    }
}
