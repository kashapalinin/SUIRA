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
        let cpuUsagePercent: Double
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

            if cpuUsagePercent >= 70 { score -= 10 }
            if cpuUsagePercent >= 90 { score -= 15 }

            return max(0, min(100, score))
        }
    }

    static let shared = SuiraPerformanceMonitor()

    @Published private(set) var snapshot: Snapshot

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var retainCount = 0
    private var fpsSamples: [Double] = []
    private var frameIntervalSamples: [CFTimeInterval] = []
    private var droppedFrames = 0
    private var frameOverruns = 0
    private var lastMetricsUpdateTimestamp: CFTimeInterval = 0
    private var lastSnapshotPublishTimestamp: CFTimeInterval = 0
    private var cachedMemoryUsageMB: Double = 0
    private var cachedCPUUsagePercent: Double = 0

    private let sampleLimit = 180
    private let intervalSampleLimit = 90
    private let minimumBaselineSampleCount = 8
    private let snapshotPublishInterval: CFTimeInterval = 0.25
    private let longPauseThreshold: CFTimeInterval = 0.5
    private let overrunTolerance = 1.45

    private init() {
        snapshot = Self.makeSnapshot(
            fpsSamples: [],
            droppedFrames: 0,
            frameOverruns: 0,
            memoryUsageMB: 0,
            cpuUsagePercent: 0
        )
    }

    private func currentSnapshot() -> Snapshot {
        Self.makeSnapshot(
            fpsSamples: fpsSamples,
            droppedFrames: droppedFrames,
            frameOverruns: frameOverruns,
            memoryUsageMB: cachedMemoryUsageMB,
            cpuUsagePercent: cachedCPUUsagePercent
        )
    }

    private static func makeSnapshot(
        fpsSamples: [Double],
        droppedFrames: Int,
        frameOverruns: Int,
        memoryUsageMB: Double,
        cpuUsagePercent: Double
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
            cpuUsagePercent: cpuUsagePercent,
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
        frameIntervalSamples.removeAll(keepingCapacity: true)
        droppedFrames = 0
        frameOverruns = 0
        cachedMemoryUsageMB = 0
        cachedCPUUsagePercent = 0
        lastMetricsUpdateTimestamp = 0
        lastSnapshotPublishTimestamp = 0
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
        frameIntervalSamples.removeAll(keepingCapacity: true)
    }

    @objc
    private func onFrame(_ link: CADisplayLink) {
        let targetFPS = Double(max(link.preferredFramesPerSecond, Self.maximumFramesPerSecond, 60))
        let nominalFrameDuration = Self.nominalFrameDuration(for: link, targetFPS: targetFPS)

        defer {
            lastTimestamp = link.timestamp
        }

        guard let lastTimestamp else {
            if cachedMemoryUsageMB == 0 {
                cachedMemoryUsageMB = Self.readMemoryUsageMB()
                cachedCPUUsagePercent = Self.readCPUUsagePercent()
                publishSnapshot()
            }
            return
        }

        let delta = max(link.timestamp - lastTimestamp, 0.0001)
        guard UIApplication.shared.applicationState == .active, delta <= longPauseThreshold else {
            frameIntervalSamples.removeAll(keepingCapacity: true)
            if shouldPublishSnapshot(at: link.timestamp) {
                publishSnapshot()
            }
            return
        }

        let currentFPS = min(targetFPS, 1.0 / delta)
        fpsSamples.append(currentFPS)
        if fpsSamples.count > sampleLimit {
            fpsSamples.removeFirst(fpsSamples.count - sampleLimit)
        }

        let baselineFrameDuration = baselineFrameDuration(defaultingTo: nominalFrameDuration)
        if shouldCountFrameDrop(delta: delta, baselineFrameDuration: baselineFrameDuration) {
            frameOverruns += 1
            let missedFrames = max(Int((delta / baselineFrameDuration).rounded(.down)) - 1, 0)
            droppedFrames += missedFrames
        }
        appendFrameInterval(delta)

        if link.timestamp - lastMetricsUpdateTimestamp >= 1.0 {
            cachedMemoryUsageMB = Self.readMemoryUsageMB()
            cachedCPUUsagePercent = Self.readCPUUsagePercent()
            lastMetricsUpdateTimestamp = link.timestamp
        }

        if shouldPublishSnapshot(at: link.timestamp) {
            publishSnapshot()
        }
    }

    private func publishSnapshot() {
        snapshot = currentSnapshot()
    }

    private func appendFrameInterval(_ interval: CFTimeInterval) {
        frameIntervalSamples.append(interval)
        if frameIntervalSamples.count > intervalSampleLimit {
            frameIntervalSamples.removeFirst(frameIntervalSamples.count - intervalSampleLimit)
        }
    }

    private func baselineFrameDuration(defaultingTo nominalFrameDuration: CFTimeInterval) -> CFTimeInterval {
        guard frameIntervalSamples.count >= minimumBaselineSampleCount else {
            return nominalFrameDuration
        }

        let sorted = frameIntervalSamples.sorted()
        let median = sorted[sorted.count / 2]
        return max(median, nominalFrameDuration)
    }

    private func shouldCountFrameDrop(delta: CFTimeInterval, baselineFrameDuration: CFTimeInterval) -> Bool {
        guard frameIntervalSamples.count >= minimumBaselineSampleCount else {
            return false
        }
        return delta > baselineFrameDuration * overrunTolerance
    }

    private func shouldPublishSnapshot(at timestamp: CFTimeInterval) -> Bool {
        guard timestamp - lastSnapshotPublishTimestamp >= snapshotPublishInterval else {
            return false
        }
        lastSnapshotPublishTimestamp = timestamp
        return true
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

    nonisolated private static func readCPUUsagePercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)

        let threadsResult = task_threads(mach_task_self_, &threadList, &threadCount)
        guard threadsResult == KERN_SUCCESS, let threadList else { return 0 }

        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), size)
        }

        var totalUsage: Double = 0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info_data_t()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)

            let infoResult = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    thread_info(
                        threadList[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        rebound,
                        &count
                    )
                }
            }

            guard infoResult == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 else {
                continue
            }

            totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }

        return totalUsage
    }

    private static var maximumFramesPerSecond: Int {
        60
    }

    private static func nominalFrameDuration(for link: CADisplayLink, targetFPS: Double) -> CFTimeInterval {
        let targetDuration = 1.0 / targetFPS
        let linkDuration = link.duration > 0 ? link.duration : 0
        let nextFrameDuration = link.targetTimestamp > link.timestamp
            ? link.targetTimestamp - link.timestamp
            : 0

        return max(targetDuration, linkDuration, nextFrameDuration)
    }
}
