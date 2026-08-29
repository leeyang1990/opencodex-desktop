import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var coreManager = CoreManager.shared
    @ObservedObject private var eventStore = DesktopEventStore.shared
    @StateObject private var loginItem = LoginItemManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "诊断与修复",
                    subtitle: "即使 Core 无法启动，也能检查本机安装、端口、运行时与系统环境"
                )

                summaryCard
                checksCard
                runtimeCard
                securityAuditCard
                eventHistoryCard
                repairCard
                privacyCard
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.runEnvironmentCheck() }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await model.refresh()
                        model.runEnvironmentCheck()
                    }
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 18) {
            Image(
                systemName: model.environmentReport.needsAttention ? "stethoscope.circle.fill" : "checkmark.shield.fill"
            )
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(model.environmentReport.needsAttention ? AppPalette.warning : AppPalette.success)
            .frame(width: 58, height: 58)
            .background(
                (model.environmentReport.needsAttention ? AppPalette.warning : AppPalette.success).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(summaryTitle)
                    .font(.title3.weight(.semibold))
                Text(summaryDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(passedCount)/\(model.environmentReport.items.count)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("检查通过")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var checksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("本机检查", systemImage: "checklist")
                .font(.title3.weight(.semibold))
            EnvironmentCheckList(report: model.environmentReport)
        }
        .cardStyle()
    }

    private var repairCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("安全操作", systemImage: "wrench.and.screwdriver")
                .font(.title3.weight(.semibold))

            Text("这些操作只影响 Desktop 自己安装的 Core 和本机启动状态，不会修改 Provider、账号、模型或 Codex Base URL。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if model.coreIntegrityInspection.needsRepair {
                    Button("修复 Core 安装") { Task { await model.installCore() } }
                        .buttonStyle(.borderedProminent)
                } else if !model.coreIntegrityInspection.isValid {
                    Button("安装 Core") { Task { await model.installCore() } }
                        .buttonStyle(.borderedProminent)
                } else if model.isOnline {
                    Button("重启 Core") { Task { await model.restartService() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("启动 Core") { Task { await model.startService() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(portIsOccupied)
                }

                Button("查看 Core 日志") { model.openCoreLog() }
                    .disabled(!coreLogExists)
                Button("打开安装目录") { model.openCoreInstallationFolder() }
                    .disabled(!coreFolderExists)
                Spacer()
                Button("导出诊断包") { model.exportDiagnostics() }
            }

            if model.environmentReport.requiresLoginItemApproval {
                Divider()
                HStack {
                    Label("登录项仍需在系统设置中批准", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.warning)
                    Spacer()
                    Button("打开登录项设置") { loginItem.openSystemSettings() }
                }
            }
        }
        .cardStyle()
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Codex Runtime", systemImage: "terminal")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.isScanningCodexRuntimes {
                    ProgressView().controlSize(.small)
                }
                Button("重新扫描") { Task { await model.scanCodexRuntimes() } }
                    .disabled(model.isScanningCodexRuntimes)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(
                    systemName: model.settings?.codexRuntime?.version == nil
                        ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(model.settings?.codexRuntime?.version == nil ? AppPalette.warning : AppPalette.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Core 当前使用")
                        .font(.callout.weight(.medium))
                    Text(coreRuntimeDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if coreManager.preferredCodexRuntimePath != nil {
                    Button("恢复自动选择") { Task { await model.clearCodexRuntimePreference() } }
                }
            }

            Divider()

            if model.codexRuntimeCandidates.isEmpty, !model.isScanningCodexRuntimes {
                Text("未发现可验证的 Codex CLI。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.codexRuntimeCandidates.enumerated()), id: \.element.id) { index, candidate in
                        runtimeRow(candidate)
                        if index < model.codexRuntimeCandidates.count - 1 { Divider() }
                    }
                }
            }

            Text("Desktop 只选择本机 Codex 可执行文件；账号登录与路由仍由 Codex 和 OpenCodex 管理。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var eventHistoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("本机事件", systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("最近 7 天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !eventStore.events.isEmpty {
                    Button("清除") { eventStore.clear() }
                }
            }

            if eventStore.events.isEmpty {
                Text("暂无本机运行事件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(eventStore.events.prefix(8).enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.kind.symbol)
                                .foregroundStyle(event.kind.isFailure ? AppPalette.warning : AppPalette.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.kind.title)
                                    .font(.callout.weight(.medium))
                                if let detail = event.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        if index < min(eventStore.events.count, 8) - 1 { Divider() }
                    }
                }
            }

            Text("只记录进程、版本、睡眠唤醒和检查结果；不记录账号、请求、Prompt 或响应内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var securityAuditCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("本机安全审计", systemImage: "lock.shield")
                .font(.title3.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(Array(model.securityAuditReport.items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: securitySymbol(item.state))
                            .foregroundStyle(securityColor(item.state))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    if index < model.securityAuditReport.items.count - 1 { Divider() }
                }
            }
        }
        .cardStyle()
    }

    private func securitySymbol(_ state: EnvironmentCheckState) -> String {
        switch state {
        case .passed: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .pending: "clock.fill"
        }
    }

    private func securityColor(_ state: EnvironmentCheckState) -> Color {
        switch state {
        case .passed: AppPalette.success
        case .attention: AppPalette.warning
        case .pending: .secondary
        }
    }

    private func runtimeRow(_ candidate: CodexRuntimeCandidate) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: candidate.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(candidate.isValid ? AppPalette.success : AppPalette.danger)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(candidate.version.map { "Codex \($0)" } ?? "无法验证")
                        .font(.callout.weight(.medium))
                    Pill(text: candidate.source.title, color: .secondary)
                    if coreManager.preferredCodexRuntimePath == candidate.path {
                        Pill(text: "当前偏好", color: AppPalette.accent)
                    }
                }
                Text(candidate.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let error = candidate.validationError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(AppPalette.warning)
                        .lineLimit(2)
                }
            }
            Spacer()
            if candidate.isValid, coreManager.preferredCodexRuntimePath != candidate.path {
                Button("使用并重启") { Task { await model.useCodexRuntime(candidate) } }
                    .disabled(model.isRefreshing)
            }
        }
        .padding(.vertical, 9)
    }

    private var coreRuntimeDetail: String {
        guard let runtime = model.settings?.codexRuntime else { return "Core 未运行或管理接口不可用。" }
        if let version = runtime.version {
            return "Codex \(version) · \(runtime.source ?? "自动发现")"
        }
        if let local = model.codexRuntimeCandidates.first(where: \.isValid) {
            return "Core 尚未验证；Mac 已发现 Codex \(local.version ?? "")。可选择后重启 Core。"
        }
        return "Core 尚未验证可用的 Codex CLI。"
    }

    private var privacyCard: some View {
        Label {
            Text("诊断包不会包含 API Key、管理令牌内容、账号标识、请求正文或 Core 原始日志。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(AppPalette.accent)
        }
        .cardStyle()
    }

    private var passedCount: Int {
        model.environmentReport.items.filter { $0.state == .passed }.count
    }

    private var attentionCount: Int {
        model.environmentReport.items.filter { $0.state == .attention }.count
    }

    private var summaryTitle: String {
        attentionCount == 0 ? "本机环境状态良好" : "发现 \(attentionCount) 个需要处理的项目"
    }

    private var summaryDetail: String {
        guard let checkedAt = model.environmentReport.checkedAt else { return "正在读取本机状态…" }
        return "最近检查：\(checkedAt.formatted(date: .abbreviated, time: .standard))"
    }

    private var portIsOccupied: Bool {
        if case .occupied = model.localPortInspection { true } else { false }
    }

    private var coreLogExists: Bool {
        FileManager.default.fileExists(atPath: CoreInstallationPaths.logFile.path)
    }

    private var coreFolderExists: Bool {
        FileManager.default.fileExists(atPath: CoreInstallationPaths.coreDirectory.path)
    }
}
