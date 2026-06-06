//
//  RefactoringProblemsTestView.swift
//  SUIRAExample
//
//  Created by Павел Калинин on 10.05.2026.
//
import SwiftUI
import SUIRA

struct RefactoringProblemsTestView: View {
    @State private var tick = 0
    @State private var hotCounter = 0
    @State private var volatileIdentity = UUID()
    @State private var workloadSeed = 0
    @State private var broadState = DemoBroadState.initial
    @State private var isRunning = false

    var body: some View {
        List {
            Section("Управление демонстрацией") {
                Button(isRunning ? "Серия выполняется..." : "Запустить 10 шумных обновлений") {
                    runProblemBurst()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .accessibilityIdentifier("RunRecompositionProblemsDemoButton")

                Text("Тиков: \(tick)")
                    .font(.headline.monospacedDigit())

                Text("После серии откройте SUIRA: вкладка рекомпозиций должна показать P1 для ProblemsDemo.Screen и ProblemsDemo.HotCounter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("1. Горячий контейнер") {
                HotCounterPanel(counter: hotCounter, volatileIdentity: volatileIdentity)
            }

            Section("2. Широкая модель состояния") {
                WideStatePanel(state: broadState)
            }

            Section("3. Тяжёлая синхронная работа") {
                ExpensiveBodyPanel(seed: workloadSeed)
            }

            Section("4. Дочерний блок без причины") {
                StaticButRebuiltPanel(parentTick: tick)
            }
        }
        .navigationTitle("Recomposition Problems")
        .suiraDependencyProbe("broadState", value: broadState)
        .trackRecomposition("ProblemsDemo.Screen")
    }

    private func runProblemBurst() {
        guard !isRunning else { return }
        isRunning = true

        Task { @MainActor in
            for step in 1...10 {
                SuiraDataFlow.mutation("tick", detail: "\(tick) -> \(step)")
                tick = step

                SuiraDataFlow.mutation("hotCounter", detail: "\(hotCounter) -> \(hotCounter + 1)")
                hotCounter += 1

                SuiraDataFlow.mutation("workloadSeed", detail: "\(workloadSeed) -> \(workloadSeed + 1)")
                workloadSeed += 1

                SuiraDataFlow.mutation("volatileIdentity", detail: "new UUID for HotCounterPanel.id")
                volatileIdentity = UUID()

                SuiraDataFlow.mutation("broadState", detail: "advance(step: \(step))")
                broadState.advance(step: step)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            isRunning = false
        }
    }
}

private struct HotCounterPanel: View {
    let counter: Int
    let volatileIdentity: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Контейнер получает каждое обновление и пересоздаёт identity.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Hot counter: \(counter)")
                .font(.headline)
                .monospacedDigit()

            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { index in
                    Text("\(counter + index)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 34, height: 28)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 4)
        .id(volatileIdentity)
        .suiraTrackId("ProblemsDemo.HotCounter.Identity", id: volatileIdentity)
        .trackRecomposition("ProblemsDemo.HotCounter")
    }
}

private struct WideStatePanel: View {
    let state: DemoBroadState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Вью получает модель целиком: \(state.rows.count) строк, \(state.metrics.count) метрик, \(state.flags.count) флагов.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                statusPill("Version", "\(state.version)")
                statusPill("Unread", "\(state.unreadCount)")
                statusPill("Mode", state.selectedMode)
            }

            ForEach(state.metrics.prefix(4)) { metric in
                HStack {
                    Text(metric.title)
                    Spacer()
                    Text("\(metric.value)")
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ExpensiveBodyPanel: View {
    let seed: Int

    var body: some View {
        let heavyResult = performHeavyCalculation(seed: seed)

        VStack(alignment: .leading, spacing: 8) {
            Text("Синхронный расчёт выполняется прямо во время построения body.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Checksum: \(heavyResult)")
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func performHeavyCalculation(seed: Int) -> Int {
        var sum = 0
        let limit = 450_000 + (seed % 3) * 120_000
        for value in 0..<limit {
            sum = (sum &+ value &+ seed) % 1_000_003
        }
        return sum
    }
}

private struct StaticButRebuiltPanel: View {
    let parentTick: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Родительский tick меняется, хотя карточка ниже всегда показывает одно и то же.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Parent tick: \(parentTick)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            StaticPayloadCard(parentTick: parentTick)
                .suiraTrackEquatable("ProblemsDemo.StaticPayload.Equatable")
        }
        .padding(.vertical, 4)
    }
}

private struct StaticPayloadCard: View, Equatable {
    let parentTick: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }

    var body: some View {
        Text("Static payload")
            .font(.subheadline.weight(.medium))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DemoBroadState: Equatable {
    var version: Int
    var userName: String
    var unreadCount: Int
    var selectedMode: String
    var flags: [Bool]
    var rows: [DemoRow]
    var metrics: [DemoMetric]
    var notifications: [String]
    var lastSyncDescription: String
    var debugNotes: [String]

    static let initial = DemoBroadState(
        version: 0,
        userName: "Demo User",
        unreadCount: 3,
        selectedMode: "Live",
        flags: [true, false, true, true, false, false, true, false],
        rows: (1...14).map { DemoRow(title: "Row \($0)", subtitle: "Cached value \($0)") },
        metrics: [
            DemoMetric(title: "CPU", value: 18),
            DemoMetric(title: "Memory", value: 42),
            DemoMetric(title: "Network", value: 7),
            DemoMetric(title: "Queue", value: 3),
            DemoMetric(title: "Cache", value: 91)
        ],
        notifications: ["Welcome", "Refresh pending", "Sync complete"],
        lastSyncDescription: "not started",
        debugNotes: ["wide-state", "fan-out", "identity-reset", "body-work"]
    )

    mutating func advance(step: Int) {
        version = step
        unreadCount = 3 + step
        selectedMode = step.isMultiple(of: 2) ? "Live" : "Replay"
        flags = flags.enumerated().map { index, value in
            index == step % max(flags.count, 1) ? !value : value
        }
        metrics = metrics.enumerated().map { index, metric in
            DemoMetric(title: metric.title, value: metric.value + step + index)
        }
        rows = rows.enumerated().map { index, row in
            DemoRow(title: row.title, subtitle: "tick \(step), item \(index + 1)")
        }
        notifications.append("tick \(step)")
        if notifications.count > 8 {
            notifications.removeFirst(notifications.count - 8)
        }
        lastSyncDescription = Date().formatted(date: .omitted, time: .standard)
        debugNotes.append("mutation-\(step)")
        if debugNotes.count > 12 {
            debugNotes.removeFirst(debugNotes.count - 12)
        }
    }
}

private struct DemoRow: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String
}

private struct DemoMetric: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var value: Int
}

#Preview {
    NavigationView {
        RefactoringProblemsTestView()
    }
}
