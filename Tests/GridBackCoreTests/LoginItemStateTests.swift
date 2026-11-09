import XCTest
import GridBackCore

final class LoginItemStateTests: XCTestCase {
    func testCheckboxIsOnOnlyWhenTheSystemSaysEnabled() {
        for status in LoginItemSystemStatus.allCases {
            let state = LoginItemViewState.make(status: status)
            XCTAssertEqual(state.isOn, status == .enabled, status.rawValue)
            XCTAssertEqual(state.needsApproval, status == .requiresApproval, status.rawValue)
            XCTAssertEqual(state.notFound, status == .notFound, status.rawValue)
            XCTAssertNil(state.failure, status.rawValue)
        }
    }

    func testCreatingTheControllerOnlyReadsStatus() {
        let service = MockLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)
        XCTAssertFalse(controller.state.isOn)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
        XCTAssertEqual(service.statusReads, 1)
    }

    func testTurningOnRegistersAndShowsEnabled() {
        let service = MockLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertTrue(controller.state.isOn)
        XCTAssertFalse(controller.state.needsApproval)
        XCTAssertNil(controller.state.failure)
    }

    func testTurningOnThatNeedsApprovalStaysOffWithANote() {
        let service = MockLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertFalse(controller.state.isOn)
        XCTAssertTrue(controller.state.needsApproval)
        XCTAssertNil(controller.state.failure)
    }

    func testRegisterErrorThatLeavesApprovalDoesNotAddASecondError() {
        let service = MockLoginItemService(status: .requiresApproval)
        service.registerError = StubFailure()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertFalse(controller.state.isOn)
        XCTAssertTrue(controller.state.needsApproval)
        XCTAssertNil(controller.state.failure)
    }

    func testRegisterErrorWithNoChangeShowsAPlainFailure() {
        let service = MockLoginItemService(status: .notRegistered)
        service.registerError = StubFailure()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertFalse(controller.state.isOn)
        XCTAssertEqual(controller.state.failure, .couldNotTurnOn)
    }

    func testMissingAppShowsTheNotFoundNoteInsteadOfAGenericError() {
        let service = MockLoginItemService(status: .notFound)
        service.registerError = StubFailure()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertFalse(controller.state.isOn)
        XCTAssertTrue(controller.state.notFound)
        XCTAssertNil(controller.state.failure)
    }

    func testTurningOffUnregisters() {
        let service = MockLoginItemService(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let controller = LoginItemController(service: service)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertFalse(controller.state.isOn)
        XCTAssertNil(controller.state.failure)
    }

    func testUnregisterErrorThatLeavesItEnabledShowsAPlainFailure() {
        let service = MockLoginItemService(status: .enabled)
        service.unregisterError = StubFailure()
        let controller = LoginItemController(service: service)
        controller.setEnabled(false)
        XCTAssertTrue(controller.state.isOn)
        XCTAssertEqual(controller.state.failure, .couldNotTurnOff)
    }

    func testRefreshFollowsAChangeMadeInSystemSettings() {
        let service = MockLoginItemService(status: .enabled)
        let controller = LoginItemController(service: service)
        XCTAssertTrue(controller.state.isOn)
        service.status = .requiresApproval
        controller.refresh()
        XCTAssertFalse(controller.state.isOn)
        XCTAssertTrue(controller.state.needsApproval)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
    }

    func testRefreshClearsAnOldFailureWhenTheSystemStateIsReadAgain() {
        let service = MockLoginItemService(status: .notRegistered)
        service.registerError = StubFailure()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(controller.state.failure, .couldNotTurnOn)
        controller.refresh()
        XCTAssertNil(controller.state.failure)
        XCTAssertFalse(controller.state.isOn)
    }
}

private struct StubFailure: Error {}

private final class MockLoginItemService: LoginItemService {
    var status: LoginItemSystemStatus
    var statusAfterRegister: LoginItemSystemStatus
    var statusAfterUnregister: LoginItemSystemStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var statusReads = 0

    init(status: LoginItemSystemStatus) {
        self.status = status
        statusAfterRegister = status
        statusAfterUnregister = status
    }

    func currentStatus() -> LoginItemSystemStatus {
        statusReads += 1
        return status
    }

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = statusAfterUnregister
    }
}
