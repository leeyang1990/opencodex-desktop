import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var coreManager = CoreManager.shared
    @ObservedObject private var eventStore = DesktopEventStore.shared
    @StateObject private var loginItem = LoginItemManager()
    @State private var showsAdvancedRuntimeOptions = false
    @State private var host = AppConstants.Connection.defaultHost
    @State private var port = AppConstants.Connection.defaultPort

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: L10n.tr("诊断"),
                    subtitle: L10n.tr("检查与修复运行问题")
                )
                .padding(.bottom, 2)

                repairCard
                if model.environmentReport.needsAttention {
                    summaryCard
                    checksCard
                }
                runtimeCard
                connectionCard
                securityAuditCard
                eventHistoryCard
                privacyNote
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            host = model.connectionHost
            port = model.connectionPort
            model.runEnvironmentCheck()
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await model.refresh()
                        model.runEnvironmentCheck()
                    }
                } label: {
                    Label(L10n.tr("重新检查"), systemImage: "arrow.clockwise")
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
            .glassControl(
                tint: (model.environmentReport.needsAttention ? AppPalette.warning : AppPalette.success)
                    .opacity(0.18)
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
                Text(L10n.tr("检查通过"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var checksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.tr("本机检查"), systemImage: "checklist")
                .font(.title3.weight(.semibold))
            EnvironmentCheckList(report: model.environmentReport)
        }
        .cardStyle()
    }

    private var repairCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.tr("安全操作"), systemImage: "wrench.and.screwdriver")
                .font(.title3.weight(.semibold))

            Text(L10n.tr("仅影响本机内核，不更改账号、渠道与路由。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if model.coreIntegrityInspection.needsRepair {
                    Button(L10n.tr("修复 Core 安装")) { Task { await model.installCore() } }
                        .shellButtonStyle(prominent: true)
                } else if !model.coreIntegrityInspection.isValid {
                    Button(L10n.tr("安装 Core")) { Task { await model.installCore() } }
                        .shellButtonStyle(prominent: true)
                } else if model.isOnline {
                    Button(L10n.tr("重启 Core")) { Task { await model.restartService() } }
                        .shellButtonStyle(prominent: true)
                } else {
                    Button(L10n.tr("启动 Core")) { Task { await model.startService() } }
                        .shellButtonStyle(prominent: true)
                        .disabled(portIsOccupied)
                }

                Button(L10n.tr("查看 Core 日志")) { model.openCoreLog() }
                    .disabled(!coreLogExists)
                Button(L10n.tr("打开安装目录")) { model.openCoreInstallationFolder() }
                    .disabled(!coreFolderExists)
                Spacer()
                Button(L10n.tr("导出诊断包")) { model.exportDiagnostics() }
            }

            if model.environmentReport.requiresLoginItemApproval {
                Divider()
                HStack {
                    Label(L10n.tr("登录项仍需在系统设置中批准"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.warning)
                    Spacer()
                    Button(L10n.tr("打开登录项设置")) { loginItem.openSystemSettings() }
                }
            }
        }
        .cardStyle()
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Codex CLI", systemImage: "terminal")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.isScanningCodexRuntimes {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.scanCodexRuntimes() }
                } label: {
                    Label(L10n.tr("重新扫描"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanningCodexRuntimes)
            }

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: runtimeStatusSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(runtimeStatusColor)
                    .frame(width: 38, height: 38)
                    .glassControl(tint: runtimeStatusColor.opacity(0.18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(runtimeStatusTitle)
                        .font(.callout.weight(.semibold))
                    Text(runtimeStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !coreRuntimeIsBound, let recommendedRuntime {
                    Button(runtimePrimaryActionTitle) {
                        Task { await model.useCodexRuntime(recommendedRuntime) }
                    }
                    .shellButtonStyle(prominent: true)
                    .disabled(model.isRefreshing || model.isScanningCodexRuntimes)
                }
            }

            Label {
                Text(L10n.tr("选择内核调用的 CLI，不更改系统命令或账号。"))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $showsAdvancedRuntimeOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    if model.codexRuntimeCandidates.isEmpty, !model.isScanningCodexRuntimes {
                        Text(L10n.tr("没有可供切换的 Codex CLI。"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.codexRuntimeCandidates.enumerated()), id: \.element.id) {
                                index, candidate in
                                runtimeRow(candidate)
                                if index < model.codexRuntimeCandidates.count - 1 { Divider() }
                            }
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.tr("切换会重启内核，保留配置。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if coreManager.preferredCodexRuntimePath != nil {
                            Button(L10n.tr("恢复自动选择")) { Task { await model.clearCodexRuntimePreference() } }
                                .disabled(model.isRefreshing)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Label(L10n.tr("更换 CLI"), systemImage: "slider.horizontal.3")
                    Spacer()
                    Text(L10n.tr("\(model.codexRuntimeCandidates.filter(\.isValid).count) 个可用版本"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout.weight(.medium))
            }
        }
        .cardStyle()
    }

    private var eventHistoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.tr("本机事件"), systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(L10n.tr("最近 7 天"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !eventStore.events.isEmpty {
                    Button(L10n.tr("清除")) { eventStore.clear() }
                }
            }

            if eventStore.events.isEmpty {
                Text(L10n.tr("暂无本机运行事件。"))
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

            Text(L10n.tr("仅记录运行状态，不含账号或请求内容。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var securityAuditCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.tr("本机安全审计"), systemImage: "lock.shield")
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
                    Text(candidate.version.map { "Codex \($0)" } ?? L10n.tr("无法验证"))
                        .font(.callout.weight(.medium))
                    Pill(text: candidate.source.title, color: .secondary)
                    if recommendedRuntime?.path == candidate.path {
                        Pill(text: L10n.tr("推荐"), color: AppPalette.success)
                    }
                    if coreUsesCandidate(candidate) {
                        Pill(text: L10n.tr("Core 当前使用"), color: AppPalette.accent)
                    } else if coreManager.preferredCodexRuntimePath == candidate.path {
                        Pill(text: L10n.tr("重启后使用"), color: AppPalette.accent)
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
            if candidate.isValid,
                !coreUsesCandidate(candidate),
                coreManager.preferredCodexRuntimePath != candidate.path
            {
                Button(candidateActionTitle) { Task { await model.useCodexRuntime(candidate) } }
                    .disabled(model.isRefreshing || model.isScanningCodexRuntimes)
            }
        }
        .padding(.vertical, 9)
    }

    private var recommendedRuntime: CodexRuntimeCandidate? {
        CodexRuntimeDiscovery.recommendedCandidate(
            from: model.codexRuntimeCandidates,
            preferredPath: coreManager.preferredCodexRuntimePath
        )
    }

    private var coreRuntimeIsBound: Bool { model.settings?.codexRuntime?.version != nil }

    private func coreUsesCandidate(_ candidate: CodexRuntimeCandidate) -> Bool {
        guard coreRuntimeIsBound, let runtimePath = model.settings?.codexRuntime?.path else { return false }
        return expandedRuntimePath(runtimePath) == candidate.path
    }

    private func expandedRuntimePath(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst()
    }

    private var runtimeStatusSymbol: String {
        if coreRuntimeIsBound { return "checkmark.circle.fill" }
        if recommendedRuntime != nil { return model.isOnline ? "link.badge.plus" : "checkmark.circle.fill" }
        return model.isScanningCodexRuntimes ? "magnifyingglass" : "exclamationmark.triangle.fill"
    }

    private var runtimeStatusColor: Color {
        if coreRuntimeIsBound || (!model.isOnline && recommendedRuntime != nil) { return AppPalette.success }
        return model.isScanningCodexRuntimes ? .secondary : AppPalette.warning
    }

    private var runtimeStatusTitle: String {
        if let version = model.settings?.codexRuntime?.version {
            return L10n.tr("Core 当前使用 Codex \(version)")
        }
        if let recommendedRuntime {
            return model.isOnline
                ? L10n.tr("Core 尚未指定 Codex CLI")
                : L10n.tr("已找到 Codex \(recommendedRuntime.version ?? "")")
        }
        return model.isScanningCodexRuntimes ? L10n.tr("正在查找 Codex CLI") : L10n.tr("未找到 Codex CLI")
    }

    private var runtimeStatusDetail: String {
        if let runtime = model.settings?.codexRuntime, runtime.version != nil {
            let path = runtime.path.map(expandedRuntimePath) ?? L10n.tr("路径未知")
            return L10n.tr("已验证版本 · \(path) · \(runtimeSourceTitle(runtime.source))")
        }
        if recommendedRuntime != nil {
            return model.isOnline
                ? L10n.tr("当前仅回退尝试系统命令 codex，版本无法确认；Codex 登录与能力识别可能不稳定。")
                : L10n.tr("Core 尚未运行；选择推荐版本后，下次启动将使用该版本。")
        }
        return model.isScanningCodexRuntimes
            ? L10n.tr("正在检查 NVM、Homebrew、Codex.app、ChatGPT.app 与系统 PATH。")
            : L10n.tr("请先安装 Codex CLI，然后重新扫描。")
    }

    private var runtimePrimaryActionTitle: String {
        model.isOnline || coreManager.ownsRunningProcess
            ? L10n.tr("让 Core 使用推荐版本并重启")
            : L10n.tr("让 Core 下次使用推荐版本")
    }

    private var candidateActionTitle: String {
        model.isOnline || coreManager.ownsRunningProcess
            ? L10n.tr("让 Core 使用此版本并重启")
            : L10n.tr("让 Core 使用此版本")
    }

    private func runtimeSourceTitle(_ source: String?) -> String {
        switch source {
        case "environment": L10n.tr("Desktop 指定")
        case "configured": L10n.tr("Core 已保存")
        case "shim": L10n.tr("应用运行环境")
        case "path": L10n.tr("系统 PATH")
        default: source ?? L10n.tr("自动发现")
        }
    }

    /// Connection and token surface. It lives here, next to the other low-level state, instead of
    /// occupying the main settings page.
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.tr("连接"), systemImage: "network")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.tr("主机")).foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200, alignment: .leading)
                }
                GridRow {
                    Text(L10n.tr("端口")).foregroundStyle(.secondary)
                    TextField("10100", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120, alignment: .leading)
                }
            }

            HStack(spacing: 10) {
                StatusDot(state: model.connectionState)
                Text(model.connectionState.label)
                    .font(.callout.weight(.medium))
                Text("http://\(host):\(port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("应用并重连")) {
                    model.connectionHost = host
                    model.connectionPort = port
                    Task { await model.saveConnection() }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: model.tokenAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(model.tokenAvailable ? AppPalette.success : AppPalette.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tokenAvailable ? L10n.tr("管理令牌可用") : L10n.tr("未找到管理令牌"))
                        .font(.callout.weight(.medium))
                    Text(model.tokenPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(L10n.tr("在 Finder 中显示")) { model.openConfigFolder() }
            }

            Text(L10n.tr("客户端只在本机回环请求中使用令牌，不会显示、记录或另存其内容。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var privacyNote: some View {
        Label {
            Text(L10n.tr("诊断包不会包含 API Key、管理令牌内容、账号标识、请求正文或内核原始日志。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(AppPalette.accent)
        }
    }

    private var passedCount: Int {
        model.environmentReport.items.filter { $0.state == .passed }.count
    }

    private var attentionCount: Int {
        model.environmentReport.items.filter { $0.state == .attention }.count
    }

    private var summaryTitle: String {
        attentionCount == 0 ? L10n.tr("本机环境状态良好") : L10n.tr("发现 \(attentionCount) 个需要处理的项目")
    }

    private var summaryDetail: String {
        guard let checkedAt = model.environmentReport.checkedAt else { return L10n.tr("正在读取本机状态…") }
        return L10n.tr("最近检查：\(checkedAt.formatted(date: .abbreviated, time: .standard))")
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
