import Combine
import Foundation
import QuartzCore
import UIKit
import Darwin

@MainActor
final class SuiraPerformanceMonitor: ObservableObject {
    struct Snapshot: Sendable {
        let currentFPS: Double
        let averageFPS: Double
        let droppedFrames: Int
        let frameOverruns: Int
        let memoryUsageMB: Double
        let targetFPS: Int

        var performanceScore: Int {
            var score = 100

            if averageFPS < 58 { score -= 10 }
            if averageFPS < 55 { score -= 15 }
            if averageFPS < 50 { score -= 20 }

            if droppedFrames >= 3 { score -= 10 }
            if droppedFrames >= 10 { score -= 15 }

            if memoryUsageMB >= 600 { score -= 10 }
            if memoryUsageMB >= 1024 { score -= 15 }

            return max(0, min(100, score))
        }
    }

    static let shared = SuiraPerformanceMonitor()

    @Published private(set) var snapshot: Snapshot

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var retainCount = 0
    private var fpsSamples: [Double] = []
    private var droppedFrames = 0
    private var frameOverruns = 0
    private var lastMetricsUpdateTimestamp: CFTimeInterval = 0
    private var cachedMemoryUsageMB: Double = 0

    private let sampleLimit = 180

    private init() {
        snapshot = Self.makeSnapshot(
            fpsSamples: [],
            droppedFrames: 0,
            frameOverruns: 0,
            memoryUsageMB: 0
        )
    }

    private func currentSnapshot() -> Snapshot {
        Self.makeSnapshot(
            fpsSamples: fpsSamples,
            droppedFrames: droppedFrames,
            frameOverruns: frameOverruns,
            memoryUsageMB: cachedMemoryUsageMB
        )
    }

    private static func makeSnapshot(
        fpsSamples: [Double],
        droppedFrames: Int,
        frameOverruns: Int,
        memoryUsageMB: Double
    ) -> Snapshot {
        let targetFPS = max(Self.maximumFramesPerSecond, 60)
        let currentFPS = fpsSamples.last ?? Double(targetFPS)
        let averageFPS = fpsSamples.isEmpty
            ? Double(targetFPS)
            : fpsSamples.reduce(0, +) / Double(fpsSamples.count)

        return Snapshot(
            currentFPS: currentFPS,
            averageFPS: averageFPS,
            droppedFrames: droppedFrames,
            frameOverruns: frameOverruns,
            memoryUsageMB: memoryUsageMB,
            targetFPS: targetFPS
        )
    }

    func retain() {
        retainCount += 1
        guard displayLink == nil else { return }
        start()
    }

    func release() {
        retainCount = max(0, retainCount - 1)
        guard retainCount == 0 else { return }
        stop()
    }

    func reset() {
        lastTimestamp = nil
        fpsSamples.removeAll(keepingCapacity: true)
        droppedFrames = 0
        frameOverruns = 0
        cachedMemoryUsageMB = 0
        lastMetricsUpdateTimestamp = 0
        snapshot = currentSnapshot()
    }

    private func start() {
        let link = CADisplayLink(target: self, selector: #selector(onFrame(_:)))
        if #available(iOS 15.0, macCatalyst 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: Float(Self.maximumFramesPerSecond),
                preferred: Float(Self.maximumFramesPerSecond)
            )
        } else {
            link.preferredFramesPerSecond = Self.maximumFramesPerSecond
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc
    private func onFrame(_ link: CADisplayLink) {
        let targetFPS = Double(max(link.preferredFramesPerSecond, Self.maximumFramesPerSecond, 60))
        let targetFrameDuration = 1.0 / targetFPS

        defer {
            lastTimestamp = link.timestamp
        }

        guard let lastTimestamp else {
            if cachedMemoryUsageMB == 0 {
                cachedMemoryUsageMB = Self.readMemoryUsageMB()
                publishSnapshot()
            }
            return
        }

        let delta = max(link.timestamp - lastTimestamp, 0.0001)
        let currentFPS = min(targetFPS, 1.0 / delta)
        fpsSamples.append(currentFPS)
        if fpsSamples.count > sampleLimit {
            fpsSamples.removeFirst(fpsSamples.count - sampleLimit)
        }

        if delta > targetFrameDuration * 1.08 {
            frameOverruns += 1
            let missedFrames = max(Int((delta / targetFrameDuration).rounded(.down)) - 1, 0)
            droppedFrames += missedFrames
        }

        if link.timestamp - lastMetricsUpdateTimestamp >= 1.0 {
            cachedMemoryUsageMB = Self.readMemoryUsageMB()
            lastMetricsUpdateTimestamp = link.timestamp
        }

        publishSnapshot()
    }

    private func publishSnapshot() {
        snapshot = currentSnapshot()
    }

    nonisolated private static func readMemoryUsageMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    nonisolated private static var maximumFramesPerSecond: Int {
        UIScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60
    }
}
