import AppKit
import Foundation

extension AppModel {
    func startService() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await coreManager.start(port: connectionPort)
            try await waitForServiceReadiness(timeout: AppConstants.Service.startupTimeout)
            await refresh(showSpinner: false)
            guard isOnline else { throw CoreManagerError.launchFailed("内核已响应，但管理接口尚未就绪") }
            coreManager.recordSuccessfulLaunch(version: coreManager.targetRelease.version)
            operationMessage = "OpenCodex 内核已启动"
            eventStore.append(.coreStarted, detail: "Core \(health?.version ?? coreManager.targetRelease.version)")
            runEnvironmentCheck()
        } catch {
            errorMessage = error.localizedDescription
            runEnvironmentCheck()
        }
    }

    func stopService() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if isOnline { try await client.stopProxy() }
            try await Task.sleep(for: AppConstants.Service.gracefulStopDelay)
            await coreManager.stop()
            await refresh(showSpinner: false)
            operationMessage = "内核已停止"
            eventStore.append(.coreStopped)
            runEnvironmentCheck()
        } catch {
            await coreManager.stop()
            await refresh(showSpinner: false)
            errorMessage = error.localizedDescription
            runEnvironmentCheck()
        }
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
            if isOnline || coreManager.ownsRunningProcess { await stopService() }
            try await coreManager.installTargetCore()
            eventStore.append(.coreInstalled, detail: "Core \(coreManager.targetRelease.version)")
            operationMessage = "OpenCodex Core \(coreManager.targetRelease.version) 已安装"
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
                    operationMessage = "安装失败，已恢复 Core \(recoveryRelease.version)"
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
            operationMessage = "已回滚到 Core \(release.version)"
        }
    }

    func uninstallCore() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if isOnline || coreManager.ownsRunningProcess { await stopService() }
            try await coreManager.uninstallTargetCore()
            await refresh(showSpinner: false)
            operationMessage = "内核已卸载，配置与账号数据已保留"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCoreInstallationFolder() {
        coreManager.openInstallationFolder()
    }

    func openDashboard() {
        if let dashboardURL { NSWorkspace.shared.open(dashboardURL) }
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
        throw CoreManagerError.launchFailed("内核未在限定时间内就绪，请查看内核日志")
    }

    private func recoverCore(using release: CoreRelease) async {
        errorMessage = nil
        if isOnline || coreManager.ownsRunningProcess { await stopService() }
        do {
            try coreManager.selectTrustedRelease(release)
            await startService()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
