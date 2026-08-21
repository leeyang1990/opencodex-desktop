import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "概览",
                    subtitle: "本机 OpenCodex 服务与模型路由状态"
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
                    title: "服务",
                    value: model.health?.version.map { "v\($0)" } ?? "运行中",
                    detail: model.health?.pid.map { "PID \($0)" } ?? model.baseAddress,
                    symbol: "bolt.horizontal.circle.fill",
                    tint: AppPalette.success
                )
                MetricCard(
                    title: "Providers",
                    value: "\(model.enabledProviders.count) 个已启用",
                    detail: "共 \(model.providers.count) 个配置",
                    symbol: "point.3.connected.trianglepath.dotted"
                )
                MetricCard(
                    title: "默认路由",
                    value: model.defaultProvider?.name ?? model.config?.defaultProvider ?? "—",
                    detail: model.defaultProvider?.displayModel ?? "自动选择模型",
                    symbol: "arrow.triangle.branch",
                    tint: Color(red: 0.57, green: 0.35, blue: 0.92)
                )
                MetricCard(
                    title: "Codex Runtime",
                    value: model.settings?.codexRuntime?.version ?? "已连接",
                    detail: model.settings?.codexRuntime?.path ?? "等待运行时信息",
                    symbol: "terminal.fill",
                    tint: Color(red: 0.17, green: 0.62, blue: 0.77)
                )
            }

            if let warning = model.settings?.codexRuntime?.warning, !warning.isEmpty {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(AppPalette.warning)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Provider 状态")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(model.enabledProviders.count)/\(model.providers.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(model.providers.prefix(5)) { provider in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(provider.disabled ? Color.secondary.opacity(0.4) : AppPalette.success)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name).font(.callout.weight(.medium))
                            Text(provider.displayModel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Pill(text: provider.displayAuth, color: provider.disabled ? .secondary : AppPalette.accent)
                        if provider.name == model.config?.defaultProvider {
                            Pill(text: "默认", color: AppPalette.success)
                        }
                    }
                    if provider.id != model.providers.prefix(5).last?.id { Divider() }
                }
            }
            .cardStyle()
        }
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
            Text(model.connectionState == .unauthorized ? "无法访问管理 API" : "OpenCodex 尚未运行")
                .font(.title2.weight(.semibold))
            Text(
                model.connectionState == .unauthorized
                    ? "客户端需要读取本机受保护的管理令牌。启动或重启一次服务通常可以修复。"
                    : "启动本地服务后，就可以在这里管理 Provider 与运行设置。"
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            HStack {
                Button("启动服务") {
                    Task { await model.startService() }
                }
                .buttonStyle(.borderedProminent)
            }
            Text("兼容的 OpenCodex \(model.coreManager.compatibleRelease.version) 内核与应用分离安装")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .cardStyle()
    }
}
