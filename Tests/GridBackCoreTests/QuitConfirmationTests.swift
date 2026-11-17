import XCTest
import GridBackCore

final class QuitConfirmationTests: XCTestCase {
    func testConfirmationWindowIsTwoSeconds() {
        XCTAssertEqual(QuitConfirmation.window, 2)
    }

    func testQWithCommandArms() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, characters: "q", at: 10), .arm(until: 12))
        XCTAssertEqual(press(confirm: &confirm, characters: "q", at: 12), .quit)
        XCTAssertEqual(press(confirm: &confirm, characters: "Q", at: 12), .arm(until: 14))
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

    func testRepeatsAreSwallowed() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, at: 0, isRepeat: true), .swallow)
        XCTAssertEqual(press(confirm: &confirm, at: 1), .arm(until: 3))
        XCTAssertEqual(press(confirm: &confirm, at: 1.2, isRepeat: true), .swallow)
        XCTAssertEqual(press(confirm: &confirm, at: 2), .quit)
    }

    /// Key code 12 is the physical US Q key. On AZERTY that key types "a",
    /// and on Dvorak it types an apostrophe. The character decides.
    func testKeyCode12WithCharacterADoesNotArm() {
        var confirm = QuitConfirmation()
        XCTAssertEqual(press(confirm: &confirm, characters: "a", at: 1), .pass)
        XCTAssertEqual(press(confirm: &confirm, characters: "a", at: 1, isRepeat: true), .pass)
        XCTAssertEqual(press(confirm: &confirm, characters: "'", at: 1), .pass)
        XCTAssertEqual(press(confirm: &confirm, characters: "q", at: 1), .arm(until: 3))
        XCTAssertEqual(press(confirm: &confirm, characters: "a", at: 2), .pass)
        XCTAssertEqual(press(confirm: &confirm, characters: "q", at: 2), .quit)
    }

    func testShiftAndOptionVariantsDoNotArm() {
        var confirm = QuitConfirmation()
        let samples: [(String, KeyModifiers)] = [
            ("q", [.command, .shift]),
            ("Q", [.command, .shift]),
            ("q", [.command, .option]),
            ("q", [.command, .control]),
            ("q", [.command, .shift, .option]),
            ("q", []),
            ("", .command),
        ]
        for (characters, modifiers) in samples {
            XCTAssertEqual(
                confirm.decide(
                    characters: characters,
                    modifiers: modifiers,
                    at: 1,
                    windowIsKey: true,
                    isRepeat: false
                ),
                .pass
            )
        }
        XCTAssertEqual(press(confirm: &confirm, at: 1), .arm(until: 3))
        XCTAssertEqual(
            confirm.decide(
                characters: "q",
                modifiers: [.command, .shift],
                at: 1.5,
                windowIsKey: true,
                isRepeat: false
            ),
            .pass
        )
        XCTAssertEqual(
            confirm.decide(
                characters: "q",
                modifiers: [.command, .option],
                at: 1.5,
                windowIsKey: true,
                isRepeat: false
            ),
            .pass
        )
        XCTAssertEqual(press(confirm: &confirm, at: 2), .quit)
    }

    private func press(
        confirm: inout QuitConfirmation,
        characters: String = "q",
        at now: TimeInterval,
        modifiers: KeyModifiers = .command,
        windowIsKey: Bool = true,
        isRepeat: Bool = false
    ) -> QuitConfirmation.Decision {
        confirm.decide(
            characters: characters,
            modifiers: modifiers,
            at: now,
            windowIsKey: windowIsKey,
            isRepeat: isRepeat
        )
    }
}
