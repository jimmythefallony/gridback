import AppKit
import GridBackCore
import XCTest

/// Proves where Escape goes while a mouse drag is tracking, without posting
/// events into the user's session. `NSApp.post` stays inside this test process.
final class EscapeDeliveryTests: XCTestCase {
    func testMouseTrackingDoesNotDeliverEscapeUntilTheQueueIsAskedForKeys() throws {
        let posted = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )
        let escape = try XCTUnwrap(posted)
        let app = NSApplication.shared
        var monitorSawEscape = false
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                monitorSawEscape = true
            }
            return event
        }
        defer { NSEvent.removeMonitor(monitor) }

        app.postEvent(escape, atStart: true)
        let mouseOnly = app.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: Date().addingTimeInterval(0.05),
            inMode: .eventTracking,
            dequeue: true
        )
        XCTAssertNil(mouseOnly)
        XCTAssertFalse(monitorSawEscape, "A mouse-only tracking loop must not deliver Escape to the local key monitor")

        let modes: [RunLoop.Mode] = [.eventTracking, .default, .modalPanel, .common]
        var found: RunLoop.Mode?
        for mode in modes {
            guard let event = app.nextEvent(matching: .keyDown, until: Date.distantPast, inMode: mode, dequeue: false) else {
                continue
            }
            if event.keyCode == 53 {
                found = mode
                _ = app.nextEvent(matching: .keyDown, until: Date.distantPast, inMode: mode, dequeue: true)
                break
            }
        }
        let delivered = try XCTUnwrap(found, "Escape stayed queued, but no run-loop mode could see it")
        XCTAssertFalse(monitorSawEscape)
        XCTAssertEqual(delivered, .eventTracking, "The queued Escape was visible to \(delivered.rawValue)")

        let origin = Layout(pages: [["voice", "dictionary"]], metrics: GridMetrics(columns: 2, rows: 2))
        var drag = HeldDrag()
        drag.beginGrid(appID: "dictionary", origin: origin)
        let command = OverlayCommanding.command(
            keyCode: 53,
            characters: "",
            modifiers: [],
            isSearching: false,
            folderIsOpen: false,
            columns: 2,
            drag: &drag
        )
        guard case .cancelDrag(let cancellation) = command else {
            return XCTFail("dequeued Escape did not cancel the drag")
        }
        XCTAssertEqual(cancellation.origin.orderedIDs, ["voice", "dictionary"])
        XCTAssertEqual(drag.complete(), .none)
    }
}
