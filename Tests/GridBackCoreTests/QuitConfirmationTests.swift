import XCTest
import GridBackCore

final class QuitConfirmationTests: XCTestCase {
    private let quit = QuitConfirmation.quitKeyCode

    func testConfirmationWindowIsAboutTwoSecondsAndUsesTheQKey() {
        XCTAssertEqual(QuitConfirmation.window, 2)
        XCTAssertEqual(QuitConfirmation.quitKeyCode, 12)
    }

    func testFirstPressArmsAndSecondPressInsideTheWindowQuits() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, at: 10), .arm(until: 12))
        XCTAssertEqual(press(confirm: &confirm, at: 12), .quit)
        XCTAssertEqual(press(confirm: &confirm, at: 12), .arm(until: 14))
    }

    func testPressAfterTheWindowArmsAgain() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, at: 10), .arm(until: 12))
        let later = 10 + QuitConfirmation.window + 0.001
        XCTAssertEqual(press(confirm: &confirm, at: later), .arm(until: later + QuitConfirmation.window))
    }

    func testPressWithNoKeyWindowDoesNotQuitOrArm() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, at: 4, windowIsKey: false), .pass)
        XCTAssertEqual(press(confirm: &confirm, at: 4), .arm(until: 6))
        XCTAssertEqual(press(confirm: &confirm, at: 5, windowIsKey: false), .pass)
        XCTAssertEqual(press(confirm: &confirm, at: 5.5), .quit)
    }

    func testRepeatDoesNotArmOrQuit() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, at: 0, isRepeat: true), .swallow)
        XCTAssertEqual(press(confirm: &confirm, at: 1), .arm(until: 3))
        XCTAssertEqual(press(confirm: &confirm, at: 1.2, isRepeat: true), .swallow)
        XCTAssertEqual(press(confirm: &confirm, at: 2), .quit)
    }

    func testOtherChordsDoNotArmOrQuit() {
        var confirm = QuitConfirmation()
        let samples: [(UInt16, KeyModifiers)] = [
            (0, .command),
            (6, [.command, .shift]),
            (quit, [.command, .shift]),
            (quit, [.command, .option]),
            (quit, [.command, .control]),
            (quit, []),
        ]
        for (keyCode, modifiers) in samples {
            XCTAssertEqual(
                confirm.decide(keyCode: keyCode, modifiers: modifiers, at: 1, windowIsKey: true, isRepeat: false),
                .pass
            )
        }
        XCTAssertEqual(press(confirm: &confirm, at: 1), .arm(until: 3))
    }

    private func press(
        confirm: inout QuitConfirmation,
        at now: TimeInterval,
        windowIsKey: Bool = true,
        isRepeat: Bool = false
    ) -> QuitConfirmation.Decision {
        confirm.decide(
            keyCode: quit,
            modifiers: .command,
            at: now,
            windowIsKey: windowIsKey,
            isRepeat: isRepeat
        )
    }
}
