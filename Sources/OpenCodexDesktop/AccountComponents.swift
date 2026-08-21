import SwiftUI

struct AccountCard: View {
    let account: CodexAccount
    let isActive: Bool
    let isPinned: Bool
    let isBusy: Bool
    let onSelect: () -> Void
    let onPause: (Bool) -> Void
    let onPriority: () -> Void
    let onReauthenticate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                Image(
                    systemName: account.isMain ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.fill"
                )
                .font(.system(size: 25))
                .foregroundStyle(account.paused ? Color.secondary : AppPalette.accent)
                .frame(width: 42, height: 42)
                .background(
                    AppPalette.accent.opacity(account.paused ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(account.displayName).font(.headline)
                        if isActive { Pill(text: "当前", color: AppPalette.success) }
                        if isPinned { Pill(text: "已固定", color: AppPalette.accent) }
                        if account.isMain { Pill(text: "主账号", color: .secondary) }
                    }
                    Text(account.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Menu {
                        if !isActive && !account.paused {
                            Button("立即使用", systemImage: "checkmark.circle", action: onSelect)
                        }
                        Button("设置选择顺序", systemImage: "arrow.up.arrow.down", action: onPriority)
                        if !account.isMain {
                            Button("重新认证", systemImage: "arrow.clockwise", action: onReauthenticate)
                        }
                        Divider()
                        Button(account.paused ? "恢复账号" : "暂停账号", systemImage: account.paused ? "play" : "pause") {
                            onPause(!account.paused)
                        }
                        if !account.isMain {
                            Button("移除账号", systemImage: "trash", role: .destructive, action: onRemove)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 26, height: 26)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            HStack(spacing: 10) {
                accountStatus
                if let plan = account.plan, !plan.isEmpty {
                    Pill(text: plan.uppercased(), color: AppPalette.accent)
                }
                Text("顺序 \(account.priority)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let quota = account.quota {
                Divider()
                HStack(spacing: 20) {
                    if let value = quota.fiveHourPercent {
                        QuotaBar(title: "5 小时", percent: value)
                    }
                    if let value = quota.weeklyPercent {
                        QuotaBar(title: "每周", percent: value)
                    }
                    if let value = quota.monthlyPercent {
                        QuotaBar(title: "每月", percent: value)
                    }
                    if quota.fiveHourPercent == nil && quota.weeklyPercent == nil && quota.monthlyPercent == nil {
                        Text("暂无额度数据").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
        .opacity(account.paused ? 0.68 : 1)
    }

    private var accountStatus: some View {
        let text: String
        let color: Color
        if account.paused {
            text = "已暂停"; color = .secondary
        } else if account.needsReauth {
            text = "需要重新认证"; color = AppPalette.warning
        } else if account.isHealthy {
            text = "健康"; color = AppPalette.success
        } else {
            text = account.healthLabel ?? "受限"; color = AppPalette.warning
        }
        return Pill(text: text, color: color)
    }
}

struct QuotaBar: View {
    let title: String
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("已用 \(Int(percent.rounded()))%")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: min(max(percent, 0), 100), total: 100)
                .tint(percent >= 90 ? AppPalette.warning : AppPalette.accent)
        }
        .frame(maxWidth: 210)
    }
}

struct AccountLoginSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let account: CodexAccount?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            stateIcon
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)

            HStack {
                switch model.accountLoginState {
                case .starting:
                    Button("取消") {
                        model.cancelCodexLogin(); dismiss()
                    }
                case .waiting:
                    Button("取消") {
                        model.cancelCodexLogin(); dismiss()
                    }
                    Button("重新打开登录页") { model.reopenCodexLoginPage() }
                        .buttonStyle(.borderedProminent)
                case .completed:
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                case .failed:
                    Button("关闭") { dismiss() }
                    Button("重试") {
                        model.dismissCodexLoginResult(); model.beginCodexLogin(reauthAccount: account)
                    }
                    .buttonStyle(.borderedProminent)
                case .idle:
                    Button("关闭") { dismiss() }
                }
            }
            Spacer()

            Label("登录凭证由 OpenCodex 写入本机安全存储，客户端不会显示令牌。", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 520, height: 390)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch model.accountLoginState {
        case .starting, .waiting:
            ProgressView().controlSize(.large).frame(width: 64, height: 64)
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(AppPalette.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(
                AppPalette.warning)
        case .idle:
            Image(systemName: "person.badge.plus").font(.system(size: 48)).foregroundStyle(AppPalette.accent)
        }
    }

    private var title: String {
        switch model.accountLoginState {
        case .starting: account == nil ? "正在准备登录" : "正在准备重新认证"
        case .waiting: "在浏览器中完成登录"
        case let .completed(email): email.map { "\($0) 已连接" } ?? "账号已连接"
        case .failed: "登录失败"
        case .idle: "连接 ChatGPT 账号"
        }
    }

    private var detail: String {
        switch model.accountLoginState {
        case .starting: "OpenCodex 正在创建安全的 OAuth 登录流程。"
        case .waiting: "请选择要加入账号池的官方 ChatGPT / Codex 账号。完成后此窗口会自动更新。"
        case .completed: "账号已安全加入本机账号池，可以参与自动切换。"
        case let .failed(message): message
        case .idle: "通过 OpenAI 官方登录连接账号。"
        }
    }
}

struct AccountPriorityEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let account: CodexAccount
    @State private var priority: Int

    init(account: CodexAccount) {
        self.account = account
        _priority = State(initialValue: account.priority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置选择顺序").font(.title2.weight(.semibold))
            Text(account.displayName).foregroundStyle(.secondary)
            Stepper(value: $priority, in: -100...100) {
                HStack {
                    Text("顺序值")
                    Spacer()
                    Text("\(priority)").font(.title3.monospacedDigit().weight(.semibold))
                }
            }
            Text("数值越小越优先。手动选择账号会临时覆盖顺序，直到该账号不可用或额度达到阈值。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    Task {
                        await model.setCodexAccountPriority(account, priority: priority)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(priority == account.priority)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
