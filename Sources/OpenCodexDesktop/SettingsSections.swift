import AppKit
import SwiftUI

extension SettingsView {
    var applicationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("客户端", symbol: "macwindow")
            settingRow(
                title: "在 Dock 中显示",
                detail: "关闭后同时从 Dock 和 ⌘-Tab 隐藏；仍可通过菜单栏图标打开窗口"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { applicationAppearance.showsDockIcon },
                        set: { isVisible in
                            do {
                                try applicationAppearance.setDockIconVisible(isVisible)
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            settingRow(
                title: "自动检查客户端更新",
                detail: "启动时最多每天检查一次本仓库的 GitHub Release；不会自动下载或安装"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { appUpdateManager.automaticChecksEnabled },
                        set: { appUpdateManager.setAutomaticChecksEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            settingRow(
                title: "系统通知",
                detail: "在 Core 异常退出、唤醒检查失败或更新需要处理时显示 macOS 通知"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notificationManager.isEnabled },
                        set: { enabled in Task { await notificationManager.setEnabled(enabled) } }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if notificationManager.authorizationDenied {
                Label("通知权限已被系统拒绝，请在“系统设置 › 通知”中允许 OpenCodex Desktop。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.warning)
            }

            Divider()

            clientUpdateStatus
        }
        .cardStyle()
    }

    var clientUpdateStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("客户端版本")
                        .font(.callout.weight(.medium))
                    Text("当前版本 \(appUpdateManager.currentVersion) · Apple Silicon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appUpdateManager.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let statusMessage = appUpdateManager.statusMessage {
                Label(statusMessage, systemImage: updateStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(updateStatusColor)
                    .textSelection(.enabled)
            }

            HStack {
                Button("检查更新") {
                    Task { await appUpdateManager.checkForUpdates() }
                }
                .disabled(appUpdateManager.isBusy)

                Button("Release 页面") { appUpdateManager.openReleasesPage() }

                Spacer()

                if appUpdateManager.downloadedUpdateURL != nil {
                    Button("在 Finder 中显示") { appUpdateManager.revealDownloadedUpdate() }
                    Button("打开安装镜像") { appUpdateManager.openDownloadedUpdate() }
                        .buttonStyle(.borderedProminent)
                } else if appUpdateManager.availableRelease != nil {
                    Button("下载并校验") {
                        Task { await appUpdateManager.downloadAvailableUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appUpdateManager.isBusy)
                }
            }
        }
    }

    var updateStatusSymbol: String {
        if appUpdateManager.downloadedUpdateURL != nil { return "checkmark.shield.fill" }
        if appUpdateManager.availableRelease != nil { return "arrow.down.circle.fill" }
        if appUpdateManager.lastOperationFailed {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    var updateStatusColor: Color {
        if appUpdateManager.lastOperationFailed {
            return AppPalette.warning
        }
        if appUpdateManager.availableRelease != nil { return AppPalette.accent }
        return .secondary
    }

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("连接", symbol: "network")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("主机").foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("端口").foregroundStyle(.secondary)
                    TextField("10100", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150, alignment: .leading)
                }
            }
            Text("为保护管理令牌，客户端只接受 127.0.0.1、localhost 或 ::1。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                StatusDot(state: model.connectionState)
                Text(model.connectionState.label)
                    .font(.callout.weight(.medium))
                Text("http://\(host):\(port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("应用并重连") {
                    model.connectionHost = host
                    model.connectionPort = port
                    Task { await model.saveConnection() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardStyle()
    }

    var coreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("OpenCodex 内核", symbol: "shippingbox")
                Spacer()
                Text("已选择 \(coreManager.targetRelease.version)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            coreVersionSelection

            Divider()
            coreInstallationStatus

            Label(
                "退出或意外关闭 Desktop 不会停止本地 Core；Codex 账号链路会继续运行，只有点击“停止服务”或卸载内核才会主动停止。",
                systemImage: "bolt.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            settingRow(
                title: "登录时启动",
                detail: "登录 Mac 后启动客户端与已安装的本地内核"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { value in
                            do { try loginItem.setEnabled(value) } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if loginItem.requiresApproval {
                HStack {
                    Label("需要在系统设置中批准登录项", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.warning)
                    Spacer()
                    Button("打开系统设置") { loginItem.openSystemSettings() }
                }
            }
            HStack {
                Button("查看内核日志") { model.openCoreLog() }
                    .disabled(!coreManager.installationState.isInstalled)
                Button("打开安装目录") { model.openCoreInstallationFolder() }
                    .disabled(!coreManager.installationState.isInstalled)
                Spacer()
                if coreManager.installationState.isInstalled {
                    if let rollback = coreManager.rollbackRelease {
                        Button("回滚到 \(rollback.version)") { Task { await model.rollbackCore() } }
                            .disabled(model.isRefreshing)
                    }
                    Button("卸载", role: .destructive) { confirmUninstall = true }
                    Button("重新安装") { Task { await model.installCore() } }
                    if model.isOnline || coreManager.ownsRunningProcess {
                        Button(model.isOnline ? "停止服务" : "停止启动", role: .destructive) {
                            Task { await model.stopService() }
                        }
                    } else {
                        Button("启动服务") { Task { await model.startService() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .cardStyle()
    }

    var coreVersionSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingRow(
                title: "版本策略",
                detail: coreManager.versionMode == .build
                    ? "使用随当前客户端发布并完成回归验证的默认内核"
                    : "从客户端内置的可信版本目录中选择；下载制品仍会进行完整摘要校验"
            ) {
                Picker("", selection: coreVersionModeBinding) {
                    ForEach(CoreVersionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(coreVersionSelectionDisabled)
            }

            if coreManager.versionMode == .custom {
                settingRow(
                    title: "选择 Core",
                    detail: "自选版本未随本客户端完整回归；启动失败时可切回构建版本，已有版本目录会保留。"
                ) {
                    Picker("", selection: customCoreVersionBinding) {
                        ForEach(coreManager.userSelectableReleases, id: \.version) { release in
                            Text("\(release.version) · Bun \(release.bunVersion)")
                                .tag(release.version)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(coreVersionSelectionDisabled)
                }
            }

            if coreVersionSelectionDisabled {
                Label("停止当前服务后才能切换内核版本。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var coreVersionModeBinding: Binding<CoreVersionMode> {
        Binding(
            get: { coreManager.versionMode },
            set: { coreManager.setVersionMode($0) }
        )
    }

    var customCoreVersionBinding: Binding<String> {
        Binding(
            get: { coreManager.customVersion ?? coreManager.userSelectableReleases.first?.version ?? "" },
            set: { version in
                do {
                    try coreManager.selectCustomVersion(version)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        )
    }

    var coreVersionSelectionDisabled: Bool {
        model.isOnline || coreManager.ownsRunningProcess || coreManager.installationState.isBusy
    }

    @ViewBuilder
    var coreInstallationStatus: some View {
        switch coreManager.installationState {
        case .checking:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在检查本地内核…").foregroundStyle(.secondary)
            }
        case .notInstalled:
            coreStatusRow(
                symbol: "arrow.down.circle.fill",
                color: AppPalette.accent,
                title: "内核尚未安装",
                detail: "客户端保持轻量；首次使用时单独下载经过校验的 OpenCodex Core、锁定依赖和 Bun 运行时。"
            ) {
                Button("下载并安装") { Task { await model.installCore() } }
                    .buttonStyle(.borderedProminent)
            }
        case let .installing(phase):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在安装 Core \(coreManager.targetRelease.version)")
                        .font(.callout.weight(.medium))
                    Text(phase).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .installed(manifest):
            coreStatusRow(
                symbol: "checkmark.seal.fill",
                color: AppPalette.success,
                title: "OpenCodex Core \(manifest.coreVersion)",
                detail:
                    "\(coreManager.targetIsBuildRelease ? "构建版本" : "自选版本") · 提交 \(String(manifest.coreCommit.prefix(7))) · Bun \(manifest.bunVersion)"
            ) { EmptyView() }
        case let .updateAvailable(installed, target):
            coreStatusRow(
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                color: AppPalette.warning,
                title: "已选择 Core \(target.version)",
                detail: "当前另有 Core \(installed.coreVersion) 已安装；安装所选版本后才能启动。"
            ) {
                Button("安装所选版本") { Task { await model.installCore() } }
                    .buttonStyle(.borderedProminent)
            }
        case let .failed(message):
            coreStatusRow(
                symbol: "exclamationmark.triangle.fill",
                color: AppPalette.danger,
                title: "内核安装失败",
                detail: message
            ) {
                Button("重试") { Task { await model.installCore() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    func coreStatusRow<Accessory: View>(
        symbol: String,
        color: Color,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    var securitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("安全", symbol: "lock.shield")
            HStack(spacing: 12) {
                Image(systemName: model.tokenAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(model.tokenAvailable ? AppPalette.success : AppPalette.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tokenAvailable ? "管理令牌可用" : "未找到管理令牌")
                        .font(.callout.weight(.medium))
                    Text(model.tokenPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("在 Finder 中显示") { model.openConfigFolder() }
            }
            Text("客户端只在发送本机管理请求时读取令牌，不会显示、记录或另存其内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    func settingRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    func loadValues() {
        host = model.connectionHost
        port = model.connectionPort
    }
}
