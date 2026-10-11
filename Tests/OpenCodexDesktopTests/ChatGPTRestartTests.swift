import Foundation
import XCTest

@testable import OpenCodexDesktop

@MainActor
private final class FakeChatGPTApp: ChatGPTAppControlling {
    var isRunning = false
    var quitSucceeds = true
    var launchSucceeds = true
    var onQuit: () -> Void = {}
    var onLaunch: () -> Void = {}
    private(set) var quitCount = 0
    private(set) var launchCount = 0
    private(set) var lastQuitTimeout: Duration?

    func requestQuit(timeout: Duration) async -> Bool {
        onQuit()
        quitCount += 1
        lastQuitTimeout = timeout
        if quitSucceeds { isRunning = false }
        return quitSucceeds
    }

    func launch() async -> Bool {
        onLaunch()
        launchCount += 1
        if launchSucceeds { isRunning = true }
        return launchSucceeds
    }
}

@MainActor
final class StopServiceCleanupTests: XCTestCase {
    private func makeModel() -> (AppModel, FakeChatGPTApp) {
        let name = "StopServiceCleanupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(
            defaults: defaults,
            client: OpenCodexAPIClient(host: "127.0.0.1", port: 1), eventStore: .scratch())
        let app = FakeChatGPTApp()
        model.chatGPT = app
        model.stopCoreOperation = {}
        model.restoreRoutingOperation = {}
        return (model, app)
    }

    func testExplicitStopRestoresBeforeRestartRegardlessOfQuitPreference() async {
        let (model, app) = makeModel()
        model.defaults.set(false, forKey: "restoreCodexRoutingOnQuit")
        model.errorMessage = "previous error"
        app.isRunning = true
        var steps: [String] = []
        model.stopCoreOperation = { steps.append("stop") }
        model.restoreRoutingOperation = { steps.append("restore") }
        app.onQuit = { steps.append("quit") }
        app.onLaunch = { steps.append("launch") }

        let succeeded = await model.stopService()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(steps, ["stop", "restore", "quit", "launch"])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.operationMessage, L10n.tr("代理已停止，路由已还原，ChatGPT 已重启"))
        XCTAssertFalse(model.isRefreshing)
        XCTAssertFalse(model.isStoppingService)
    }

    func testStopDoesNotLaunchChatGPTIfItWasClosed() async {
        let (model, app) = makeModel()
        var restores = 0
        model.restoreRoutingOperation = { restores += 1 }
        let succeeded = await model.stopService()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(restores, 1)
        XCTAssertEqual(app.launchCount, 0)
        XCTAssertEqual(model.operationMessage, L10n.tr("代理已停止，路由已还原"))
    }

    func testFailedStopDoesNotRestoreOrRestart() async {
        let (model, app) = makeModel()
        app.isRunning = true
        model.stopCoreOperation = { throw OpenCodexAPIError.operationFailed("stop refused") }
        var restores = 0
        model.restoreRoutingOperation = { restores += 1 }
        let succeeded = await model.stopService()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(restores, 0)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertTrue(model.errorMessage?.contains("stop refused") == true)
        XCTAssertNil(model.operationMessage)
    }

    func testFailedRestoreDoesNotRestartOrClaimSuccess() async {
        let (model, app) = makeModel()
        app.isRunning = true
        model.restoreRoutingOperation = { throw CoreManagerError.restoreFailed("config busy") }
        let succeeded = await model.stopService()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertEqual(
            model.errorMessage,
            L10n.tr("代理已停止，但路由还原失败；未重启 ChatGPT。\(CoreManagerError.restoreFailed("config busy").localizedDescription)"))
        XCTAssertNil(model.operationMessage)
    }

    func testFailedChatGPTQuitKeepsPendingStateAndReportsPartialCompletion() async {
        let (model, app) = makeModel()
        app.isRunning = true
        app.quitSucceeds = false
        let succeeded = await model.stopService()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(app.launchCount, 0)
        XCTAssertTrue(model.isChatGPTRestartPending)
        XCTAssertEqual(model.errorMessage, L10n.tr("代理已停止，路由已还原；\(L10n.tr("ChatGPT 未在限定时间内退出，请手动退出后重试。"))"))
        XCTAssertNil(model.operationMessage)
    }

    func testFailedRelaunchDoesNotClaimCompletion() async {
        let (model, app) = makeModel()
        app.isRunning = true
        app.launchSucceeds = false
        let succeeded = await model.stopService()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(app.quitCount, 1)
        XCTAssertEqual(app.launchCount, 1)
        XCTAssertTrue(model.errorMessage?.contains(L10n.tr("无法启动 ChatGPT，请确认应用仍安装在本机后重试。")) == true)
        XCTAssertNil(model.operationMessage)
    }

    func testMaintenanceStopDoesNotRestoreAgainOrRestartChatGPT() async {
        let (model, app) = makeModel()
        app.isRunning = true
        var restores = 0
        model.restoreRoutingOperation = { restores += 1 }
        let succeeded = await model.stopService(restartChatGPTAfterStop: false)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(restores, 0)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertEqual(model.operationMessage, L10n.tr("内核已停止"))
    }

    func testRepeatedStopIsRejectedWhileFirstIsRunning() async {
        let (model, app) = makeModel()
        app.isRunning = true
        var stopCount = 0
        var resume: CheckedContinuation<Void, Never>?
        model.stopCoreOperation = {
            stopCount += 1
            await withCheckedContinuation { resume = $0 }
        }
        let first = Task { await model.stopService() }
        while resume == nil { await Task.yield() }
        let second = await model.stopService()
        XCTAssertFalse(second)
        resume?.resume()
        let succeeded = await first.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(app.quitCount, 1)
    }
}

@MainActor
final class ChatGPTRestartTests: XCTestCase {
    private func makeModel() -> (AppModel, FakeChatGPTApp) {
        let suiteName = "ocx-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let model = AppModel(
            defaults: defaults,
            client: OpenCodexAPIClient(host: "127.0.0.1", port: 1),
            eventStore: .scratch()
        )
        let app = FakeChatGPTApp()
        model.chatGPT = app
        return (model, app)
    }

    func testRestartQuitsThenRelaunchesRunningApp() async {
        let (model, app) = makeModel()
        app.isRunning = true
        model.refreshChatGPTStatus()
        model.isChatGPTRestartPending = true

        let restarted = await model.restartChatGPT(reason: "单元测试")

        XCTAssertTrue(restarted)
        XCTAssertEqual(app.quitCount, 1)
        XCTAssertEqual(app.launchCount, 1)
        XCTAssertEqual(app.lastQuitTimeout, AppConstants.ChatGPT.quitTimeout)
        XCTAssertFalse(model.isChatGPTRestartPending)
        XCTAssertTrue(model.isChatGPTRunning)
        XCTAssertNil(model.errorMessage)
    }

    func testRestartLaunchesWithoutQuittingWhenAppIsNotRunning() async {
        let (model, app) = makeModel()

        let restarted = await model.restartChatGPT(reason: nil)

        XCTAssertTrue(restarted)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertEqual(app.launchCount, 1)
    }

    /// A running ChatGPT that refuses to quit must not be replaced by a second copy.
    func testRestartDoesNotLaunchWhenQuitFails() async {
        let (model, app) = makeModel()
        app.isRunning = true
        app.quitSucceeds = false

        let restarted = await model.restartChatGPT(reason: nil)

        XCTAssertFalse(restarted)
        XCTAssertEqual(app.launchCount, 0)
        XCTAssertNotNil(model.errorMessage)
    }

    func testRestartReportsMissingApplication() async {
        let (model, app) = makeModel()
        app.launchSucceeds = false

        let restarted = await model.restartChatGPT(reason: nil)

        XCTAssertFalse(restarted)
        XCTAssertNotNil(model.errorMessage)
    }
}

@MainActor
final class ExitCleanupTests: XCTestCase {
    private func makeModel() -> (AppModel, FakeChatGPTApp, () -> Int) {
        let suiteName = "ExitCleanupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            defaults: defaults,
            client: OpenCodexAPIClient(host: "127.0.0.1", port: 1),
            eventStore: .scratch()
        )
        let app = FakeChatGPTApp()
        model.chatGPT = app
        model.needsExitCleanup = { true }
        model.stopOwnedCoreOnExitOperation = { true }
        var restoreCalls = 0
        model.restoreRoutingOperation = { restoreCalls += 1 }
        return (model, app, { restoreCalls })
    }

    func testQuitStopsThenRestoresThenRestartsClient() async {
        let (model, app, _) = makeModel()
        app.isRunning = true
        var steps: [String] = []
        model.stopOwnedCoreOnExitOperation = {
            steps.append("stop"); return true
        }
        model.restoreRoutingOperation = { steps.append("restore") }
        app.onQuit = { steps.append("quit") }
        app.onLaunch = { steps.append("launch") }

        let message = await model.runExitCleanup()

        XCTAssertNil(message)
        XCTAssertEqual(steps, ["stop", "restore", "quit", "launch"])
        XCTAssertTrue(model.didRunExitCleanup)
    }

    func testSuccessfulQuitCleanupRunsOnlyOnce() async {
        let (model, app, restoreCalls) = makeModel()
        app.isRunning = true
        _ = await model.runExitCleanup()
        _ = await model.runExitCleanup()
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertEqual(app.launchCount, 1)
        XCTAssertTrue(model.didRunExitCleanup)
    }

    func testOldDisabledPreferenceAndRecentTimestampCannotSkipCleanup() async {
        let (model, app, restoreCalls) = makeModel()
        model.defaults.set(false, forKey: "restoreCodexRoutingOnQuit")
        model.defaults.set(Date(), forKey: "lastCodexRoutingRestoreAt")
        app.isRunning = true
        let message = await model.runExitCleanup()
        XCTAssertNil(message)
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertEqual(app.launchCount, 1)
    }

    func testFailedStopBlocksRestoreAndRetriesOnNextQuit() async {
        let (model, app, restoreCalls) = makeModel()
        app.isRunning = true
        model.stopOwnedCoreOnExitOperation = { throw CoreManagerError.launchFailed("still running") }
        let message = await model.runExitCleanup()
        XCTAssertNotNil(message)
        XCTAssertEqual(restoreCalls(), 0)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertFalse(model.didRunExitCleanup)
        model.stopOwnedCoreOnExitOperation = { true }
        let retry = await model.runExitCleanup()
        XCTAssertNil(retry)
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertEqual(app.launchCount, 1)
    }

    func testFailedRestoreIsRetriedInsteadOfBypassedOnSecondQuit() async {
        let (model, app, _) = makeModel()
        app.isRunning = true
        var calls = 0
        model.restoreRoutingOperation = {
            calls += 1
            if calls == 1 { throw CoreManagerError.restoreFailed("config busy") }
        }
        let first = await model.runExitCleanup()
        XCTAssertNotNil(first)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertFalse(model.didRunExitCleanup)
        let second = await model.runExitCleanup()
        XCTAssertNil(second)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(app.launchCount, 1)
    }

    func testRestoreTimeoutDoesNotPermitQuit() async {
        let (model, app, _) = makeModel()
        app.isRunning = true
        model.restoreRoutingOperation = { throw CoreManagerError.restoreTimedOut }
        let message = await model.runExitCleanup()
        XCTAssertNotNil(message)
        XCTAssertFalse(model.didRunExitCleanup)
        XCTAssertEqual(app.quitCount, 0)
    }

    func testRefusedClientQuitBlocksExitAndCanBeRetried() async {
        let (model, app, _) = makeModel()
        app.isRunning = true
        app.quitSucceeds = false
        let message = await model.runExitCleanup()
        XCTAssertNotNil(message)
        XCTAssertFalse(model.didRunExitCleanup)
        XCTAssertEqual(app.launchCount, 0)
        app.quitSucceeds = true
        let retry = await model.runExitCleanup()
        XCTAssertNil(retry)
        XCTAssertEqual(app.launchCount, 1)
    }

    func testFailedRelaunchRetriesEvenWhenClientIsNowClosed() async {
        let (model, app, _) = makeModel()
        app.isRunning = true
        app.launchSucceeds = false
        let message = await model.runExitCleanup()
        XCTAssertNotNil(message)
        XCTAssertFalse(app.isRunning)
        XCTAssertFalse(model.didRunExitCleanup)
        XCTAssertTrue(model.exitCleanupNeedsClientRestart)
        app.launchSucceeds = true
        let retry = await model.runExitCleanup()
        XCTAssertNil(retry)
        XCTAssertEqual(app.quitCount, 1)
        XCTAssertEqual(app.launchCount, 2)
        XCTAssertFalse(model.exitCleanupNeedsClientRestart)
    }

    func testClosedClientStaysClosedButRoutingIsRestored() async {
        let (model, app, restoreCalls) = makeModel()
        let message = await model.runExitCleanup()
        XCTAssertNil(message)
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertEqual(app.launchCount, 0)
    }

    func testFreshInstallWithoutCoreCanQuit() async {
        let (model, app, restoreCalls) = makeModel()
        model.needsExitCleanup = { false }
        model.stopOwnedCoreOnExitOperation = {
            XCTFail("nothing to stop"); return false
        }
        let message = await model.runExitCleanup()
        XCTAssertNil(message)
        XCTAssertEqual(restoreCalls(), 0)
        XCTAssertEqual(app.launchCount, 0)
    }

    func testConcurrentQuitRequestsShareCleanup() async {
        let (model, app, restoreCalls) = makeModel()
        app.isRunning = true
        var resume: CheckedContinuation<Void, Never>?
        var stops = 0
        model.stopOwnedCoreOnExitOperation = {
            stops += 1
            await withCheckedContinuation { resume = $0 }
            return true
        }
        let first = Task { await model.runExitCleanup() }
        while resume == nil { await Task.yield() }
        let second = Task { await model.runExitCleanup() }
        await Task.yield()
        resume?.resume()
        let firstMessage = await first.value
        let secondMessage = await second.value
        XCTAssertNil(firstMessage)
        XCTAssertNil(secondMessage)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertEqual(app.launchCount, 1)
    }

    func testInFlightServiceOperationDefersQuit() async {
        let (model, _, restoreCalls) = makeModel()
        model.isStoppingService = true
        let message = await model.runExitCleanup()
        XCTAssertNotNil(message)
        XCTAssertFalse(model.didRunExitCleanup)
        XCTAssertEqual(restoreCalls(), 0)
    }
}
