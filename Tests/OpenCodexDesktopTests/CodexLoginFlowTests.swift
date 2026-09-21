import Foundation
import XCTest

@testable import OpenCodexDesktop

/// The sign-in flow: start, poll to completion, and never hang past the deadline.
@MainActor
final class CodexLoginFlowTests: XCTestCase {
    private func makeModel() -> AppModel {
        let model = AppModel(
            defaults: UserDefaults(suiteName: "CodexLoginFlowTests.\(UUID().uuidString)")!,
            client: OpenCodexAPIClient(host: "127.0.0.1", port: 1),
            eventStore: .scratch()
        )
        model.connectionState = .online
        model.loginPollInterval = .milliseconds(1)
        model.loginTimeout = .seconds(5)
        return model
    }

    func testLoginPollsUntilDoneThenReportsSuccess() async {
        let model = makeModel()
        model.connectionState = .online
        model.startLoginOperation = {
            CodexLoginStatus(status: "starting", flowId: "flow-1", accountId: nil, email: nil, error: nil)
        }
        var pollCount = 0
        model.loginStatusOperation = { _ in
            pollCount += 1
            if pollCount < 2 {
                return CodexLoginStatus(status: "pending", flowId: "flow-1", accountId: nil, email: nil, error: nil)
            }
            return CodexLoginStatus(
                status: "done",
                flowId: "flow-1",
                accountId: "chatgpt-2",
                email: "a@b.c",
                error: nil
            )
        }

        await model.addCodexAccount()

        XCTAssertEqual(pollCount, 2)
        XCTAssertNil(model.loginFlowID)
        XCTAssertEqual(model.operationMessage?.contains("a@b.c"), true)
        // The refresh that follows a successful login talks to a real Core; offline is fine here,
        // what matters is that the flow itself completed.
        XCTAssertNil(model.loginMessage)
    }

    /// A Core-side error must surface verbatim instead of being swallowed as a timeout.
    func testLoginSurfacesCoreError() async {
        let model = makeModel()
        model.connectionState = .online
        model.startLoginOperation = {
            CodexLoginStatus(status: "starting", flowId: "flow-2", accountId: nil, email: nil, error: nil)
        }
        model.loginStatusOperation = { _ in
            CodexLoginStatus(
                status: "error",
                flowId: "flow-2",
                accountId: nil,
                email: nil,
                error: "Signed-in ChatGPT account does not match this pool account."
            )
        }

        await model.addCodexAccount()

        XCTAssertNil(model.loginFlowID)
        XCTAssertEqual(model.accountErrorMessage, "Signed-in ChatGPT account does not match this pool account.")
    }

    func testLoginReportsMissingFlowIDInsteadOfSpinning() async {
        let model = makeModel()
        model.connectionState = .online
        model.startLoginOperation = {
            CodexLoginStatus(status: "starting", flowId: nil, accountId: nil, email: nil, error: nil)
        }

        await model.addCodexAccount()

        XCTAssertNil(model.loginFlowID)
        XCTAssertNotNil(model.accountErrorMessage)
    }

    /// The polling loop is bounded; a browser tab left open must not spin forever.
    func testLoginStopsPollingWhenCancelled() async {
        let model = makeModel()
        model.connectionState = .online
        model.startLoginOperation = {
            CodexLoginStatus(status: "starting", flowId: "flow-3", accountId: nil, email: nil, error: nil)
        }
        var pollCount = 0
        model.loginStatusOperation = { _ in
            pollCount += 1
            // Cancel from inside the flow, as the user pressing Cancel would.
            if pollCount == 2 { model.loginFlowID = nil }
            return CodexLoginStatus(status: "pending", flowId: "flow-3", accountId: nil, email: nil, error: nil)
        }

        await model.addCodexAccount()

        XCTAssertLessThanOrEqual(pollCount, 3, "polling must stop once the flow is abandoned")
    }

    func testAddingAccountIsRejectedWhileAnotherFlowIsActive() async {
        let model = makeModel()
        model.connectionState = .online
        model.loginFlowID = "existing"
        var started = false
        model.startLoginOperation = {
            started = true
            return CodexLoginStatus(status: "starting", flowId: "flow-4", accountId: nil, email: nil, error: nil)
        }

        await model.addCodexAccount()

        XCTAssertFalse(started)
        XCTAssertEqual(model.loginFlowID, "existing")
    }
}
