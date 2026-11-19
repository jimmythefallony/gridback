import XCTest
import GridBackCore

final class OpenMeasurementTests: XCTestCase {
    private let megabyte = UInt64(1024 * 1024)

    func testCPUPercentIsOneCoreAndCanPassOneHundred() {
        let earlier = sample(cpu: 0, wall: 0)
        XCTAssertEqual(percent(from: earlier, to: sample(cpu: 1_000_000_000, wall: 1_000_000_000)), 100, accuracy: 0.000_000_1)
        XCTAssertEqual(percent(from: earlier, to: sample(cpu: 2_000_000_000, wall: 1_000_000_000)), 200, accuracy: 0.000_000_1)
        XCTAssertEqual(percent(from: earlier, to: sample(cpu: 1_000_000, wall: 1_000_000_000)), 0.1, accuracy: 0.000_000_1)
        XCTAssertEqual(percent(from: earlier, to: sample(cpu: 62_000_000, wall: 1_000_000_000)), 6.2, accuracy: 0.000_000_1)
        XCTAssertEqual(percent(from: earlier, to: sample(cpu: 0, wall: 1_000_000_000)), 0, accuracy: 0.000_000_1)
    }

    func testCPUPercentRejectsAClockThatDidNotMoveForward() {
        let earlier = sample(cpu: 10, wall: 50)
        XCTAssertNil(ProcessLoad.cpuPercent(from: earlier, to: sample(cpu: 10, wall: 50)))
        XCTAssertNil(ProcessLoad.cpuPercent(from: earlier, to: sample(cpu: 11, wall: 49)))
        XCTAssertNil(ProcessLoad.cpuPercent(from: earlier, to: sample(cpu: 9, wall: 80)))
    }

    func testPercentTextUsesADotAndOneDecimal() {
        XCTAssertEqual(ProcessLoad.formatPercent(6.25), "6.3%")
        XCTAssertEqual(ProcessLoad.formatPercent(6.24), "6.2%")
        XCTAssertEqual(ProcessLoad.formatPercent(0.04), "0.0%")
        XCTAssertEqual(ProcessLoad.formatPercent(0.05), "0.1%")
        XCTAssertEqual(ProcessLoad.formatPercent(0.1), "0.1%")
        XCTAssertEqual(ProcessLoad.formatPercent(100), "100.0%")
        XCTAssertEqual(ProcessLoad.formatPercent(0), "0.0%")
        XCTAssertEqual(ProcessLoad.formatPercent(Double.nan), "0.0%")
        XCTAssertEqual(ProcessLoad.formatPercent(Double.infinity), "0.0%")
        XCTAssertEqual(ProcessLoad.formatMilliseconds(84), "84")
        XCTAssertEqual(ProcessLoad.formatMilliseconds(80.5), "80.5")
    }

    func testMegabytesRoundHalfUp() {
        XCTAssertEqual(ProcessLoad.megabytes(rounding: 92 * megabyte), 92)
        XCTAssertEqual(ProcessLoad.megabytes(rounding: 95 * megabyte), 95)
        XCTAssertEqual(ProcessLoad.megabytes(rounding: megabyte / 2), 1)
        XCTAssertEqual(ProcessLoad.megabytes(rounding: megabyte / 2 - 1), 0)
    }

    func testMillisecondsRoundToTheNearest() {
        XCTAssertEqual(ProcessLoad.milliseconds(from: 0, to: 84_000_000), 84)
        XCTAssertEqual(ProcessLoad.milliseconds(from: 0, to: 1_499_999), 1)
        XCTAssertEqual(ProcessLoad.milliseconds(from: 0, to: 1_500_000), 2)
        XCTAssertEqual(ProcessLoad.milliseconds(from: 0, to: 499_999), 0)
        XCTAssertNil(ProcessLoad.milliseconds(from: 20, to: 19))
    }

    func testExampleLineIsTheWarmOpenAfterAQuietGap() {
        var phase = GridOpenSession.start()
        _ = GridOpenSession.advance(&phase, .trigger(.hotkey, sample(cpu: 0, wall: 0, bytes: 90 * megabyte)))
        _ = GridOpenSession.advance(&phase, .temperature(.cold))
        _ = GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 50_000_000))
        _ = GridOpenSession.advance(&phase, .close(sample(cpu: 0, wall: 1_000_000_000, bytes: 90 * megabyte)))

        let open = sample(cpu: 1_000_000, wall: 2_000_000_000, bytes: 92 * megabyte)
        XCTAssertEqual(GridOpenSession.advance(&phase, .trigger(.hotkey, open)), [.beginInterval(.hotkey)])
        XCTAssertEqual(GridOpenSession.advance(&phase, .temperature(.warm)), [])
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 2_084_000_000)),
            [.endInterval(.committed(.warm))]
        )
        let closed = GridOpenSession.advance(
            &phase,
            .close(sample(cpu: 63_000_000, wall: 3_000_000_000, bytes: 95 * megabyte))
        )
        guard case .log(let measurement) = closed.first, closed.count == 1 else {
            return XCTFail("Expected one log line")
        }
        XCTAssertEqual(measurement.temperature, .warm)
        XCTAssertEqual(measurement.milliseconds, 84)
        XCTAssertEqual(measurement.idleCPUPercent ?? -1, 0.1, accuracy: 0.000_000_1)
        XCTAssertEqual(measurement.openCPUPercent, 6.2, accuracy: 0.000_000_1)
        XCTAssertEqual(measurement.memoryOpenMB, 92)
        XCTAssertEqual(measurement.memoryCloseMB, 95)
        XCTAssertEqual(measurement.trigger, .hotkey)
        XCTAssertEqual(
            PerfLogLine.format(measurement),
            "open warm ms=84 idleCPU=0.1% openCPU=6.2% memOpenMB=92 memCloseMB=95 trigger=hotkey"
        )
    }

    func testFirstOpenHasNoIdleCPUAndACreatedPanelIsCold() {
        var phase = GridOpenSession.start()
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .trigger(.menu, sample(cpu: 0, wall: 0, bytes: 137 * megabyte))),
            [.beginInterval(.menu)]
        )
        XCTAssertEqual(GridOpenSession.advance(&phase, .temperature(.cold)), [])
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 120_000_000)),
            [.endInterval(.committed(.cold))]
        )
        let closed = GridOpenSession.advance(
            &phase,
            .close(sample(cpu: 110_000_000, wall: 1_000_000_000, bytes: 139 * megabyte))
        )
        guard case .log(let measurement) = closed.first else {
            return XCTFail("Expected one log line")
        }
        XCTAssertNil(measurement.idleCPUPercent)
        XCTAssertEqual(measurement.temperature, .cold)
        XCTAssertEqual(measurement.trigger, .menu)
        XCTAssertEqual(measurement.milliseconds, 120)
        XCTAssertEqual(measurement.memoryOpenMB, 137)
        XCTAssertEqual(measurement.memoryCloseMB, 139)
        XCTAssertEqual(
            PerfLogLine.format(measurement),
            "open cold ms=120 idleCPU=none openCPU=11.0% memOpenMB=137 memCloseMB=139 trigger=menu"
        )
    }

    func testClosingHotkeyDoesNotStartAnInterval() {
        var phase = displayedPhase()
        XCTAssertEqual(GridOpenSession.advance(&phase, .trigger(.hotkey, sample(cpu: 5, wall: 5))), [])
        let closed = GridOpenSession.advance(&phase, .close(sample(cpu: 5, wall: 1_000_000_005)))
        guard case .log(let measurement) = closed.first else {
            return XCTFail("Expected the original open to be logged")
        }
        XCTAssertEqual(measurement.trigger, .hotkey)
        XCTAssertEqual(measurement.milliseconds, 40)
    }

    func testMenuWhileOpenDoesNotRestartTheMeasurement() {
        var phase = displayedPhase()
        XCTAssertEqual(GridOpenSession.advance(&phase, .trigger(.menu, sample(cpu: 9, wall: 9))), [])
        XCTAssertEqual(GridOpenSession.advance(&phase, .temperature(.cold)), [])
        let closed = GridOpenSession.advance(&phase, .close(sample(cpu: 9, wall: 1_000_000_009)))
        guard case .log(let measurement) = closed.first else {
            return XCTFail("Expected the original open to be logged")
        }
        XCTAssertEqual(measurement.temperature, .warm)
        XCTAssertEqual(measurement.trigger, .hotkey)
    }

    func testCloseBeforeTheFrameIsNotLogged() {
        var phase = GridOpenSession.start()
        _ = GridOpenSession.advance(&phase, .trigger(.hotkey, sample(cpu: 0, wall: 0)))
        _ = GridOpenSession.advance(&phase, .temperature(.cold))
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .close(sample(cpu: 1, wall: 1_000))),
            [.endInterval(.cancelled)]
        )
        if case .idle = phase {
        } else {
            XCTFail("Expected to be idle after giving up")
        }
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .close(sample(cpu: 2, wall: 2_000))),
            []
        )
    }

    func testFrameBeforeTemperatureStillTagsThePanel() {
        var phase = GridOpenSession.start()
        _ = GridOpenSession.advance(&phase, .trigger(.menu, sample(cpu: 0, wall: 1_000)))
        XCTAssertEqual(GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 21_000_000)), [])
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .temperature(.cold)),
            [.endInterval(.committed(.cold))]
        )
    }

    func testASecondTriggerDoesNotReplaceTheOpenThatIsUnderway() {
        var phase = GridOpenSession.start()
        _ = GridOpenSession.advance(&phase, .trigger(.hotkey, sample(cpu: 0, wall: 0)))
        XCTAssertEqual(GridOpenSession.advance(&phase, .trigger(.menu, sample(cpu: 50, wall: 50))), [])
        _ = GridOpenSession.advance(&phase, .temperature(.warm))
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 30_000_000)),
            [.endInterval(.committed(.warm))]
        )
        let closed = GridOpenSession.advance(&phase, .close(sample(cpu: 0, wall: 1_000_000_000)))
        guard case .log(let measurement) = closed.first else {
            return XCTFail("Expected a log line")
        }
        XCTAssertEqual(measurement.milliseconds, 30)
        XCTAssertEqual(measurement.trigger, .hotkey)
    }

    func testClockGoingBackwardsSkipsTheLine() {
        var phase = GridOpenSession.start()
        _ = GridOpenSession.advance(&phase, .trigger(.hotkey, sample(cpu: 100, wall: 0)))
        _ = GridOpenSession.advance(&phase, .temperature(.warm))
        XCTAssertEqual(GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 0)), [.endInterval(.committed(.warm))])
        // Zero milliseconds is a real open. A CPU clock that steps backwards is not logged.
        XCTAssertEqual(
            GridOpenSession.advance(&phase, .close(sample(cpu: 90, wall: 1_000_000_000))),
            []
        )
    }

    func testMedianWorstAndPeak() {
        XCTAssertNil(OpenSummaryMath.median([]))
        XCTAssertEqual(OpenSummaryMath.median([84]), 84)
        XCTAssertEqual(OpenSummaryMath.median([10, 30]), 20)
        XCTAssertEqual(OpenSummaryMath.median([90, 10, 40]), 40)
        XCTAssertEqual(OpenSummaryMath.median([80, 81]), 80.5)

        let measurements = [
            measurement(.cold, ms: 100, idle: nil, open: 10, memOpen: 80, memClose: 90, trigger: .hotkey),
            measurement(.warm, ms: 80, idle: 0.1, open: 6, memOpen: 90, memClose: 95, trigger: .hotkey),
            measurement(.warm, ms: 81, idle: 0.3, open: 8, memOpen: 91, memClose: 96, trigger: .menu)
        ]
        let summary = OpenSummaryMath.summarize(measurements)
        XCTAssertEqual(summary.cold?.medianMilliseconds, 100)
        XCTAssertEqual(summary.cold?.worstMilliseconds, 100)
        XCTAssertEqual(summary.cold?.count, 1)
        XCTAssertEqual(summary.warm?.medianMilliseconds, 80.5)
        XCTAssertEqual(summary.warm?.worstMilliseconds, 81)
        XCTAssertEqual(summary.warm?.count, 2)
        XCTAssertEqual(summary.averageIdleCPUPercent ?? -1, 0.2, accuracy: 0.000_000_1)
        XCTAssertEqual(summary.averageOpenCPUPercent ?? -1, 8, accuracy: 0.000_000_1)
        XCTAssertEqual(summary.peakMemoryMB, 96)
        XCTAssertEqual(
            OpenSummaryText.render(summary, last: "1d"),
            """
            GridBack open measurements, last 1d
            cold open: median 100 ms, worst 100 ms, count 1
            warm open: median 80.5 ms, worst 81 ms, count 2
            average idle CPU: 0.2%
            average open CPU: 8.0%
            peak memory: 96 MB
            """
        )
    }

    func testEmptySummarySaysThereIsNoData() {
        let summary = OpenSummaryMath.summarize([])
        XCTAssertNil(summary.cold)
        XCTAssertNil(summary.warm)
        XCTAssertNil(summary.averageIdleCPUPercent)
        XCTAssertNil(summary.averageOpenCPUPercent)
        XCTAssertNil(summary.peakMemoryMB)
        XCTAssertEqual(
            OpenSummaryText.render(summary, last: "7d"),
            "No GridBack open measurements in the last 7d."
        )
    }

    func testSummarySkipsMissingIdleAndKeepsTheOpen() {
        let summary = OpenSummaryMath.summarize([
            measurement(.cold, ms: 120, idle: nil, open: 11, memOpen: 137, memClose: 139, trigger: .hotkey)
        ])
        XCTAssertEqual(
            OpenSummaryText.render(summary, last: "1d"),
            """
            GridBack open measurements, last 1d
            cold open: median 120 ms, worst 120 ms, count 1
            warm open: none
            average idle CPU: none
            average open CPU: 11.0%
            peak memory: 139 MB
            """
        )
    }

    func testLogLineRoundTripAndAPrefixIsIgnored() {
        let line = "open warm ms=84 idleCPU=0.1% openCPU=6.2% memOpenMB=92 memCloseMB=95 trigger=hotkey"
        let parsed = PerfLogLine.parse(line)
        XCTAssertEqual(parsed?.temperature, .warm)
        XCTAssertEqual(parsed?.milliseconds, 84)
        XCTAssertEqual(parsed?.idleCPUPercent, 0.1)
        XCTAssertEqual(parsed?.openCPUPercent, 6.2)
        XCTAssertEqual(parsed?.memoryOpenMB, 92)
        XCTAssertEqual(parsed?.memoryCloseMB, 95)
        XCTAssertEqual(parsed?.trigger, .hotkey)
        XCTAssertEqual(parsed.map(PerfLogLine.format), line)

        let prefixed = PerfLogLine.parse("notice \(line)")
        XCTAssertEqual(prefixed, parsed)
        XCTAssertNil(PerfLogLine.parse("open warm ms=84 idleCPU=0.1%"))
        XCTAssertNil(PerfLogLine.parse("open warm ms=84 idleCPU=none openCPU=6% memOpenMB=92 memCloseMB=95 trigger=hotkey"))
        XCTAssertNil(PerfLogLine.parse("nothing to read"))
    }

    private func displayedPhase() -> GridOpenPhase {
        var phase = GridOpenSession.start()
        _ = GridOpenSession.advance(&phase, .trigger(.hotkey, sample(cpu: 0, wall: 0)))
        _ = GridOpenSession.advance(&phase, .temperature(.warm))
        _ = GridOpenSession.advance(&phase, .frameCommitted(wallNanos: 40_000_000))
        return phase
    }

    private func percent(from earlier: ProcessSample, to later: ProcessSample) -> Double {
        ProcessLoad.cpuPercent(from: earlier, to: later) ?? -1
    }

    private func sample(cpu: UInt64, wall: UInt64, bytes: UInt64 = 0) -> ProcessSample {
        ProcessSample(cpuNanos: cpu, wallNanos: wall, footprintBytes: bytes)
    }

    private func measurement(
        _ temperature: OpenTemperature,
        ms: Int,
        idle: Double?,
        open: Double,
        memOpen: Int,
        memClose: Int,
        trigger: OpenTrigger
    ) -> OpenMeasurement {
        OpenMeasurement(
            temperature: temperature,
            milliseconds: ms,
            idleCPUPercent: idle,
            openCPUPercent: open,
            memoryOpenMB: memOpen,
            memoryCloseMB: memClose,
            trigger: trigger
        )
    }
}
