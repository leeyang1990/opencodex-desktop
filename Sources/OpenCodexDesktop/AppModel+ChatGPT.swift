import AppKit
import Foundation

/// Outcome of one `ocx restore` attempt, kept value-typed so the exit path can decide whether
/// quitting is still safe.
enum RoutingRestoreOutcome: Equatable {
    case restored
    case failed(String)
    case timedOut
}

extension AppModel {
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
                errorMessage = L10n.tr("ChatGPT 未在限定时间内退出，请手动退出后重试。")
                return false
            }
        }
        guard await chatGPT.launch() else {
            refreshChatGPTStatus()
            errorMessage = L10n.tr("无法启动 ChatGPT，请确认应用仍安装在本机后重试。")
            return false
        }
        isChatGPTRestartPending = false
        refreshChatGPTStatus()
        errorMessage = nil
        operationMessage = wasRunning ? L10n.tr("ChatGPT 已重启，新的 Codex 配置已生效") : L10n.tr("ChatGPT 已启动")
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
            eventStore.append(.runtimeChanged, detail: L10n.tr("Codex 路由重新指向失败"))
        }
    }

    func reapplyCodexRouting() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await reapplyRoutingOperation()
            await refresh(showSpinner: false)
            guard settings?.isCodexRoutingInjected != false else {
                errorMessage = L10n.tr("内核未确认路由已恢复，请查看内核日志。")
                return
            }
            errorMessage = nil
            operationMessage = L10n.tr("Codex 路由已重新指向本机代理")
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
        switch await restoreCodexRouting(restartChatGPT: true, reason: L10n.tr("手动还原")) {
        case .restored:
            errorMessage = nil
            operationMessage = L10n.tr("已还原 Codex 路由，并重启 ChatGPT")
            eventStore.append(.codexRoutingRestored, detail: L10n.tr("手动还原"))
        case .timedOut:
            errorMessage = L10n.tr("还原 Codex 路由超时，配置可能仍指向本机代理。")
            eventStore.append(.codexRoutingRestoreFailed, detail: L10n.tr("超时"))
        case let .failed(detail):
            errorMessage = detail.isEmpty ? L10n.tr("还原 Codex 路由失败。") : detail
            eventStore.append(.codexRoutingRestoreFailed, detail: detail.isEmpty ? nil : detail)
        }
        runEnvironmentCheck()
    }

    // MARK: - Quit-time cleanup

    /// All quit entry points share one mandatory cleanup. Retry failures, including a failed
    /// relaunch after the client already quit. Previous sessions and old preferences cannot skip it.
    func runExitCleanup() async -> String? {
        if let exitCleanupTask { return await exitCleanupTask.value }
        guard !didRunExitCleanup else { return nil }
        guard !isStoppingService, !isRestartingChatGPT, !isRefreshing else {
            return L10n.tr("当前操作尚未完成，请完成后重试退出。")
        }
        guard needsExitCleanup() else {
            didRunExitCleanup = true
            return nil
        }
        let task = Task { await performExitCleanup() }
        exitCleanupTask = task
        let message = await task.value
        exitCleanupTask = nil
        return message
    }

    private func performExitCleanup() async -> String? {
        isStoppingService = true
        errorMessage = nil
        operationMessage = nil
        defer { isStoppingService = false }
        exitCleanupNeedsClientRestart = exitCleanupNeedsClientRestart || chatGPT.isRunning

        do {
            if try await stopOwnedCoreOnExitOperation() { eventStore.append(.coreStopped) }
        } catch {
            return L10n.tr("停止 OpenCodex 失败，未退出：\(error.localizedDescription)")
        }

        do {
            try await restoreRoutingOperation()
            eventStore.append(.codexRoutingRestored, detail: L10n.tr("退出客户端"))
        } catch {
            eventStore.append(.codexRoutingRestoreFailed, detail: L10n.tr("退出客户端"))
            await refresh(showSpinner: false)
            return L10n.tr("还原 Codex 路由失败，未退出：\(error.localizedDescription)")
        }

        if exitCleanupNeedsClientRestart || chatGPT.isRunning {
            isChatGPTRestartPending = true
            guard await restartChatGPT(reason: L10n.tr("退出客户端")) else {
                return L10n.tr("OpenCodex 已停止，路由已还原，但 Codex 重启失败；\(errorMessage ?? L10n.tr("请手动重启 ChatGPT。"))")
            }
        }
        exitCleanupNeedsClientRestart = false
        didRunExitCleanup = true
        return nil
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
