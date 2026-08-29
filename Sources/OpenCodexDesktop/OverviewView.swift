import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var navigation = AppNavigation.shared
    @ObservedObject private var eventStore = DesktopEventStore.shared

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "运行状态",
                    subtitle: "管理本机 OpenCodex Core 的安装与运行"
                )

                if model.isOnline {
                    onlineContent
                } else {
                    offlineContent
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
            }
        }
    }

    private var onlineContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                MetricCard(
                    title: "OpenCodex Core",
                    value: model.health?.version.map { "v\($0)" } ?? "运行中",
                    detail: "本机回环 · 端口 \(model.connectionPort)",
                    symbol: "bolt.horizontal.circle.fill",
                    tint: AppPalette.success
                )
                MetricCard(
                    title: "Codex Runtime",
                    value: codexRuntimeValue,
                    detail: codexRuntimeDetail,
                    symbol: "terminal.fill",
                    tint: model.settings?.codexRuntime?.version == nil ? AppPalette.warning : AppPalette.accent
                )
                MetricCard(
                    title: "稳定运行",
                    value: uptimeValue,
                    detail: model.health?.pid.map { "Core 进程 \($0)" } ?? "运行状态已连接",
                    symbol: "clock.fill",
                    tint: AppPalette.accent
                )
                MetricCard(
                    title: "本机安全",
                    value: securityValue,
                    detail: securityDetail,
                    symbol: "lock.shield.fill",
                    tint: model.securityAuditReport.needsAttention ? AppPalette.warning : AppPalette.success
                )
            }

            lifecycleCard
            recentEventsCard
        }
    }

    private var lifecycleCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "desktopcomputer.and.macbook")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 52, height: 52)
                .background(
                    AppPalette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("本机生命周期")
                    .font(.title3.weight(.semibold))
                Text("Desktop 管理 Core 进程、可信版本、睡眠唤醒检查与故障记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("诊断与修复") { navigation.show(.diagnostics) }
            Button("重启 Core") { Task { await model.restartService() } }
                .disabled(model.isRefreshing)
            Button("停止 Core", role: .destructive) { Task { await model.stopService() } }
                .disabled(model.isRefreshing)
        }
        .cardStyle()
    }

    private var recentEventsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("最近本机事件", systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("查看全部") { navigation.show(.diagnostics) }
            }

            if eventStore.events.isEmpty {
                Text("暂无运行事件。Desktop 不记录账号、Prompt 或响应内容。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(eventStore.events.prefix(4).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            Image(systemName: event.kind.symbol)
                                .foregroundStyle(event.kind.isFailure ? AppPalette.warning : AppPalette.accent)
                                .frame(width: 20)
                            Text(event.kind.title)
                                .font(.callout.weight(.medium))
                            if let detail = event.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        if index < min(eventStore.events.count, 4) - 1 { Divider() }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var offlineContent: some View {
        VStack(spacing: 18) {
            Image(
                systemName: model.connectionState == .unauthorized ? "lock.trianglebadge.exclamationmark" : "bolt.slash"
            )
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(model.connectionState == .unauthorized ? AppPalette.warning : .secondary)
            .frame(width: 72, height: 72)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(model.connectionState == .unauthorized ? "无法访问管理 API" : "OpenCodex Core 尚未运行")
                .font(.title2.weight(.semibold))
            Text(
                model.connectionState == .unauthorized
                    ? "客户端需要读取本机受保护的管理令牌。启动或重启一次服务通常可以修复。"
                    : "启动本机 Core 后，即可从 Desktop 打开 OpenCodex 控制台。"
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            HStack {
                Button("启动 Core") {
                    Task { await model.startService() }
                }
                .buttonStyle(.borderedProminent)
            }
            Text("已选择 OpenCodex \(model.coreManager.targetRelease.version) 内核，与应用分离安装")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .cardStyle()
    }

    private var codexRuntimeValue: String {
        if let version = model.settings?.codexRuntime?.version { return "v\(version)" }
        if let version = model.codexRuntimeCandidates.first(where: \.isValid)?.version { return "v\(version)" }
        return "待配置"
    }

    private var codexRuntimeDetail: String {
        if let source = model.settings?.codexRuntime?.source { return source }
        if model.codexRuntimeCandidates.contains(where: \.isValid) { return "Mac 已发现 · 等待 Core 绑定" }
        return "打开诊断选择 Runtime"
    }

    private var uptimeValue: String {
        guard let seconds = model.health?.uptime else { return "已连接" }
        let totalMinutes = max(0, Int(seconds) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }

    private var securityValue: String {
        let items = model.securityAuditReport.items
        guard !items.isEmpty else { return "检查中" }
        return "\(items.filter { $0.state == .passed }.count)/\(items.count) 通过"
    }

    private var securityDetail: String {
        model.securityAuditReport.needsAttention ? "发现需要处理的项目" : "回环监听与本机权限"
    }
}
