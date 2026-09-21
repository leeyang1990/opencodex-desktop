import SwiftUI

/// The common account path: sign in, choose an account, pause it, and pick a scheduling policy.
/// Fine-grained pool tuning remains in the Core console.
struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var navigation = AppNavigation.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "账号")
                    .padding(.bottom, 2)

                if !model.isOnline {
                    offlineCard
                } else {
                    poolCard
                    if let scheduling = model.scheduling { schedulingCard(scheduling) }
                    if model.loginFlowID != nil { loginCard }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task { await model.loadCodexAccounts() }
    }

    // MARK: - Pool

    private var poolCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("账号池", systemImage: "person.2")
                    .font(.title3.weight(.semibold))
                Text("\(model.codexAccounts.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoadingAccounts || model.isUpdatingAccounts {
                    ProgressView().controlSize(.small)
                }
                Button("添加账号") { Task { await model.addCodexAccount() } }
                    .shellButtonStyle(prominent: true)
                    .disabled(model.isStartingLogin || model.loginFlowID != nil)
                Button {
                    Task { await model.loadCodexAccounts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoadingAccounts)
                .help("重新读取账号")
            }

            if let message = model.accountErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.warning)
            }

            if model.codexAccounts.isEmpty {
                Text("暂无账号，添加后在浏览器中完成授权。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.codexAccounts.enumerated()), id: \.element.id) { index, account in
                        accountRow(account)
                        if index < model.codexAccounts.count - 1 {
                            Divider().opacity(0.35).padding(.leading, 14)
                        }
                    }
                }
                .glassInsetSurface()
            }
        }
        .cardStyle()
    }

    private func accountRow(_ account: CodexAccount) -> some View {
        let isActive = model.scheduling?.activeCodexAccountId == account.id
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? AppPalette.success : Color.secondary.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: .medium))
                    if account.isMain == true {
                        Pill(text: "本机登录", color: .secondary)
                    }
                    if let plan = account.plan {
                        Pill(text: plan.uppercased(), color: AppPalette.accent)
                    }
                    if account.isPaused {
                        Pill(text: "已暂停", color: AppPalette.warning, symbol: "pause.fill")
                    }
                    if account.needsReauth == true {
                        Pill(text: "需重新登录", color: AppPalette.danger, symbol: "exclamationmark.triangle.fill")
                    } else if !account.isHealthy {
                        Pill(text: account.healthLabel ?? "异常", color: AppPalette.warning)
                    }
                }
                Text(quotaDetail(account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let percent = account.quota?.weeklyPercent {
                quotaBar(percent)
            }

            Menu {
                Button("设为当前账号") { Task { await model.selectCodexAccount(account) } }
                    .disabled(isActive || account.isPaused)
                Button(account.isPaused ? "恢复使用" : "暂停使用") {
                    Task { await model.setCodexAccountPaused(account, paused: !account.isPaused) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .disabled(model.isUpdatingAccounts)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func quotaDetail(_ account: CodexAccount) -> String {
        var parts: [String] = []
        if account.quota?.weeklyResetAt != nil, let percent = account.quota?.weeklyPercent {
            parts.append(String(format: "周额度 %.0f%%", percent))
        } else if account.quota == nil {
            parts.append("无额度数据")
        }
        if let summary = account.healthSummary, account.healthLabel != nil { parts.append(summary) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func quotaBar(_ percent: Double) -> some View {
        let tint = percent >= 80 ? AppPalette.danger : (percent >= 50 ? AppPalette.warning : AppPalette.success)
        return VStack(alignment: .trailing, spacing: 3) {
            Text(String(format: "%.0f%%", percent))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(tint)
            Capsule()
                .fill(.quaternary)
                .frame(width: 54, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, 54 * min(max(percent, 0), 100) / 100), height: 4)
                }
        }
    }

    // MARK: - Scheduling

    private func schedulingCard(_ scheduling: CodexAccountScheduling) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("调度", systemImage: "arrow.triangle.branch")
                .font(.title3.weight(.semibold))

            settingRow(
                title: "账号使用方式",
                detail: schedulingHelp(scheduling.accountPoolStrategy ?? "quota")
            ) {
                Picker(
                    "",
                    selection: Binding(
                        get: { scheduling.accountPoolStrategy ?? "quota" },
                        set: { value in Task { await model.setCodexPoolStrategy(value) } }
                    )
                ) {
                    ForEach(CodexAccountScheduling.strategies, id: \.self) { strategy in
                        Text(CodexAccountScheduling.strategyTitle(strategy)).tag(strategy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                .disabled(model.isUpdatingAccounts)
            }

            if scheduling.pinned == true {
                Label("账号已固定，不会自动切换。", systemImage: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Login

    private func schedulingHelp(_ strategy: String) -> String {
        switch strategy {
        case "round-robin": "依次使用可用账号"
        case "fill-first": "当前账号用尽后切换"
        default: "优先使用额度充足的账号"
        }
    }

    private var loginCard: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在添加账号")
                    .font(.callout.weight(.medium))
                Text(model.loginMessage ?? "请在浏览器中完成授权…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { Task { await model.cancelCodexLogin() } }
        }
        .cardStyle()
    }

    private var offlineCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text("启动代理后管理账号")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("启动代理") { Task { await model.startService() } }
                .shellButtonStyle(prominent: true)
                .disabled(model.isRefreshing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardStyle()
    }

    private func settingRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            accessory()
        }
    }
}
