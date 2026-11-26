import XCTest
import GridBackCore

final class GridFadeTests: XCTestCase {
    func testFreshOpenEasesOutAndLetsTheIconsFollow() throws {
        var fade = GridFade()
        let open = fade.show(reduceMotion: false)
        XCTAssertEqual(fade.phase, .opening)
        XCTAssertEqual(open?.alpha, 1)
        XCTAssertEqual(open?.duration, GridFade.openDuration)
        XCTAssertEqual(open?.curve, .easeOut)
        XCTAssertEqual(open?.fresh, true)
        XCTAssertEqual(open?.scalesIcons, true)
        XCTAssertEqual(open?.fadesIcons, true)
        XCTAssertEqual(open?.iconScale, GridFade.iconScale)
        XCTAssertEqual(open?.iconDelay, GridFade.iconDelay)
        XCTAssertEqual(open?.iconOpacity, 1)
        XCTAssertEqual(
            (open?.iconDelay ?? 0) + (open?.iconDuration ?? 0),
            GridFade.openDuration,
            accuracy: 0.000_000_1
        )
        XCTAssertLessThanOrEqual(open?.duration ?? 1, 0.25)
        XCTAssertEqual(fade.complete(generation: fade.generation), .open)
        XCTAssertEqual(fade.phase, .open)
        XCTAssertNil(fade.complete(generation: fade.generation))
    }

    func testHideDuringOpeningReverses() throws {
        var fade = GridFade()
        let opening = try XCTUnwrap(fade.show(reduceMotion: false))
        let closing = try XCTUnwrap(fade.hide(reduceMotion: false))
        XCTAssertEqual(fade.phase, .closing)
        XCTAssertEqual(closing.alpha, 0)
        XCTAssertEqual(closing.duration, GridFade.closeDuration)
        XCTAssertEqual(closing.curve, .easeIn)
        XCTAssertEqual(closing.iconDelay, 0)
        XCTAssertEqual(closing.scalesIcons, true)
        XCTAssertEqual(closing.iconScale, GridFade.iconScale)
        XCTAssertEqual(closing.iconOpacity, 0)
        XCTAssertNotEqual(opening.generation, closing.generation)
        XCTAssertNil(fade.complete(generation: opening.generation))
        XCTAssertEqual(fade.phase, .closing)
        XCTAssertEqual(fade.complete(generation: closing.generation), .closed)
    }

    func testShowDuringClosingReversesAndCancelsThePendingCompletion() throws {
        var fade = GridFade()
        let opening = try XCTUnwrap(fade.show(reduceMotion: false))
        XCTAssertEqual(fade.complete(generation: opening.generation), .open)
        let closing = try XCTUnwrap(fade.hide(reduceMotion: false))
        let reopened = try XCTUnwrap(fade.show(reduceMotion: false))
        XCTAssertEqual(fade.phase, .opening)
        XCTAssertEqual(reopened.fresh, false)
        XCTAssertEqual(reopened.alpha, 1)
        XCTAssertEqual(reopened.iconDelay, 0)
        XCTAssertEqual(reopened.duration, GridFade.openDuration)
        XCTAssertNotEqual(closing.generation, reopened.generation)
        XCTAssertNil(fade.complete(generation: closing.generation))
        XCTAssertEqual(fade.phase, .opening)
        XCTAssertEqual(fade.complete(generation: reopened.generation), .open)
    }

    func testDoubleHideDuringClosingDoesNothing() throws {
        var fade = GridFade()
        XCTAssertEqual(fade.complete(generation: fade.show(reduceMotion: false)?.generation ?? -1), .open)
        let closing = try XCTUnwrap(fade.hide(reduceMotion: false))
        XCTAssertNil(fade.hide(reduceMotion: false))
        XCTAssertNil(fade.hide(reduceMotion: true))
        XCTAssertEqual(fade.phase, .closing)
        XCTAssertEqual(fade.generation, closing.generation)
        XCTAssertEqual(fade.complete(generation: closing.generation), .closed)
    }

    func testStaleGenerationCompletionDoesNothing() throws {
        var fade = GridFade()
        let opening = try XCTUnwrap(fade.show(reduceMotion: false))
        XCTAssertNil(fade.complete(generation: 0))
        XCTAssertNil(fade.complete(generation: opening.generation + 1))
        XCTAssertEqual(fade.phase, .opening)
        _ = fade.hide(reduceMotion: false)
        XCTAssertNil(fade.complete(generation: opening.generation))
        XCTAssertEqual(fade.phase, .closing)
        let reopened = try XCTUnwrap(fade.show(reduceMotion: false))
        XCTAssertNil(fade.complete(generation: reopened.generation - 1))
        XCTAssertEqual(fade.phase, .opening)
    }

    func testReduceMotionHasNoScaleAndUsesTheShortFade() throws {
        var fade = GridFade()
        let open = try XCTUnwrap(fade.show(reduceMotion: true))
        XCTAssertFalse(open.scalesIcons)
        XCTAssertFalse(open.fadesIcons)
        XCTAssertEqual(open.iconScale, 1)
        XCTAssertEqual(open.iconDelay, 0)
        XCTAssertEqual(open.iconOpacity, 1)
        XCTAssertEqual(open.duration, GridFade.reducedDuration)
        XCTAssertEqual(open.iconDuration, GridFade.reducedDuration)
        XCTAssertEqual(open.curve, .linear)
        XCTAssertEqual(fade.complete(generation: open.generation), .open)

        let close = try XCTUnwrap(fade.hide(reduceMotion: true))
        XCTAssertFalse(close.scalesIcons)
        XCTAssertFalse(close.fadesIcons)
        XCTAssertEqual(close.iconScale, 1)
        XCTAssertEqual(close.iconDelay, 0)
        XCTAssertEqual(close.iconOpacity, 1)
        XCTAssertEqual(close.duration, GridFade.reducedDuration)
        XCTAssertEqual(close.curve, .linear)
        XCTAssertLessThan(close.duration, GridFade.closeDuration)
        XCTAssertLessThan(open.duration, GridFade.openDuration)
    }

    func testShowWhileOpeningOrOpenDoesNothing() throws {
        var fade = GridFade()
        let opening = try XCTUnwrap(fade.show(reduceMotion: false))
        XCTAssertNil(fade.show(reduceMotion: false))
        XCTAssertEqual(fade.generation, opening.generation)
        XCTAssertEqual(fade.complete(generation: opening.generation), .open)
        XCTAssertNil(fade.show(reduceMotion: false))
        XCTAssertEqual(fade.phase, .open)
    }

    func testHideWhileClosedDoesNothing() {
        var fade = GridFade()
        XCTAssertNil(fade.hide(reduceMotion: false))
        XCTAssertEqual(fade.phase, .closed)
        XCTAssertEqual(fade.generation, 0)
    }
}
