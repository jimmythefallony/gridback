import AppKit
import Darwin
import GridBackCore
import os

/// Reads the process once.
///
/// CPU time is the process clock, which includes threads that are still running.
/// The task's basic info only counts threads that have already exited, so it
/// would miss the time of a live app. Memory is `task_info` `phys_footprint`,
/// the figure Activity Monitor shows.
enum ProcessProbe {
    static func read() -> ProcessSample {
        ProcessSample(
            cpuNanos: clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID),
            wallNanos: wallNanos(),
            footprintBytes: physicalFootprint()
        )
    }

    /// Monotonic time that stays still while the Mac is asleep, so a night
    /// asleep is not reported as a long idle at zero CPU. This is not a
    /// CPU or memory reading. The first committed frame uses it for the open time.
    static func wallNanos() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    private static func physicalFootprint() -> UInt64 {
        var info = task_vm_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self(), task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
}

/// One open, from the trigger to the first committed frame, plus the CPU and
/// memory around it.
///
/// The Points of Interest interval is named GridOpen. It starts in the hotkey
/// callback, or in `show()` for any other trigger, and it ends from a one-shot
/// run-loop observer once AppKit is about to sleep, which is when the frame
/// has been committed. That observer is not a timer and it does not poll.
/// CPU time and the memory footprint are read only when an open starts and
/// when the grid closes. The notice line is written at close, when those
/// numbers exist. Nothing here is sent off the Mac.
final class GridOpenTrace {
    static let shared = GridOpenTrace()

    /// Builds the signposter and the logger before the first open, so that
    /// work is not part of a measured open.
    static func prepare() {
        _ = shared
    }

    private let signposter = OSSignposter(
        subsystem: "com.jimmythefallony.GridBack",
        category: .pointsOfInterest
    )
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "perf")
    private let lock = NSLock()
    private var phase = GridOpenSession.start()
    private var interval: OSSignpostIntervalState?
    /// Main thread only. A one-shot observer waiting for the frame to commit.
    private var frameObserver: CFRunLoopObserver?

    /// Hotkey callback, which is not the main thread. Starts the interval only
    /// when the grid is closed, before the hop onto the main thread.
    func hotkeyArrived() {
        guard isIdle() else { return }
        let sample = ProcessProbe.read()
        take(.trigger(.hotkey, sample))
    }

    /// `show()` for a trigger that is not the hotkey. A hotkey open is already underway.
    func showTriggerArrived() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isIdle() else { return }
        let sample = ProcessProbe.read()
        take(.trigger(.menu, sample))
    }

    func notePanel(created: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        take(.temperature(created ? .cold : .warm))
    }

    /// Call after the panel has been ordered front. The interval ends on the
    /// next commit, not at this return.
    func panelOrderedFront() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isOpening, frameObserver == nil else { return }
        guard let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            false,
            CFIndex.max,
            { [weak self] _, _ in
                self?.firstFrameCommitted()
            }
        ) else { return }
        frameObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, CFRunLoopMode.commonModes)
    }

    func gridClosed() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isIdle() else { return }
        removeFrameObserver()
        let sample = ProcessProbe.read()
        take(.close(sample))
    }

    /// `show()` returned before the panel could appear. Does not log a line.
    func abandonOpening() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isOpening else { return }
        removeFrameObserver()
        let sample = ProcessProbe.read()
        take(.close(sample))
    }

    private func firstFrameCommitted() {
        // The observer is one-shot. The run loop drops it after this call, so
        // it is not removed from inside the callback.
        frameObserver = nil
        let wall = ProcessProbe.wallNanos()
        take(.frameCommitted(wallNanos: wall))
    }

    private func removeFrameObserver() {
        guard let frameObserver else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), frameObserver, CFRunLoopMode.commonModes)
        self.frameObserver = nil
    }

    private var isOpening: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .opening = phase { return true }
        return false
    }

    private func isIdle() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .idle = phase { return true }
        return false
    }

    private func take(_ event: GridOpenEvent) {
        lock.lock()
        let steps = GridOpenSession.advance(&phase, event)
        let lines = applySignposts(steps)
        lock.unlock()
        for line in lines {
            // One public string. The line is only cold/warm, hotkey/menu, and
            // numbers. A private string would be stored as "<private>".
            log.notice("\(line, privacy: .public)")
        }
    }

    private func applySignposts(_ steps: [GridOpenStep]) -> [String] {
        var lines: [String] = []
        for step in steps {
            switch step {
            case .beginInterval(let trigger):
                if let interval {
                    finish(interval, .cancelled)
                }
                interval = start(trigger)
            case .endInterval(let end):
                if let interval {
                    finish(interval, end)
                    self.interval = nil
                }
            case .log(let measurement):
                lines.append(PerfLogLine.format(measurement))
            }
        }
        return lines
    }

    private func start(_ trigger: OpenTrigger) -> OSSignpostIntervalState {
        switch trigger {
        case .hotkey:
            return signposter.beginInterval("GridOpen", "hotkey")
        case .menu:
            return signposter.beginInterval("GridOpen", "menu")
        }
    }

    private func finish(_ state: OSSignpostIntervalState, _ end: GridOpenStep.End) {
        switch end {
        case .committed(.cold):
            signposter.endInterval("GridOpen", state, "cold")
        case .committed(.warm):
            signposter.endInterval("GridOpen", state, "warm")
        case .cancelled:
            signposter.endInterval("GridOpen", state, "cancelled")
        }
    }
}
