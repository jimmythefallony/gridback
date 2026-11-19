import Foundation

/// One reading of the process. The app fills this in at open and at close.
public struct ProcessSample: Equatable, Sendable {
    /// Process CPU time, user and system together, in nanoseconds.
    public var cpuNanos: UInt64
    /// Monotonic time that does not move forward while the Mac is asleep, in nanoseconds.
    public var wallNanos: UInt64
    /// Physical memory footprint, in bytes. This is the number Activity Monitor shows.
    public var footprintBytes: UInt64

    public init(cpuNanos: UInt64, wallNanos: UInt64, footprintBytes: UInt64) {
        self.cpuNanos = cpuNanos
        self.wallNanos = wallNanos
        self.footprintBytes = footprintBytes
    }
}

/// How an open was requested. The log uses the raw value, and nothing else.
public enum OpenTrigger: String, Equatable, Sendable {
    case hotkey
    case menu
}

/// Cold is the first open, when the panel is created. Warm reuses the panel.
public enum OpenTemperature: String, Equatable, Sendable {
    case cold
    case warm
}

/// Pure arithmetic for one pair of readings. No clocks and no logging.
public enum ProcessLoad {
    /// CPU use between two readings, as a percent of one core.
    ///
    /// 100 means the process kept one core busy for the whole gap. Two busy
    /// cores report 200. Nil when the wall clock did not move forward, or the
    /// CPU clock went backwards.
    public static func cpuPercent(from earlier: ProcessSample, to later: ProcessSample) -> Double? {
        guard later.wallNanos > earlier.wallNanos else { return nil }
        guard later.cpuNanos >= earlier.cpuNanos else { return nil }
        let wall = later.wallNanos - earlier.wallNanos
        let cpu = later.cpuNanos - earlier.cpuNanos
        return Double(cpu) / Double(wall) * 100
    }

    /// Nearest megabyte. Half a megabyte rounds up.
    public static func megabytes(rounding bytes: UInt64) -> Int {
        let unit = UInt64(1024 * 1024)
        let rounded = (bytes + unit / 2) / unit
        guard rounded <= UInt64(Int.max) else { return Int.max }
        return Int(rounded)
    }

    /// Nearest millisecond. Nil when the later reading is earlier than the first.
    public static func milliseconds(from earlierWallNanos: UInt64, to laterWallNanos: UInt64) -> Int? {
        guard laterWallNanos >= earlierWallNanos else { return nil }
        let rounded = (laterWallNanos - earlierWallNanos + 500_000) / 1_000_000
        guard rounded <= UInt64(Int.max) else { return nil }
        return Int(rounded)
    }

    /// One decimal and a dot, then a percent sign. 6.25 becomes "6.3%".
    ///
    /// The decimal mark is always a dot, so a Mac set to another region still
    /// writes a line the summary script can read.
    public static func formatPercent(_ percent: Double) -> String {
        guard percent.isFinite else { return "0.0%" }
        let scaled = (percent * 10).rounded()
        guard scaled.isFinite, abs(scaled) <= Double(Int.max) else { return "0.0%" }
        let sign = scaled < 0 ? "-" : ""
        let digits = Int(abs(scaled))
        return "\(sign)\(digits / 10).\(digits % 10)%"
    }

    /// Whole milliseconds stay whole. A half stays one decimal, as in "80.5".
    public static func formatMilliseconds(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let nearest = value.rounded()
        if abs(value - nearest) < 0.000_000_1 {
            guard nearest.isFinite, abs(nearest) <= Double(Int.max) else { return "0" }
            return String(Int(nearest))
        }
        let scaled = (value * 10).rounded()
        guard scaled.isFinite, abs(scaled) <= Double(Int.max) else { return "0" }
        let sign = scaled < 0 ? "-" : ""
        let digits = Int(abs(scaled))
        return "\(sign)\(digits / 10).\(digits % 10)"
    }
}

/// The numbers written once the grid has opened and then closed.
public struct OpenMeasurement: Equatable, Sendable {
    public var temperature: OpenTemperature
    public var milliseconds: Int
    /// Nil on the first open, which has no earlier close to compare with.
    public var idleCPUPercent: Double?
    public var openCPUPercent: Double
    public var memoryOpenMB: Int
    public var memoryCloseMB: Int
    public var trigger: OpenTrigger

    public init(
        temperature: OpenTemperature,
        milliseconds: Int,
        idleCPUPercent: Double?,
        openCPUPercent: Double,
        memoryOpenMB: Int,
        memoryCloseMB: Int,
        trigger: OpenTrigger
    ) {
        self.temperature = temperature
        self.milliseconds = milliseconds
        self.idleCPUPercent = idleCPUPercent
        self.openCPUPercent = openCPUPercent
        self.memoryOpenMB = memoryOpenMB
        self.memoryCloseMB = memoryCloseMB
        self.trigger = trigger
    }
}

public struct OpenTiming: Equatable, Sendable {
    public var medianMilliseconds: Double
    public var worstMilliseconds: Int
    public var count: Int

    public init(medianMilliseconds: Double, worstMilliseconds: Int, count: Int) {
        self.medianMilliseconds = medianMilliseconds
        self.worstMilliseconds = worstMilliseconds
        self.count = count
    }
}

public struct OpenSummary: Equatable, Sendable {
    public var cold: OpenTiming?
    public var warm: OpenTiming?
    public var averageIdleCPUPercent: Double?
    public var averageOpenCPUPercent: Double?
    public var peakMemoryMB: Int?

    public init(
        cold: OpenTiming?,
        warm: OpenTiming?,
        averageIdleCPUPercent: Double?,
        averageOpenCPUPercent: Double?,
        peakMemoryMB: Int?
    ) {
        self.cold = cold
        self.warm = warm
        self.averageIdleCPUPercent = averageIdleCPUPercent
        self.averageOpenCPUPercent = averageOpenCPUPercent
        self.peakMemoryMB = peakMemoryMB
    }
}

public enum OpenSummaryMath {
    /// Middle value. An even count uses the mean of the two middle values.
    public static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return Double(sorted[mid])
        }
        return (Double(sorted[mid - 1]) + Double(sorted[mid])) / 2
    }

    public static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Cold and warm are kept apart. Idle CPU skips opens that have none.
    /// Peak memory is the highest open or close reading.
    public static func summarize(_ measurements: [OpenMeasurement]) -> OpenSummary {
        let idles = measurements.compactMap(\.idleCPUPercent)
        let opens = measurements.map(\.openCPUPercent)
        let memories = measurements.flatMap { [$0.memoryOpenMB, $0.memoryCloseMB] }
        return OpenSummary(
            cold: timing(.cold, in: measurements),
            warm: timing(.warm, in: measurements),
            averageIdleCPUPercent: average(idles),
            averageOpenCPUPercent: average(opens),
            peakMemoryMB: memories.max()
        )
    }

    private static func timing(_ temperature: OpenTemperature, in measurements: [OpenMeasurement]) -> OpenTiming? {
        let values = measurements.filter { $0.temperature == temperature }.map(\.milliseconds)
        guard let median = median(values), let worst = values.max() else { return nil }
        return OpenTiming(medianMilliseconds: median, worstMilliseconds: worst, count: values.count)
    }
}

/// The sentences `scripts/perf-report.sh` prints. The script repeats this wording.
public enum OpenSummaryText {
    public static func render(_ summary: OpenSummary, last window: String) -> String {
        guard summary.cold != nil || summary.warm != nil else {
            return "No GridBack open measurements in the last \(window)."
        }
        return [
            "GridBack open measurements, last \(window)",
            timingLine("cold", summary.cold),
            timingLine("warm", summary.warm),
            "average idle CPU: \(percent(summary.averageIdleCPUPercent))",
            "average open CPU: \(percent(summary.averageOpenCPUPercent))",
            "peak memory: \(memory(summary.peakMemoryMB))"
        ].joined(separator: "\n")
    }

    private static func timingLine(_ name: String, _ timing: OpenTiming?) -> String {
        guard let timing else { return "\(name) open: none" }
        let median = ProcessLoad.formatMilliseconds(timing.medianMilliseconds)
        return "\(name) open: median \(median) ms, worst \(timing.worstMilliseconds) ms, count \(timing.count)"
    }

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "none" }
        return ProcessLoad.formatPercent(value)
    }

    private static func memory(_ megabytes: Int?) -> String {
        guard let megabytes else { return "none" }
        return "\(megabytes) MB"
    }
}

/// One log line. The words are fixed so the summary script can find them.
public enum PerfLogLine {
    public static func format(_ measurement: OpenMeasurement) -> String {
        let idle: String
        if let idleCPU = measurement.idleCPUPercent {
            idle = ProcessLoad.formatPercent(idleCPU)
        } else {
            idle = "none"
        }
        let openCPU = ProcessLoad.formatPercent(measurement.openCPUPercent)
        return "open \(measurement.temperature.rawValue) ms=\(measurement.milliseconds) idleCPU=\(idle) openCPU=\(openCPU) memOpenMB=\(measurement.memoryOpenMB) memCloseMB=\(measurement.memoryCloseMB) trigger=\(measurement.trigger.rawValue)"
    }

    /// Reads one measurement out of a log line. A prefix from `log show` is ignored.
    /// Returns nil when the line is not one of these measurements.
    public static func parse(_ line: String) -> OpenMeasurement? {
        let temperature: OpenTemperature
        let tail: Substring
        if let range = line.range(of: "open cold ") {
            temperature = .cold
            tail = line[range.upperBound...]
        } else if let range = line.range(of: "open warm ") {
            temperature = .warm
            tail = line[range.upperBound...]
        } else {
            return nil
        }

        var milliseconds: Int?
        var sawIdle = false
        var idleCPU: Double?
        var openCPU: Double?
        var memoryOpen: Int?
        var memoryClose: Int?
        var trigger: OpenTrigger?

        for token in tail.split(separator: " ") {
            guard let separator = token.firstIndex(of: "=") else { continue }
            let key = token[..<separator]
            let value = token[token.index(after: separator)...]
            switch key {
            case "ms":
                guard milliseconds == nil, let parsed = wholeNumber(value) else { return nil }
                milliseconds = parsed
            case "idleCPU":
                guard !sawIdle else { return nil }
                sawIdle = true
                if value == "none" {
                    idleCPU = nil
                } else if let parsed = percent(value) {
                    idleCPU = parsed
                } else {
                    return nil
                }
            case "openCPU":
                guard openCPU == nil, let parsed = percent(value) else { return nil }
                openCPU = parsed
            case "memOpenMB":
                guard memoryOpen == nil, let parsed = wholeNumber(value) else { return nil }
                memoryOpen = parsed
            case "memCloseMB":
                guard memoryClose == nil, let parsed = wholeNumber(value) else { return nil }
                memoryClose = parsed
            case "trigger":
                guard trigger == nil, let parsed = OpenTrigger(rawValue: String(value)) else { return nil }
                trigger = parsed
            default:
                continue
            }
        }

        guard sawIdle, let milliseconds, let openCPU, let memoryOpen, let memoryClose, let trigger else {
            return nil
        }
        return OpenMeasurement(
            temperature: temperature,
            milliseconds: milliseconds,
            idleCPUPercent: idleCPU,
            openCPUPercent: openCPU,
            memoryOpenMB: memoryOpen,
            memoryCloseMB: memoryClose,
            trigger: trigger
        )
    }

    private static func wholeNumber(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(isDigit) else { return nil }
        return Int(value)
    }

    /// One digit after the dot, matching `formatPercent`, and a trailing percent sign.
    private static func percent(_ value: Substring) -> Double? {
        guard value.last == "%" else { return nil }
        let number = value.dropLast()
        guard let dot = number.firstIndex(of: ".") else { return nil }
        let whole = number[..<dot]
        let fraction = number[number.index(after: dot)...]
        guard fraction.count == 1, let wholeValue = wholeNumber(whole), let fractionValue = wholeNumber(fraction) else {
            return nil
        }
        return Double(wholeValue) + Double(fractionValue) / 10
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}

/// What the app should do for one step of an open. The app owns the signpost and the log.
public enum GridOpenStep: Equatable, Sendable {
    case beginInterval(OpenTrigger)
    case endInterval(End)
    case log(OpenMeasurement)

    public enum End: Equatable, Sendable {
        case committed(OpenTemperature)
        case cancelled
    }
}

/// Where one open has got to. Readings move it; it does not read the clock itself.
public enum GridOpenPhase: Equatable, Sendable {
    case idle(lastClose: ProcessSample?)
    case opening(Opening)
    case displayed(Displayed)

    public struct Opening: Equatable, Sendable {
        public var trigger: OpenTrigger
        public var temperature: OpenTemperature?
        public var openSample: ProcessSample
        public var idleCPUPercent: Double?
        public var frameWallNanos: UInt64?
    }

    public struct Displayed: Equatable, Sendable {
        public var trigger: OpenTrigger
        public var temperature: OpenTemperature
        public var openSample: ProcessSample
        public var idleCPUPercent: Double?
        public var milliseconds: Int
    }
}

public enum GridOpenEvent: Equatable, Sendable {
    /// The hotkey or the menu asked for the grid. Starts an open only while idle.
    case trigger(OpenTrigger, ProcessSample)
    /// The panel was created or reused. Ignored unless an open is underway.
    case temperature(OpenTemperature)
    /// The panel's first frame was committed. `wallNanos` uses the sample clock.
    case frameCommitted(wallNanos: UInt64)
    /// The grid went away, or the open was given up before a frame.
    case close(ProcessSample)
}

/// Turns open and close readings into one measurement.
///
/// An open starts only from idle, so a hotkey that closes the grid does not
/// start another one. The line is produced when a displayed grid closes. An
/// open that never shows a frame is cancelled and is not logged.
public enum GridOpenSession {
    public static func start() -> GridOpenPhase {
        .idle(lastClose: nil)
    }

    public static func advance(_ phase: inout GridOpenPhase, _ event: GridOpenEvent) -> [GridOpenStep] {
        switch event {
        case .trigger(let trigger, let sample):
            guard case .idle(let lastClose) = phase else { return [] }
            phase = .opening(makeOpening(lastClose: lastClose, trigger: trigger, sample: sample))
            return [.beginInterval(trigger)]
        case .temperature(let temperature):
            guard case .opening(var opening) = phase else { return [] }
            opening.temperature = temperature
            return store(opening, into: &phase)
        case .frameCommitted(let wallNanos):
            guard case .opening(var opening) = phase else { return [] }
            opening.frameWallNanos = wallNanos
            return store(opening, into: &phase)
        case .close(let sample):
            switch phase {
            case .idle:
                return []
            case .opening:
                phase = .idle(lastClose: sample)
                return [.endInterval(.cancelled)]
            case .displayed(let displayed):
                phase = .idle(lastClose: sample)
                guard let openCPU = ProcessLoad.cpuPercent(from: displayed.openSample, to: sample) else {
                    return []
                }
                return [.log(measurement(displayed, openCPU: openCPU, close: sample))]
            }
        }
    }

    private static func makeOpening(
        lastClose: ProcessSample?,
        trigger: OpenTrigger,
        sample: ProcessSample
    ) -> GridOpenPhase.Opening {
        let idle: Double?
        if let lastClose {
            idle = ProcessLoad.cpuPercent(from: lastClose, to: sample)
        } else {
            idle = nil
        }
        return GridOpenPhase.Opening(
            trigger: trigger,
            temperature: nil,
            openSample: sample,
            idleCPUPercent: idle,
            frameWallNanos: nil
        )
    }

    /// Moves to displayed once both the temperature and the frame time are known.
    private static func store(_ opening: GridOpenPhase.Opening, into phase: inout GridOpenPhase) -> [GridOpenStep] {
        guard let temperature = opening.temperature, let frame = opening.frameWallNanos else {
            phase = .opening(opening)
            return []
        }
        guard let milliseconds = ProcessLoad.milliseconds(from: opening.openSample.wallNanos, to: frame) else {
            phase = .opening(opening)
            return []
        }
        phase = .displayed(GridOpenPhase.Displayed(
            trigger: opening.trigger,
            temperature: temperature,
            openSample: opening.openSample,
            idleCPUPercent: opening.idleCPUPercent,
            milliseconds: milliseconds
        ))
        return [.endInterval(.committed(temperature))]
    }

    private static func measurement(
        _ displayed: GridOpenPhase.Displayed,
        openCPU: Double,
        close: ProcessSample
    ) -> OpenMeasurement {
        OpenMeasurement(
            temperature: displayed.temperature,
            milliseconds: displayed.milliseconds,
            idleCPUPercent: displayed.idleCPUPercent,
            openCPUPercent: openCPU,
            memoryOpenMB: ProcessLoad.megabytes(rounding: displayed.openSample.footprintBytes),
            memoryCloseMB: ProcessLoad.megabytes(rounding: close.footprintBytes),
            trigger: displayed.trigger
        )
    }
}
