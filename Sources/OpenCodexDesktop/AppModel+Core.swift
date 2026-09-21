import AppKit
import Foundation

extension AppModel {
    func startService() async {
        guard !isStoppingService else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await coreManager.start(port: connectionPort)
            try await waitForServiceReadiness(timeout: AppConstants.Service.startupTimeout)
            await refresh(showSpinner: false)
            guard isOnline else { throw CoreManagerError.launchFailed(L10n.tr("内核已响应，但管理接口尚未就绪")) }
            coreManager.recordSuccessfulLaunch(version: coreManager.targetRelease.version)
            operationMessage = L10n.tr("OpenCodex 内核已启动")
            eventStore.append(.coreStarted, detail: "Core \(health?.version ?? coreManager.targetRelease.version)")
            await reapplyCodexRoutingIfNeeded()
            await loadConfigurationSurfaces()
            runEnvironmentCheck()
        } catch {
            errorMessage = error.localizedDescription
            runEnvironmentCheck()
        }
    }

    @discardableResult
    func stopService(restartChatGPTAfterStop: Bool = true) async -> Bool {
        guard !isStoppingService, !isRestartingChatGPT else { return false }
        isStoppingService = true
        isRefreshing = true
        errorMessage = nil
        operationMessage = nil
        defer {
            isStoppingService = false
            isRefreshing = false
            runEnvironmentCheck()
        }
        var coreStopped = false
        do {
            try await stopCoreOperation()
            coreStopped = true
            eventStore.append(.coreStopped)
            await refresh(showSpinner: false)
            if restartChatGPTAfterStop {
                // The stop endpoint also restores routing. Verify the final on-disk state with
                // the Core's idempotent CLI after exit, including the already-offline case.
                try await restoreRoutingOperation()
                eventStore.append(.codexRoutingRestored, detail: L10n.tr("停止代理"))
                if chatGPT.isRunning {
                    isChatGPTRestartPending = true
                    guard await restartChatGPT(reason: L10n.tr("停止代理")) else {
                        errorMessage = L10n.tr("代理已停止，路由已还原；\(errorMessage ?? L10n.tr("请手动重启 ChatGPT。"))")
                        return false
                    }
                    operationMessage = L10n.tr("代理已停止，路由已还原，ChatGPT 已重启")
                } else {
                    isChatGPTRestartPending = false
                    operationMessage = L10n.tr("代理已停止，路由已还原")
                }
            } else {
                operationMessage = L10n.tr("内核已停止")
            }
            return true
        } catch {
            await refresh(showSpinner: false)
            errorMessage =
                coreStopped
                ? L10n.tr("代理已停止，但路由还原失败；未重启 ChatGPT。\(error.localizedDescription)")
                : L10n.tr("停止未完成或路由还原未确认；未重启 ChatGPT。\(error.localizedDescription)")
            if coreStopped { eventStore.append(.codexRoutingRestoreFailed, detail: L10n.tr("停止代理时还原失败")) }
            return false
        }
    }

    func stopCoreForShutdown() async throws {
        // Do not force-kill a service that explicitly refuses the stop (for example a foreign
        // installation). A failed acknowledgement must remain visible to the user.
        if isOnline { try await client.stopProxy() }
        try await Task.sleep(for: AppConstants.Service.gracefulStopDelay)
        await coreManager.stop()
        guard !coreManager.ownsRunningProcess else {
            throw CoreManagerError.launchFailed(L10n.tr("内核进程仍在运行，请稍后重试。"))
        }
        let deadline = ContinuousClock.now + AppConstants.Service.terminateTimeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if try await client.isProxyListenerStopped() { return }
            try await Task.sleep(for: AppConstants.Service.healthPollInterval)
        }
        throw CoreManagerError.launchFailed(L10n.tr("代理端口仍在响应，未确认内核已停止。"))
    }

    func openConfigFolder() {
        let folder = AdminTokenProvider().tokenFileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folder)
    }

    func openCoreLog() {
        coreManager.openLog()
    }

    func installCore() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let recoveryRelease = coreManager.lastKnownGoodRelease
        do {
            if isOnline || coreManager.ownsRunningProcess {
                guard await stopService(restartChatGPTAfterStop: false) else { return }
            }
            try await coreManager.installTargetCore()
            eventStore.append(.coreInstalled, detail: "Core \(coreManager.targetRelease.version)")
            operationMessage = L10n.tr("OpenCodex Core \(coreManager.targetRelease.version) 已安装")
            await startService()
            if !isOnline, let recoveryRelease,
                recoveryRelease.version != coreManager.targetRelease.version
            {
                await recoverCore(using: recoveryRelease)
            }
        } catch {
            let originalError = error.localizedDescription
            if let recoveryRelease {
                await recoverCore(using: recoveryRelease)
                if isOnline {
                    operationMessage = L10n.tr("安装失败，已恢复 Core \(recoveryRelease.version)")
                    errorMessage = nil
                    return
                }
            }
            errorMessage = originalError
        }
    }

    func rollbackCore() async {
        guard let release = coreManager.rollbackRelease else { return }
        await recoverCore(using: release)
        if isOnline {
            eventStore.append(.coreRollback, detail: "Core \(release.version)")
            operationMessage = L10n.tr("已回滚到 Core \(release.version)")
        }
    }

    func uninstallCore() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard await stopService() else { return }
            try await coreManager.uninstallTargetCore()
            await refresh(showSpinner: false)
            operationMessage = L10n.tr("内核已卸载，配置与账号数据已保留")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCoreInstallationFolder() {
        coreManager.openInstallationFolder()
    }

    /// Opens the Core-served console in the default browser.
    func openConsole(page: CoreConsolePage? = nil) {
        guard let consoleURL = consoleURL(page: page) else { return }
        NSWorkspace.shared.open(consoleURL)
    }

    func waitForServiceReadiness(timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        var lastError: Error?
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            do {
                _ = try await client.health()
                return
            } catch {
                lastError = error
            }
            if let exitMessage = coreManager.lastExitMessage {
                throw CoreManagerError.stoppedUnexpectedly(exitMessage)
            }
            try await Task.sleep(for: AppConstants.Service.healthPollInterval)
        }
        if let error = lastError as? CoreManagerError { throw error }
        throw CoreManagerError.launchFailed(L10n.tr("内核未在限定时间内就绪，请查看内核日志"))
    }

    private func recoverCore(using release: CoreRelease) async {
        errorMessage = nil
        if isOnline || coreManager.ownsRunningProcess {
            guard await stopService(restartChatGPTAfterStop: false) else { return }
        }
        do {
            try coreManager.selectTrustedRelease(release)
            await startService()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
