import Foundation

/// Codex account pool: sign in, choose or pause an account, and select a common scheduling mode.
/// Fine-grained priority, cooldown, removal, and threshold tuning remain in the Core console.
///
/// Sign-in runs through the Core: `POST /api/codex-auth/login` has the Core open the browser and
/// returns a flow id, which this model polls. No token ever passes through the client.
extension AppModel {
    func loadCodexAccounts() async {
        guard isOnline else { return }
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }
        do {
            async let accountsResponse = client.codexAccounts()
            async let schedulingResponse = client.codexScheduling()
            codexAccounts = try await accountsResponse
            scheduling = try await schedulingResponse
            accountErrorMessage = nil
        } catch {
            accountErrorMessage = error.localizedDescription
        }
    }

    func selectCodexAccount(_ account: CodexAccount) async {
        await performAccountChange { try await self.client.selectCodexAccount(account.id) }
        operationMessage = "已切换到 \(account.displayName)"
    }

    func setCodexAccountPaused(_ account: CodexAccount, paused: Bool) async {
        await performAccountChange { try await self.client.setCodexAccountPaused(account.id, paused: paused) }
        operationMessage = paused ? "已暂停 \(account.displayName)" : "已恢复 \(account.displayName)"
    }

    // MARK: - Scheduling

    func setCodexPoolStrategy(_ strategy: String, stickyLimit: Int? = nil) async {
        let sticky = min(max(stickyLimit ?? scheduling?.accountPoolStickyLimit ?? 1, 1), 100)
        await performAccountChange { try await self.client.setCodexPoolStrategy(strategy, stickyLimit: sticky) }
        operationMessage = "调度策略已改为\(CodexAccountScheduling.strategyTitle(strategy))"
    }

    // MARK: - Sign-in

    /// Adds an account by opening a browser sign-in and polling until the Core reports the result.
    func addCodexAccount() async {
        guard isOnline, loginFlowID == nil else { return }
        isStartingLogin = true
        defer { isStartingLogin = false }
        do {
            let started = try await startLoginOperation()
            guard let flowID = started.flowId else {
                accountErrorMessage = "内核未返回登录流程标识"
                return
            }
            loginFlowID = flowID
            loginMessage = "已打开浏览器，请在浏览器中完成 ChatGPT 登录…"
            await pollLogin(flowID: flowID)
        } catch {
            accountErrorMessage = error.localizedDescription
        }
    }

    func cancelCodexLogin() async {
        guard let flowID = loginFlowID else { return }
        loginFlowID = nil
        loginMessage = nil
        try? await cancelLoginOperation(flowID)
    }

    /// Polls the Core's login state until it settles, then refreshes the pool.
    ///
    /// Bounded on purpose: an abandoned browser tab must not leave the UI spinning forever.
    private func pollLogin(flowID: String) async {
        let deadline = ContinuousClock.now + loginTimeout
        while ContinuousClock.now < deadline {
            if Task.isCancelled || loginFlowID != flowID {
                return
            }
            try? await Task.sleep(for: loginPollInterval)
            guard let status = try? await loginStatusOperation(flowID) else { continue }
            switch status.status {
            case "done":
                loginFlowID = nil
                loginMessage = nil
                await loadCodexAccounts()
                operationMessage = "已添加账号 \(status.email ?? "")".trimmingCharacters(in: .whitespaces)
                eventStore.append(.codexAccountAdded, detail: status.email)
                return
            case "error":
                loginFlowID = nil
                loginMessage = nil
                accountErrorMessage = status.error ?? "登录失败"
                return
            case "expired", "cancelled":
                loginFlowID = nil
                loginMessage = nil
                accountErrorMessage = status.status == "expired" ? "登录流程已过期，请重试" : nil
                return
            default:
                loginMessage = status.email.map { "等待 \($0) 授权…" } ?? "等待浏览器授权…"
            }
        }
        loginFlowID = nil
        loginMessage = nil
        accountErrorMessage = "登录等待超时，请重新发起"
    }

    private func performAccountChange(_ change: () async throws -> Void) async {
        guard isOnline, !isUpdatingAccounts else { return }
        isUpdatingAccounts = true
        defer { isUpdatingAccounts = false }
        do {
            try await change()
            await loadCodexAccounts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
