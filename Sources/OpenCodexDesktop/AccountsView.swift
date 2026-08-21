import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingLogin = false
    @State private var loginTarget: CodexAccount?
    @State private var deletingAccount: CodexAccount?
    @State private var editingPriority: CodexAccount?
    @State private var threshold = 80

    var body: some View {
        Group {
            if !model.isOnline {
                EmptyState(
                    symbol: "person.2.slash",
                    title: "无法加载账号池",
                    detail: "请先启动 OpenCodex 服务。",
                    actionTitle: "重新连接"
                ) {
                    Task { await model.refresh() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader(
                            title: "账号",
                            subtitle: "管理 ChatGPT / Codex 登录与自动切换策略"
                        )
                        strategyCard
                        accountList
                    }
                    .padding(28)
                    .frame(maxWidth: 980, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refreshAccounts(refreshQuota: true) }
                } label: {
                    Label("刷新额度", systemImage: "arrow.clockwise")
                }
                .disabled(!model.isOnline || model.isRefreshingAccounts)

                Button {
                    beginLogin()
                } label: {
                    Label("添加账号", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isOnline || model.accountLoginState.isInProgress)
            }
        }
        .sheet(isPresented: $showingLogin, onDismiss: loginSheetDismissed) {
            AccountLoginSheet(account: loginTarget)
                .environmentObject(model)
        }
        .sheet(item: $editingPriority) { account in
            AccountPriorityEditor(account: account)
                .environmentObject(model)
        }
        .confirmationDialog(
            "移除 \(deletingAccount?.displayName ?? "")？",
            isPresented: Binding(
                get: { deletingAccount != nil },
                set: { if !$0 { deletingAccount = nil } }
            )
        ) {
            Button("移除账号", role: .destructive) {
                guard let account = deletingAccount else { return }
                deletingAccount = nil
                Task { await model.removeCodexAccount(account) }
            }
            Button("取消", role: .cancel) { deletingAccount = nil }
        } message: {
            Text("这会从本机账号池删除该账号的登录凭证，不会删除 ChatGPT 账号本身。")
        }
        .onAppear(perform: loadThreshold)
        .onChange(of: model.accountPoolStatus?.autoSwitchThreshold) { _, _ in loadThreshold() }
    }

    private var strategyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("切换策略", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.isRefreshingAccounts { ProgressView().controlSize(.small) }
            }

            Picker(
                "切换策略",
                selection: Binding(
                    get: { model.accountPoolStatus?.accountPoolStrategy ?? .quota },
                    set: { strategy in Task { await model.updateAccountPoolStrategy(strategy) } }
                )
            ) {
                ForEach(AccountPoolStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text((model.accountPoolStatus?.accountPoolStrategy ?? .quota).detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动切换阈值").font(.callout.weight(.medium))
                    Text("额度使用达到阈值后，允许新会话选择其他健康账号。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Slider(
                    value: Binding(
                        get: { Double(threshold) },
                        set: { threshold = Int($0.rounded()) }
                    ), in: 10...100, step: 5
                )
                .frame(width: 180)
                Text("\(threshold)%")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .frame(width: 44, alignment: .trailing)
                Button("保存") {
                    Task { await model.updateAccountAutoSwitchThreshold(threshold) }
                }
                .disabled(threshold == model.accountPoolStatus?.autoSwitchThreshold)
            }
        }
        .cardStyle()
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("账号池")
                    .font(.title3.weight(.semibold))
                Text("\(model.codexAccounts.filter { !$0.paused }.count) 个可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if model.codexAccounts.isEmpty {
                EmptyState(
                    symbol: "person.crop.circle.badge.plus",
                    title: "还没有可用账号",
                    detail: "添加 ChatGPT 账号后即可启用自动切换。",
                    actionTitle: "添加账号",
                    action: { beginLogin() }
                )
                .frame(minHeight: 260)
                .cardStyle()
            } else {
                ForEach(model.codexAccounts) { account in
                    AccountCard(
                        account: account,
                        isActive: model.accountPoolStatus?.activeCodexAccountId == account.effectiveID,
                        isPinned: model.accountPoolStatus?.pinnedAccountId == account.effectiveID,
                        isBusy: model.busyAccount == account.effectiveID,
                        onSelect: { Task { await model.selectCodexAccount(account) } },
                        onPause: { paused in Task { await model.setCodexAccountPaused(account, paused: paused) } },
                        onPriority: { editingPriority = account },
                        onReauthenticate: { beginLogin(account) },
                        onRemove: { deletingAccount = account }
                    )
                }
            }
        }
    }

    private func beginLogin(_ account: CodexAccount? = nil) {
        loginTarget = account
        model.dismissCodexLoginResult()
        showingLogin = true
        model.beginCodexLogin(reauthAccount: account)
    }

    private func loginSheetDismissed() {
        if model.accountLoginState.isInProgress { model.cancelCodexLogin() } else { model.dismissCodexLoginResult() }
        loginTarget = nil
    }

    private func loadThreshold() {
        threshold = model.accountPoolStatus?.autoSwitchThreshold ?? 80
    }
}
