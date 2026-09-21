import AppKit
import Charts
import SwiftUI

/// The shell's landing surface: local service state plus shortcuts into the common configuration
/// paths. The Core console remains one click away for their full settings.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var navigation = AppNavigation.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                if model.isOnline {
                    serviceCard
                    routeCard
                    usageCard
                } else {
                    offlineCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            if model.isOnline, model.usageReport == nil {
                Task { await model.loadUsage() }
            }
        }
    }

    private var greeting: String {
        switch model.connectionState {
        case .online: "OpenCodex 已就绪"
        case .checking: "正在连接本机代理"
        case .offline: "本机代理未运行"
        case .unauthorized: "需要重新授权"
        }
    }

    // MARK: - Cards

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                iconBadge("bolt.horizontal.circle.fill", tint: AppPalette.success)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("本机代理")
                            .font(.title3.weight(.semibold))
                        Pill(
                            text: "v\(model.health?.version ?? model.coreManager.targetRelease.version)",
                            color: AppPalette.success,
                            symbol: "checkmark.seal.fill"
                        )
                    }
                    Text(model.baseAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
            }

            HStack(spacing: 8) {
                Button("复制地址", systemImage: "doc.on.doc") {
                    copy(model.baseAddress + "/v1")
                }

                Spacer(minLength: 8)

                Button("重启代理") { Task { await model.restartService() } }
                    .disabled(model.isRefreshing)
                Button("停止", role: .destructive) { Task { await model.stopService() } }
                    .disabled(model.isRefreshing)
                    .help("停止代理、还原路由，并重启正在运行的 ChatGPT")
            }
        }
        .cardStyle()
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                iconBadge(
                    "arrow.triangle.2.circlepath",
                    tint: model.settings?.isCodexRoutingInjected == false ? .secondary : AppPalette.accent
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("ChatGPT")
                        .font(.title3.weight(.semibold))
                    Text(routeDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("重启 ChatGPT") { Task { await model.restartChatGPT(reason: "首页") } }
                    .disabled(model.isRestartingChatGPT)
            }

            if model.isChatGPTRestartPending {
                Label("配置已更改，重启 ChatGPT 后生效。", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(AppPalette.warning)
            }
        }
        .cardStyle()
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("使用记录")
                        .font(.title3.weight(.semibold))
                    Text("最近 7 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.loadUsage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新使用记录")
                .disabled(model.isLoadingUsage)
            }

            if let report = model.usageReport {
                HStack(spacing: 0) {
                    usageMetric("请求", compact(report.summary.requests), "arrow.up.right")
                    Divider().frame(height: 34).padding(.horizontal, 18)
                    usageMetric("Token", compact(report.summary.totalTokens), "text.word.spacing")
                    Divider().frame(height: 34).padding(.horizontal, 18)
                    usageMetric("计量覆盖", percent(report.summary.coverageRatio), "checkmark.circle")
                    if let cost = report.summary.estimatedCostUsd {
                        Divider().frame(height: 34).padding(.horizontal, 18)
                        usageMetric("估算费用", cost.formatted(.currency(code: "USD")), "dollarsign.circle")
                    }
                }

                Chart(report.days) { day in
                    AreaMark(
                        x: .value("日期", day.shortDate),
                        y: .value("请求", day.requests)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppPalette.accent.opacity(0.38), AppPalette.accent.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    .accessibilityHidden(true)

                    LineMark(
                        x: .value("日期", day.shortDate),
                        y: .value("请求", day.requests)
                    )
                    .foregroundStyle(AppPalette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    .accessibilityLabel(day.shortDate)
                    .accessibilityValue("\(day.requests) 次请求")

                    PointMark(
                        x: .value("日期", day.shortDate),
                        y: .value("请求", day.requests)
                    )
                    .foregroundStyle(AppPalette.accent)
                    .symbolSize(day.requests > 0 ? 24 : 0)
                    .accessibilityHidden(true)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 126)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassInsetSurface()
                .accessibilityLabel("最近七天请求趋势")
            } else if model.isLoadingUsage {
                ProgressView("正在读取使用记录…")
                    .frame(maxWidth: .infinity, minHeight: 118)
            } else {
                ContentUnavailableView(
                    "暂无使用记录",
                    systemImage: "chart.xyaxis.line",
                    description: Text(model.usageErrorMessage ?? "使用代理后显示统计。")
                )
                .frame(maxWidth: .infinity, minHeight: 118)
            }
        }
        .cardStyle()
    }

    private func usageMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compact<T: BinaryInteger>(_ value: T) -> String {
        Double(value).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private var offlineCard: some View {
        VStack(spacing: 16) {
            Image(
                systemName: model.connectionState == .unauthorized
                    ? "lock.trianglebadge.exclamationmark" : "bolt.slash"
            )
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(model.connectionState == .unauthorized ? AppPalette.warning : .secondary)
            .frame(width: 64, height: 64)
            .glassControl(
                tint: (model.connectionState == .unauthorized ? AppPalette.warning : Color.secondary)
                    .opacity(0.16)
            )

            Text(model.connectionState == .unauthorized ? "连接未授权" : "代理未启动")
                .font(.title3.weight(.semibold))

            Text(
                model.connectionState == .unauthorized
                    ? "请重启代理，或打开诊断检查授权。"
                    : "退出 App 不会停止代理。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)

            HStack(spacing: 8) {
                Button("启动代理") { Task { await model.startService() } }
                    .shellButtonStyle(prominent: true)
                    .disabled(model.isRefreshing)
                Button("诊断") { openWindow(id: ShellWindow.diagnostics) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .cardStyle()
    }

    // MARK: - Copy

    private var routeDetail: String {
        switch model.settings?.isCodexRoutingInjected {
        case true: "Codex 使用本机代理"
        case false: "Codex 使用原生路由"
        default: "正在读取路由状态…"
        }
    }

    private func iconBadge(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .glassControl(tint: tint.opacity(0.18))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.operationMessage = "已复制 \(text)"
    }
}
