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
        model.restoresRoutingOnQuit = false
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
final class ExitCleanupPlannerTests: XCTestCase {
    func testRestoresOnceWhenEnabled() {
        let planner = ExitCleanupPlanner(
            alreadyCleanedThisSession: false,
            preferenceEnabled: true,
            lastCleanupAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(planner.shouldRestoreRouting)
        XCTAssertFalse(planner.shouldQuitImmediately)
    }

    func testDisabledPreferenceQuitsWithoutRestoring() {
        let planner = ExitCleanupPlanner(
            alreadyCleanedThisSession: false,
            preferenceEnabled: false,
            lastCleanupAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertFalse(planner.shouldRestoreRouting)
        XCTAssertTrue(planner.shouldQuitImmediately)
    }

    func testSecondQuitInSameSessionDoesNotRestoreAgain() {
        let planner = ExitCleanupPlanner(
            alreadyCleanedThisSession: true,
            preferenceEnabled: true,
            lastCleanupAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertFalse(planner.shouldRestoreRouting)
    }

    /// Logout and restart deliver one user decision twice; the second delivery must not delete a
    /// freshly re-injected routing block.
    func testRepeatedDeliveryOfOneQuitDoesNotRestoreTwice() {
        let now = Date(timeIntervalSince1970: 10_000)
        let planner = ExitCleanupPlanner(
            alreadyCleanedThisSession: false,
            preferenceEnabled: true,
            lastCleanupAt: now.addingTimeInterval(-5),
            now: now
        )

        XCTAssertFalse(planner.shouldRestoreRouting)
    }

    func testRestoresAgainAfterTheGuardInterval() {
        let now = Date(timeIntervalSince1970: 10_000)
        let planner = ExitCleanupPlanner(
            alreadyCleanedThisSession: false,
            preferenceEnabled: true,
            lastCleanupAt: now.addingTimeInterval(-ExitCleanupPlanner.minimumIntervalBetweenRestores - 1),
            now: now
        )

        XCTAssertTrue(planner.shouldRestoreRouting)
    }

    func testPreferenceDefaultsToRestoring() {
        let suite = UserDefaults(suiteName: "ocx-tests-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.description) }

        XCTAssertTrue(DesktopPreferences.restoresRoutingOnQuit(in: suite))
        suite.set(false, forKey: DesktopPreferences.restoresRoutingOnQuitKey)
        XCTAssertFalse(DesktopPreferences.restoresRoutingOnQuit(in: suite))
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
    private func makeModel(
        restoresOnQuit: Bool = true
    ) -> (AppModel, FakeChatGPTApp, () -> Int) {
        let suiteName = "ocx-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(restoresOnQuit, forKey: DesktopPreferences.restoresRoutingOnQuitKey)
        let model = AppModel(
            defaults: defaults,
            client: OpenCodexAPIClient(host: "127.0.0.1", port: 1),
            eventStore: .scratch()
        )
        let app = FakeChatGPTApp()
        model.chatGPT = app
        var restoreCalls = 0
        model.restoreRoutingOperation = { restoreCalls += 1 }
        return (model, app, { restoreCalls })
    }

    func testQuitRestoresRoutingAndRestartsChatGPT() async {
        let (model, app, restoreCalls) = makeModel()
        app.isRunning = true

        let message = await model.runExitCleanup()

        XCTAssertNil(message)
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertEqual(app.quitCount, 1)
        XCTAssertEqual(app.launchCount, 1)
    }

    func testQuitCleanupRunsOnlyOncePerSession() async {
        let (model, _, restoreCalls) = makeModel()

        _ = await model.runExitCleanup()
        let callsAfterFirstQuit = restoreCalls()
        _ = await model.runExitCleanup()

        XCTAssertEqual(callsAfterFirstQuit, 1)
        XCTAssertEqual(restoreCalls(), 1)
        XCTAssertTrue(model.didRunExitCleanup)
    }

    func testDisabledPreferenceSkipsCleanupEntirely() async {
        let (model, app, restoreCalls) = makeModel(restoresOnQuit: false)
        app.isRunning = true

        let message = await model.runExitCleanup()

        XCTAssertNil(message)
        XCTAssertEqual(restoreCalls(), 0)
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertFalse(model.didRunExitCleanup)
    }

    /// A failed restore must be reported instead of quitting silently with Codex still routed to
    /// a proxy that is about to disappear.
    func testFailedRestoreIsReportedAndChatGPTIsLeftRunning() async {
        let (model, app, _) = makeModel()
        app.isRunning = true
        model.restoreRoutingOperation = { throw CoreManagerError.restoreFailed("路由被外部集成占用") }

        let message = await model.runExitCleanup()

        XCTAssertEqual(message, L10n.tr("还原 Codex 路由失败：\("路由被外部集成占用")"))
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertTrue(model.didRunExitCleanup)
    }

    /// A completed cleanup inside the guard interval is not repeated on the next delivery.
    func testCleanupIsNotRepeatedInsideTheGuardInterval() async {
        let (model, _, _) = makeModel()
        model.didRunExitCleanup = false
        model.defaults.set(Date(), forKey: DesktopPreferences.lastExitCleanupKey)
        var restoreCalls = 0
        model.restoreRoutingOperation = { restoreCalls += 1 }

        let message = await model.runExitCleanup()

        XCTAssertNil(message)
        XCTAssertEqual(restoreCalls, 0)
    }
}
