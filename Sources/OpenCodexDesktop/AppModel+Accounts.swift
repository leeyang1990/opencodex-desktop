import AppKit
import Foundation

extension AppModel {
    func refreshAccounts(refreshQuota: Bool = false, showErrors: Bool = true) async {
        guard isOnline else {
            codexAccounts = []
            accountPoolStatus = nil
            return
        }
        isRefreshingAccounts = true
        defer { isRefreshingAccounts = false }
        do {
            async let accountsValue = client.codexAccounts(refreshQuota: refreshQuota)
            async let statusValue = client.codexAccountPoolStatus()
            let loaded = try await (accountsValue, statusValue)
            codexAccounts = loaded.0.sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                if $0.isMain != $1.isMain { return $0.isMain }
                return $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending
            }
            accountPoolStatus = loaded.1
        } catch {
            if showErrors { errorMessage = error.localizedDescription }
        }
    }

    func selectCodexAccount(_ account: CodexAccount) async {
        await performAccountOperation(id: account.effectiveID, successMessage: "已切换到 \(account.displayName)") {
            try await self.client.selectCodexAccount(account.effectiveID)
        }
    }

    func setCodexAccountPaused(_ account: CodexAccount, paused: Bool) async {
        await performAccountOperation(
            id: account.effectiveID,
            successMessage: paused ? "账号已暂停" : "账号已恢复"
        ) {
            try await self.client.setCodexAccountPaused(account.effectiveID, paused: paused)
        }
    }

    func setCodexAccountPriority(_ account: CodexAccount, priority: Int) async {
        await performAccountOperation(id: account.effectiveID, successMessage: "账号顺序已更新") {
            try await self.client.setCodexAccountPriority(account.effectiveID, priority: priority)
        }
    }

    func removeCodexAccount(_ account: CodexAccount) async {
        guard !account.isMain else { return }
        await performAccountOperation(id: account.id, successMessage: "账号已移除") {
            try await self.client.removeCodexAccount(account.id)
        }
    }

    func updateAccountPoolStrategy(_ strategy: AccountPoolStrategy) async {
        do {
            try await client.updateCodexPoolStrategy(strategy)
            operationMessage = "账号池策略已更新"
            await refreshAccounts(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateAccountAutoSwitchThreshold(_ threshold: Int) async {
        do {
            try await client.updateCodexAutoSwitchThreshold(threshold)
            operationMessage = "自动切换阈值已更新"
            await refreshAccounts(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginCodexLogin(reauthAccount: CodexAccount? = nil) {
        guard !accountLoginState.isInProgress else { return }
        accountLoginTask?.cancel()
        accountLoginState = .starting
        let accountID = reauthAccount?.id
        let reauth = reauthAccount != nil
        accountLoginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await self.client.startCodexLogin(accountId: accountID, reauth: reauth)
                guard !Task.isCancelled else { return }
                self.accountLoginState = .waiting(flowId: start.flowId, url: start.url)
                let deadline = ContinuousClock.now + AppConstants.Service.loginTimeout
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: AppConstants.Service.loginPollInterval)
                    let status = try await self.client.codexLoginStatus(
                        flowId: start.flowId,
                        accountId: accountID,
                        reauth: reauth
                    )
                    guard !Task.isCancelled else { return }
                    switch status.status {
                    case "done":
                        self.accountLoginState = .completed(status.email)
                        self.operationMessage = reauth ? "账号已重新认证" : "账号已加入账号池"
                        await self.refreshAccounts(refreshQuota: true, showErrors: false)
                        return
                    case "error", "expired":
                        self.accountLoginState = .failed(status.error ?? "登录已过期，请重试")
                        return
                    default:
                        continue
                    }
                }
                self.accountLoginState = .failed("登录超时，请重试")
                try? await self.client.cancelCodexLogin(flowId: start.flowId)
            } catch is CancellationError {
                return
            } catch {
                self.accountLoginState = .failed(error.localizedDescription)
            }
        }
    }

    func reopenCodexLoginPage() {
        guard case let .waiting(_, rawURL) = accountLoginState,
            let url = ExternalURLPolicy.trustedLoginURL(from: rawURL)
        else {
            errorMessage = "登录地址不受信任，仅允许打开 OpenAI 或 ChatGPT 的 HTTPS 页面。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func cancelCodexLogin() {
        let flowID: String?
        if case let .waiting(id, _) = accountLoginState { flowID = id } else { flowID = nil }
        accountLoginTask?.cancel()
        accountLoginTask = nil
        accountLoginState = .idle
        Task { try? await client.cancelCodexLogin(flowId: flowID) }
    }

    func dismissCodexLoginResult() {
        if !accountLoginState.isInProgress { accountLoginState = .idle }
    }

    private func performAccountOperation(
        id: String,
        successMessage: String,
        operation: @escaping () async throws -> Void
    ) async {
        busyAccount = id
        defer { busyAccount = nil }
        do {
            try await operation()
            operationMessage = successMessage
            await refreshAccounts(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
