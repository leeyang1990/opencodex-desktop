import AppKit
import Foundation

/// Outcome of one `ocx restore` attempt, kept value-typed so the exit path can decide whether
/// quitting is still safe.
enum RoutingRestoreOutcome: Equatable {
    case restored
    case failed(String)
    case timedOut
}

/// Whether the quitting launch may rewrite Codex routing.
///
/// Restoring is intentionally once per session, and skipped when a previous quit did it moments
/// ago: two quit attempts five seconds apart are the same logout/restart, not two user decisions.
struct ExitCleanupPlanner: Equatable {
    static let minimumIntervalBetweenRestores: TimeInterval = 30

    let alreadyCleanedThisSession: Bool
    let preferenceEnabled: Bool
    let lastCleanupAt: Date?
    let now: Date

    var shouldRestoreRouting: Bool {
        guard preferenceEnabled, !alreadyCleanedThisSession else { return false }
        guard let lastCleanupAt else { return true }
        return now.timeIntervalSince(lastCleanupAt) >= Self.minimumIntervalBetweenRestores
    }

    var shouldQuitImmediately: Bool { !preferenceEnabled }
}

extension AppModel {
    /// Restore Codex routing when the launcher quits. Defaults to on.
    var restoresRoutingOnQuit: Bool {
        get { DesktopPreferences.restoresRoutingOnQuit(in: defaults) }
        set { defaults.set(newValue, forKey: DesktopPreferences.restoresRoutingOnQuitKey) }
    }

    // MARK: - ChatGPT lifecycle

    func refreshChatGPTStatus() {
        isChatGPTRunning = chatGPT.isRunning
        if !isChatGPTRunning { isChatGPTRestartPending = false }
    }

    /// Restarts ChatGPT so it re-reads `~/.codex/config.toml`.
    ///
    /// Quitting is cooperative: ChatGPT runs the Codex app-server that carries the current
    /// configuration, so it must exit on its own before the replacement reads the new one.
    @discardableResult
    func restartChatGPT(reason: String?) async -> Bool {
        guard !isRestartingChatGPT else { return false }
        isRestartingChatGPT = true
        defer { isRestartingChatGPT = false }

        let wasRunning = chatGPT.isRunning
        if wasRunning {
            let quit = await chatGPT.requestQuit(timeout: AppConstants.ChatGPT.quitTimeout)
            guard quit else {
                refreshChatGPTStatus()
                errorMessage = "ChatGPT 未在限定时间内退出，请手动退出后重试。"
                return false
            }
        }
        guard await chatGPT.launch() else {
            refreshChatGPTStatus()
            errorMessage = "无法启动 ChatGPT，请确认应用仍安装在本机后重试。"
            return false
        }
        isChatGPTRestartPending = false
        refreshChatGPTStatus()
        errorMessage = nil
        operationMessage = wasRunning ? "ChatGPT 已重启，新的 Codex 配置已生效" : "ChatGPT 已启动"
        eventStore.append(.chatGPTRestarted, detail: reason)
        return true
    }

    // MARK: - Codex routing

    @discardableResult
    func restoreCodexRouting(restartChatGPT: Bool, reason: String?) async -> RoutingRestoreOutcome {
        do {
            try await restoreRoutingOperation()
        } catch let error as CoreManagerError {
            if case .restoreTimedOut = error { return .timedOut }
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }

        await refresh(showSpinner: false)
        if restartChatGPT, chatGPT.isRunning {
            await self.restartChatGPT(reason: reason)
        }
        return .restored
    }

    /// Re-points plain Codex at the running Core.
    ///
    /// A quit-time restore records Codex integration as OFF, so the next Core start must be told
    /// to route again; otherwise the Core would honour that stored intent and never inject.
    func reapplyCodexRoutingIfNeeded() async {
        guard isOnline, settings?.isCodexRoutingInjected == false else { return }
        do {
            try await reapplyRoutingOperation()
            await refresh(showSpinner: false)
            if settings?.isCodexRoutingInjected != true { return }
            if chatGPT.isRunning { isChatGPTRestartPending = true }
        } catch {
            // A failed re-point is not a launcher failure: the Core console owns routing, and the
            // Overview card still offers the manual action.
            eventStore.append(.runtimeChanged, detail: "Codex 路由重新指向失败")
        }
    }

    func reapplyCodexRouting() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await reapplyRoutingOperation()
            await refresh(showSpinner: false)
            guard settings?.isCodexRoutingInjected != false else {
                errorMessage = "内核未确认路由已恢复，请查看内核日志。"
                return
            }
            errorMessage = nil
            operationMessage = "Codex 路由已重新指向本机代理"
            if chatGPT.isRunning { isChatGPTRestartPending = true }
        } catch {
            errorMessage = error.localizedDescription
        }
        runEnvironmentCheck()
    }

    /// The explicit card action: hand Codex back to native routing and restart ChatGPT so the
    /// restored configuration is what the running app actually uses.
    func restoreRoutingAndRestartChatGPT() async {
        isRefreshing = true
        defer { isRefreshing = false }
        switch await restoreCodexRouting(restartChatGPT: true, reason: "手动还原") {
        case .restored:
            errorMessage = nil
            operationMessage = "已还原 Codex 路由，并重启 ChatGPT"
            eventStore.append(.codexRoutingRestored, detail: "手动还原")
        case .timedOut:
            errorMessage = "还原 Codex 路由超时，配置可能仍指向本机代理。"
            eventStore.append(.codexRoutingRestoreFailed, detail: "超时")
        case let .failed(detail):
            errorMessage = detail.isEmpty ? "还原 Codex 路由失败。" : detail
            eventStore.append(.codexRoutingRestoreFailed, detail: detail.isEmpty ? nil : detail)
        }
        runEnvironmentCheck()
    }

    // MARK: - Quit-time cleanup

    /// Restores native Codex routing and restarts ChatGPT before the launcher exits.
    ///
    /// Returns `nil` when cleanup is not wanted or already happened, so the caller can terminate
    /// immediately. A returned message is shown to the user *and* remembered, so a second quit
    /// attempt inside the same session never repeats a destructive step.
    func runExitCleanup() async -> String? {
        let planner = ExitCleanupPlanner(
            alreadyCleanedThisSession: didRunExitCleanup,
            preferenceEnabled: restoresRoutingOnQuit,
            lastCleanupAt: defaults.object(forKey: DesktopPreferences.lastExitCleanupKey) as? Date,
            now: Date()
        )
        guard planner.shouldRestoreRouting else { return nil }
        didRunExitCleanup = true

        switch await restoreCodexRouting(restartChatGPT: true, reason: "退出客户端") {
        case .restored:
            defaults.set(Date(), forKey: DesktopPreferences.lastExitCleanupKey)
            eventStore.append(.codexRoutingRestored, detail: "退出客户端")
            return nil
        case .timedOut:
            let message = "还原 Codex 路由超时，配置可能仍指向本机代理。"
            eventStore.append(.codexRoutingRestoreFailed, detail: "超时")
            return message
        case let .failed(detail):
            eventStore.append(.codexRoutingRestoreFailed, detail: detail.isEmpty ? nil : detail)
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "还原 Codex 路由失败。" : "还原 Codex 路由失败：\(trimmed)"
        }
    }

    // MARK: - Status observation

    func startChatGPTStatusObservation() {
        guard chatGPTStatusTask == nil else { return }
        refreshChatGPTStatus()
        let center = NSWorkspace.shared.notificationCenter
        let observers = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard
                    let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    running.bundleIdentifier == AppConstants.ChatGPT.bundleIdentifier
                else { return }
                MainActor.assumeIsolated { self?.refreshChatGPTStatus() }
            }
        }
        chatGPTStatusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                self.refreshChatGPTStatus()
            }
        }
        chatGPTObservers = observers
    }
}
